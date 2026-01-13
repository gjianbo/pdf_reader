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
  
  // 1. 移除 static 单例，完全依赖 GetX 管理
  // static final TtsService _instance = TtsService._internal(); ...
  
  // 2. 将 _audioPlayer 改为 late，不在定义时初始化
  late AudioPlayer _audioPlayer; 
  final FlutterTts _flutterTts = FlutterTts();
  
  // State
  final Rx<TtsState> state = TtsState.stopped.obs;
  final RxInt currentSentenceIndex = 0.obs;
  
  // Data
  List<String> _playlist = [];
  
  // Cache
  final Map<String, String> _audioCache = {}; 
  final int _prefetchCount = 2;
  bool _isOnline = true;

  // Sleep Timer
  Timer? _sleepTimer;
  final RxInt sleepMinutesLeft = 0.obs;
  int? _stopAtIndex;

  final _completionController = StreamController<void>.broadcast();
  Stream<void> get onSentenceComplete => _completionController.stream;

  // 3. 在 onInit 中初始化 Player，确保 main.dart 中的 JustAudioBackground.init 已经跑完
  @override
  void onInit() {
    super.onInit();
    debugPrint("TtsService: Initializing...");
    _audioPlayer = AudioPlayer(); // 这里创建 Player 才是安全的
    _initAudioPlayer();
    _initFlutterTts();
  }

  @override
  void onClose() {
    _audioPlayer.dispose();
    _flutterTts.stop();
    _sleepTimer?.cancel();
    _completionController.close();
    super.onClose();
  }
  
  void _initFlutterTts() async {
    await _flutterTts.setLanguage("zh-CN");
    await _flutterTts.setSpeechRate(0.5);
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
        await _audioPlayer.setAudioSource(
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
        await _audioPlayer.play();
      } catch (e) {
        debugPrint("JustAudio error: $e");
        rethrow;
      }
    } else {
      throw Exception("Audio file not found");
    }
  }

  Future<void> _playOffline(String text) async {
    await _audioPlayer.stop();
    state.value = TtsState.playing;
    await _flutterTts.speak(text);
  }

  Future<void> pause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _flutterTts.stop();
      state.value = TtsState.paused;
    }
  }
  
  Future<void> resume() async {
    if (_audioPlayer.playerState.processingState != ProcessingState.idle) {
       await _audioPlayer.play();
    } else {
      play(currentSentenceIndex.value);
    }
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
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
      await _audioPlayer.setAudioSource(
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
      await _audioPlayer.play();
    } catch (e) {
      debugPrint("TtsService.playAudioFile failed: $e");
      rethrow;
    }
  }

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
