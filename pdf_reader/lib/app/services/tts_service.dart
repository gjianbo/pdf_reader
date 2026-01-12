import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart';
import 'settings_service.dart';

enum TtsState { playing, paused, stopped, loading, error }

class TtsService extends GetxService {
  final SettingsService _settings = Get.find<SettingsService>();
  
  // Players
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  // EdgeTtsService _edgeTts; // Removed unused field

  // State
  final Rx<TtsState> state = TtsState.stopped.obs;
  final RxInt currentSentenceIndex = 0.obs;
  
  // Data
  List<String> _playlist = [];
  
  // Cache & Prefetch
  // MD5(text + voice + rate + pitch) -> FilePath
  final Map<String, String> _audioCache = {}; 
  final int _prefetchCount = 2; // 预加载下两句
  bool _isOnline = true; // 简单的网络状态标记 (可通过 connectivity_plus 增强)

  // Sleep Timer
  Timer? _sleepTimer;
  final RxInt sleepMinutesLeft = 0.obs;
  int? _stopAtIndex; // 播完本章的停止索引

  // Stream Controllers
  final _completionController = StreamController<void>.broadcast();
  Stream<void> get onSentenceComplete => _completionController.stream;

  @override
  void onInit() {
    super.onInit();
    // _initEdgeTts(); // Not needed as we create instance on demand
    _initFlutterTts();
    _initAudioPlayer();
  }

/*
  void _initEdgeTts() {
    _edgeTts = EdgeTtsService(
      voice: _settings.ttsVoice.value,
      rate: _settings.ttsRate.value,
      pitch: _settings.ttsPitch.value,
    );
    
    // 监听设置变化重建 EdgeTts 实例 (如果需要)
    // 实际播放时我们会每次检查参数，这里主要初始化默认值
  }
*/

  void _initFlutterTts() async {
    await _flutterTts.setLanguage("zh-CN");
    await _flutterTts.setSpeechRate(0.5); // FlutterTts rate is 0.0 to 1.0
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    
    _flutterTts.setCompletionHandler(() {
      _onPlaybackComplete();
    });
    
    _flutterTts.setErrorHandler((msg) {
      state.value = TtsState.error;
      debugPrint("FlutterTts Error: $msg");
    });
  }

  void _initAudioPlayer() {
    _audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onPlaybackComplete();
      } else if (playerState.playing) {
        state.value = TtsState.playing;
      } else if (playerState.processingState == ProcessingState.ready && !playerState.playing) {
        state.value = TtsState.paused;
      }
    });
  }

  Future<void> _onPlaybackComplete() async {
    _completionController.add(null); // 通知外部
    
    // 检查是否到达预定的停止索引 (播完本章)
    if (_stopAtIndex != null && currentSentenceIndex.value >= _stopAtIndex!) {
      stop();
      return;
    }
    
    // 自动播放下一句
    if (currentSentenceIndex.value < _playlist.length - 1) {
      // 这里的逻辑最好由 Controller 控制，或者在这里自动切
      // 为了保持 Service 纯粹，我们只通知 Controller，让 Controller 调用 playNext
      // 但为了实现"无缝"，最好在这里直接处理
      
      // 暂时策略：Service 只负责播放当前，通知结束，由 Controller 决定是否下一首
      // 不过为了 0 延迟，Service 内部自动播放下一首是最高效的
      
      // 我们采用混合模式：自动播放下一句，并更新 index
      // Controller 监听 currentSentenceIndex 变化来更新 UI
      await play(currentSentenceIndex.value + 1);
    } else {
      stop();
    }
  }

  /// 设置播放列表
  void setPlaylist(List<String> sentences, int startIndex) {
    // 如果播放列表相同，不打断播放
    if (listEquals(_playlist, sentences)) {
      // 可以在这里更新 startIndex 吗？
      // 如果正在播放，强制跳转可能不好。
      // 让 Controller 决定是否跳转。
      return;
    }
    _playlist = sentences;
    currentSentenceIndex.value = startIndex;
    stop(); // 重置状态
  }

  /// 播放指定索引的句子
  Future<void> play(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    
    currentSentenceIndex.value = index;
    state.value = TtsState.loading;
    String text = _playlist[index];

    // 1. 触发预加载 (异步，不阻塞当前播放)
    _prefetchNext(index);

    // 2. 尝试获取当前句子的音频
    try {
      if (_isOnline) {
        await _playOnline(text);
      } else {
        await _playOffline(text);
      }
    } catch (e) {
      debugPrint("Online TTS failed: $e, switching to offline.");
      _isOnline = false; // 暂时标记为离线
      await _playOffline(text);
    }
  }

  Future<void> _playOnline(String text) async {
    String? filePath = await _getOrDownloadAudio(text);
    if (filePath != null && File(filePath).existsSync()) {
      await _audioPlayer.setFilePath(filePath);
      await _audioPlayer.play();
    } else {
      throw Exception("Audio file not found or download failed");
    }
  }

  Future<void> _playOffline(String text) async {
    // 停止 just_audio
    await _audioPlayer.stop();
    state.value = TtsState.playing; // FlutterTts 状态管理较弱，手动设为 playing
    await _flutterTts.speak(text);
  }

  Future<void> pause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _flutterTts.stop(); // FlutterTts pause 行为不一致，通常用 stop
      state.value = TtsState.paused;
    }
  }
  
  Future<void> resume() async {
    if (_audioPlayer.playerState.processingState != ProcessingState.idle) {
       await _audioPlayer.play();
    } else {
      // 如果是离线 TTS 被暂停（stop），resume 需要重头读
      play(currentSentenceIndex.value);
    }
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    await _flutterTts.stop();
    state.value = TtsState.stopped;
    _sleepTimer?.cancel();
    sleepMinutesLeft.value = 0;
    _stopAtIndex = null;
  }

  /// 预加载逻辑
  void _prefetchNext(int currentIndex) {
    for (int i = 1; i <= _prefetchCount; i++) {
      int nextIndex = currentIndex + i;
      if (nextIndex < _playlist.length) {
        // 这里的 await 不会阻塞主线程的 play，因为 _prefetchNext 是 void async 但没被 await
        _getOrDownloadAudio(_playlist[nextIndex]).catchError((e) {
          debugPrint("Prefetch error for index $nextIndex: $e");
          return null;
        });
      }
    }
  }

  /// 获取或下载音频文件
  /// 返回本地文件路径
  Future<String?> _getOrDownloadAudio(String text) async {
    // 生成唯一缓存 Key
    String key = _generateCacheKey(text);
    
    // 1. 检查内存缓存
    if (_audioCache.containsKey(key)) {
      String path = _audioCache[key]!;
      if (File(path).existsSync()) {
        return path;
      } else {
        _audioCache.remove(key);
      }
    }

    // 2. 检查磁盘文件 (持久化缓存)
    Directory tempDir = await getTemporaryDirectory();
    Directory cacheDir = Directory("${tempDir.path}/tts_cache");
    if (!cacheDir.existsSync()) {
      cacheDir.createSync();
    }
    String filePath = "${cacheDir.path}/$key.mp3";
    File file = File(filePath);
    
    if (file.existsSync() && file.lengthSync() > 0) {
      _audioCache[key] = filePath;
      return filePath;
    }

    // 3. 必须下载
    // 确保参数是最新的
    // 这里我们直接用一个新的 EdgeTtsService 实例或者更新参数，确保设置生效
    // 为了性能，我们尽量复用，但 settings 可能会变。
    // 简单起见，这里假设 settings 变更不频繁，或者在变更时我们做了其他处理。
    // 如果需要严格一致，这里应该重新 new EdgeTtsService
    EdgeTtsService service = EdgeTtsService(
      voice: _settings.ttsVoice.value,
      rate: _settings.ttsRate.value,
      pitch: _settings.ttsPitch.value,
    );

    try {
      // edge_tts_dart 默认生成随机文件名，我们需要移动或重命名
      // 但 edge_tts_dart 目前的 API 可能只返回路径
      String? downloadedPath = await service.synthesizeToFile(text);
      if (downloadedPath != null) {
        File downloadedFile = File(downloadedPath);
        await downloadedFile.copy(filePath); // 移动到我们的缓存目录并重命名
        try {
          downloadedFile.delete(); // 删除临时文件
        } catch (_) {}
        
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

  void setStopAtIndex(int? index) {
    _stopAtIndex = index;
  }

  /// 睡眠定时器
  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    sleepMinutesLeft.value = minutes;
    
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      sleepMinutesLeft.value--;
      if (sleepMinutesLeft.value <= 0) {
        timer.cancel();
        pause(); // 暂停播放
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    sleepMinutesLeft.value = 0;
  }
  
  /// 清理缓存
  Future<void> clearCache() async {
    try {
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

  @override
  void onClose() {
    _audioPlayer.dispose();
    _flutterTts.stop();
    _completionController.close();
    _sleepTimer?.cancel();
    super.onClose();
  }
}
