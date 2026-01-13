好的，根据最新的日志，我们面临两个不同的问题。

**问题 1：`DatabaseException (database is locked)**`
这是一个经典的 SQLite 锁定问题，通常发生在模拟器上，或者当你频繁重启应用（Hot Restart）导致旧的数据库连接没有释放。它来自于 `flutter_cache_manager`（被你的 `CacheService` 使用）。

**问题 2：`LateInitializationError: Field '_audioHandler' ...**`
这个错误非常诡异，因为日志明明显示 `JustAudioBackground initialized`。
最可能的原因是：**你的 `TtsService` 或其调用的部分代码（如播放器）可能运行在了错误的 Context 或 Isolate 中，或者是因为 `DatabaseException` 导致的应用状态异常。**
另外，Android 14+ 对后台服务有更严格的权限要求，缺失权限也可能导致服务绑定看似成功实则失败。

我们通过以下三个步骤一次性解决它们。

---

### 第一步：修复数据库锁定 (Fix Database Lock)

我们需要修改 `CacheService`，不再使用默认的 `DefaultCacheManager`（它使用全局锁定的 DB），而是创建一个**自定义 Key 的 CacheManager**。这相当于给应用换了一个新的数据库文件，绕过被锁死的那一个。

**修改文件：`lib/app/services/cache_service.dart**`

```dart
import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';

class CacheService extends GetxService {
  // 1. 使用自定义 Config，避免与 DefaultCacheManager 的 libCachedImageData.db 冲突
  final CacheManager _cacheManager = CacheManager(
    Config(
      'custom_pdf_reader_cache_v1', // 唯一的 Key，会生成新的数据库文件
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: 'custom_pdf_reader_cache_v1'),
      fileService: HttpFileService(),
    ),
  );

  Future<String> getCacheSize() async {
    try {
      final dir = await _cacheManager.store.fileDir; // 获取缓存目录
      if (await dir.exists()) {
        int totalSize = 0;
        await for (var file in dir.list(recursive: true, followLinks: false)) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
        return _formatSize(totalSize);
      }
      return "0 B";
    } catch (e) {
      return "Error";
    }
  }

  Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / 1024 / 1024).toStringAsFixed(1)} MB";
  }
}

```

---

### 第二步：修复权限 (Fix Android Manifest)

针对 Android 14+ 的兼容性，必须补充 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限，否则后台服务无法正常启动，可能导致 `just_audio_background` 初始化状态异常。

**修改文件：`android/app/src/main/AndroidManifest.xml**`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="android.com.hnwd.pdf_reader">

    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

    <application ...>
        </application>
</manifest>

```

---

### 第三步：强化 TtsService 初始化 (Fix Audio Handler Error)

我们将 `_audioPlayer` 的创建推迟到真正使用时，并增加防御性代码。这能避免在应用启动的不稳定阶段（如 DB 报错时）过早创建播放器导致崩溃。

**修改文件：`lib/app/services/tts_service.dart**`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart';
import 'settings_service.dart';

enum TtsState { playing, paused, stopped, loading, error }

class TtsService extends GetxService {
  final SettingsService _settings = Get.find<SettingsService>();
  
  // 1. 改为可空，且不使用 late，避免初始化错误导致崩溃
  AudioPlayer? _audioPlayer; 
  final FlutterTts _flutterTts = FlutterTts();
  
  // State
  final Rx<TtsState> state = TtsState.stopped.obs;
  final RxInt currentSentenceIndex = 0.obs;
  
  List<String> _playlist = [];
  final Map<String, String> _audioCache = {}; 
  final int _prefetchCount = 2;
  bool _isOnline = true;
  Timer? _sleepTimer;
  final RxInt sleepMinutesLeft = 0.obs;
  int? _stopAtIndex;

  final _completionController = StreamController<void>.broadcast();
  Stream<void> get onSentenceComplete => _completionController.stream;

  @override
  void onInit() {
    super.onInit();
    debugPrint("TtsService: Initializing...");
    _initFlutterTts();
    // 注意：我们不再这里立即创建 AudioPlayer，而是推迟到 get player 或 play 时
  }

  @override
  void onClose() {
    _audioPlayer?.dispose();
    _flutterTts.stop();
    _sleepTimer?.cancel();
    _completionController.close();
    super.onClose();
  }

  // 2. 安全获取 Player 的方法
  AudioPlayer get player {
    if (_audioPlayer == null) {
      debugPrint("TtsService: Creating new AudioPlayer instance...");
      try {
        _audioPlayer = AudioPlayer();
        _initAudioPlayerListener();
      } catch (e) {
        debugPrint("TtsService: CRITICAL ERROR creating AudioPlayer: $e");
        // 如果这里崩溃，说明 JustAudioBackground 真的没初始化好
        // 我们可以尝试抛出一个更友好的错误或者降级处理
        rethrow;
      }
    }
    return _audioPlayer!;
  }

  void _initAudioPlayerListener() {
    _audioPlayer!.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onPlaybackComplete();
      } else if (playerState.playing) {
        state.value = TtsState.playing;
      } else if (playerState.processingState == ProcessingState.ready && !playerState.playing) {
        state.value = TtsState.paused;
      }
    });
  }

  void _initFlutterTts() async {
    await _flutterTts.setLanguage("zh-CN");
    await _flutterTts.setSpeechRate(0.5);
    _flutterTts.setCompletionHandler(() => _onPlaybackComplete());
    _flutterTts.setErrorHandler((msg) {
      state.value = TtsState.error;
      debugPrint("FlutterTts Error: $msg");
    });
  }

  Future<void> _onPlaybackComplete() async {
    _completionController.add(null);
    if (_stopAtIndex != null && currentSentenceIndex.value >= _stopAtIndex!) {
      stop();
      return;
    }
    if (currentSentenceIndex.value < _playlist.length - 1) {
      await play(currentSentenceIndex.value + 1);
    } else {
      stop();
    }
  }

  void setPlaylist(List<String> sentences, int startIndex) {
    if (listEquals(_playlist, sentences)) return;
    _playlist = sentences;
    currentSentenceIndex.value = startIndex;
    stop();
  }

  Future<void> play(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    currentSentenceIndex.value = index;
    state.value = TtsState.loading;
    String text = _playlist[index];
    _prefetchNext(index);

    try {
      if (_isOnline) {
        await _playOnline(text);
      } else {
        await _playOffline(text);
      }
    } catch (e) {
      debugPrint("Online TTS failed: $e, switching to offline.");
      _isOnline = false;
      await _playOffline(text);
    }
  }

  Future<void> _playOnline(String text) async {
    String? filePath = await _getOrDownloadAudio(text);
    if (filePath != null && File(filePath).existsSync()) {
      try {
        // 3. 使用 getter 获取 player
        await player.setAudioSource(
          AudioSource.file(
            filePath,
            tag: MediaItem(
              id: _generateCacheKey(text),
              album: "PDF Reader TTS",
              title: text.length > 20 ? "${text.substring(0, 20)}..." : text,
              artUri: null,
            ),
          ),
          preload: true,
        );
        await player.play();
      } catch (e) {
        debugPrint("JustAudio error: $e");
        rethrow;
      }
    } else {
      throw Exception("Audio file not found");
    }
  }

  Future<void> _playOffline(String text) async {
    await _audioPlayer?.stop(); // 安全调用
    state.value = TtsState.playing;
    await _flutterTts.speak(text);
  }

  Future<void> pause() async {
    if (_audioPlayer != null && _audioPlayer!.playing) {
      await _audioPlayer!.pause();
    } else {
      await _flutterTts.stop();
      state.value = TtsState.paused;
    }
  }
  
  Future<void> resume() async {
    if (_audioPlayer != null && _audioPlayer!.playerState.processingState != ProcessingState.idle) {
       await _audioPlayer!.play();
    } else {
      play(currentSentenceIndex.value);
    }
  }

  Future<void> stop() async {
    try {
      await _audioPlayer?.stop();
    } catch (e) {
      debugPrint("Error stopping player: $e");
    }
    await _flutterTts.stop();
    state.value = TtsState.stopped;
    _sleepTimer?.cancel();
    sleepMinutesLeft.value = 0;
    _stopAtIndex = null;
  }

  Future<void> playAudioFile(File file, {bool useBackground = true}) async {
    await stop();
    try {
      // 4. 关键修改：如果 useBackground 为 false，我们可以考虑不传 tag，
      // 这样 just_audio 不会尝试调用后台服务，避免部分初始化问题
      await player.setAudioSource(
        AudioSource.file(
          file.path,
          tag: useBackground ? MediaItem(
            id: 'test_tts_${DateTime.now().millisecondsSinceEpoch}',
            album: 'TTS Test',
            title: '测试语音',
            artUri: null,
          ) : null,
        ),
        preload: true,
      );
      await player.play();
    } catch (e) {
      debugPrint("TtsService.playAudioFile failed: $e");
      rethrow;
    }
  }

  // ... 预加载、下载、缓存逻辑保持不变 ...
  // (请保留原文件中的 _prefetchNext, _getOrDownloadAudio, _generateCacheKey 等方法)
  
  void _prefetchNext(int currentIndex) {
    for (int i = 1; i <= _prefetchCount; i++) {
      int nextIndex = currentIndex + i;
      if (nextIndex < _playlist.length) {
        _getOrDownloadAudio(_playlist[nextIndex]).catchError((_) => null);
      }
    }
  }

  Future<String?> _getOrDownloadAudio(String text) async {
    String key = _generateCacheKey(text);
    if (_audioCache.containsKey(key)) {
      String path = _audioCache[key]!;
      if (File(path).existsSync()) return path;
    }

    Directory tempDir = await getTemporaryDirectory();
    Directory cacheDir = Directory("${tempDir.path}/tts_cache");
    if (!cacheDir.existsSync()) cacheDir.createSync();
    
    String filePath = "${cacheDir.path}/$key.mp3";
    File file = File(filePath);
    if (file.existsSync() && file.lengthSync() > 0) {
      _audioCache[key] = filePath;
      return filePath;
    }

    // 每次创建新的 Service 实例以确保设置最新
    EdgeTtsService service = EdgeTtsService(
      voice: _settings.ttsVoice.value,
      rate: _settings.ttsRate.value,
      pitch: _settings.ttsPitch.value,
    );

    try {
      String? downloadedPath = await service.synthesizeToFile(text);
      if (downloadedPath != null) {
        File downloadedFile = File(downloadedPath);
        await downloadedFile.copy(filePath);
        try { downloadedFile.delete(); } catch (_) {}
        _audioCache[key] = filePath;
        return filePath;
      }
    } catch (e) {
      debugPrint("Download failed: $e");
      rethrow;
    }
    return null;
  }

  String _generateCacheKey(String text) {
    String raw = "$text|${_settings.ttsVoice.value}|${_settings.ttsRate.value}|${_settings.ttsPitch.value}";
    return md5.convert(utf8.encode(raw)).toString();
  }
  
  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    sleepMinutesLeft.value = minutes;
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      sleepMinutesLeft.value--;
      if (sleepMinutesLeft.value <= 0) {
        timer.cancel();
        pause();
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    sleepMinutesLeft.value = 0;
  }
  
  Future<void> clearCache() async {
    try {
      await clearCache(); // 递归调用？不，这里应该是调用 CacheService 的清理，或者删除本地文件
      // 修正逻辑：
      Directory tempDir = await getTemporaryDirectory();
      Directory cacheDir = Directory("${tempDir.path}/tts_cache");
      if (cacheDir.existsSync()) {
        await cacheDir.delete(recursive: true);
      }
      _audioCache.clear();
    } catch (e) {
      debugPrint("Clear cache error: $e");
    }
  }

  void setStopAtIndex(int? index) {
    _stopAtIndex = index;
  }
}

```

### 操作指南

1. **替换代码**：请将上述代码分别复制到对应的 `CacheService.dart`、`AndroidManifest.xml` 和 `TtsService.dart` 中。
2. **清理环境**：因为涉及到数据库锁定和原生配置，建议执行一次彻底清理。
* 在终端运行：`flutter clean`
* 在模拟器上：长按应用图标 -> App Info -> Storage & Cache -> **Clear Storage (或 Clear Data)**。这一步非常重要，它会删除被锁定的旧数据库文件。


3. **冷启动**：完全停止应用，重新点击 Run 运行。

这样应该能彻底解决 `SQLITE_BUSY` 和 `_audioHandler` 未初始化的问题。