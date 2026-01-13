import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart';
import 'package:pdf_reader/app/services/settings_service.dart';
import 'package:pdf_reader/app/services/cache_service.dart';
import 'package:pdf_reader/app/services/webdav_service.dart';
import 'package:pdf_reader/app/services/tts_service.dart';

class SettingsController extends GetxController {
  final SettingsService settings = Get.find();
  final CacheService _cacheService = Get.find();
  final WebDavService _webDavService = Get.find();
  final TtsService _ttsService = Get.find<TtsService>(); // 复用 TtsService

  // WebDAV Text Controllers
  final webdavUrlCtrl = TextEditingController();
  final webdavUserCtrl = TextEditingController();
  final webdavPasswordCtrl = TextEditingController();

  final RxString cacheSize = "Calculating...".obs;
  
  // Test Player
  // 不再在 SettingsController 中维护单独的 AudioPlayer，
  // 而是复用 TtsService 的单例，避免 just_audio_background 的多实例冲突。
  // final AudioPlayer _testPlayer = AudioPlayer(); // Removed

  @override
  void onInit() {
    super.onInit();
    webdavUrlCtrl.text = settings.webdavUrl.value;
    webdavUserCtrl.text = settings.webdavUser.value;
    webdavPasswordCtrl.text = settings.webdavPassword.value;
    
    updateCacheSize();
  }
  
  @override
  void onClose() {
    // _testPlayer.dispose(); // Removed
    webdavUrlCtrl.dispose();
    webdavUserCtrl.dispose();
    webdavPasswordCtrl.dispose();
    super.onClose();
  }

  Future<void> saveWebDavSettings() async {
    settings.webdavUrl.value = webdavUrlCtrl.text;
    settings.webdavUser.value = webdavUserCtrl.text;
    settings.webdavPassword.value = webdavPasswordCtrl.text;
    
    try {
      await _webDavService.testConnection();
      Get.snackbar("WebDAV", "配置已保存并连接成功");
    } catch (e) {
      Get.snackbar("WebDAV", "配置已保存，但连接失败: $e", 
        backgroundColor: Colors.red.withValues(alpha: 0.2),
        colorText: Colors.red,
      );
    }
  }

  Future<void> updateCacheSize() async {
    cacheSize.value = await _cacheService.getCacheSize();
  }

  Future<void> clearCache() async {
    await _cacheService.clearCache();
    await updateCacheSize();
    Get.snackbar("缓存", "缓存已清理");
  }

  Future<void> backup() async {
    try {
      Get.showOverlay(asyncFunction: () async {
        await _webDavService.backup();
      }, loadingWidget: const Center(child: CircularProgressIndicator()));
      Get.snackbar("备份", "云端备份成功");
    } catch (e) {
      Get.snackbar("错误", "备份失败: $e");
    }
  }

  Future<void> restore() async {
    try {
      Get.showOverlay(asyncFunction: () async {
        await _webDavService.restore();
      }, loadingWidget: const Center(child: CircularProgressIndicator()));
      Get.snackbar("恢复", "数据恢复成功");
    } catch (e) {
      Get.snackbar("错误", "恢复失败: $e");
    }
  }

  /// 测试 Edge TTS
  Future<void> testEdgeTts() async {
    // 显示加载对话框
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      debugPrint("EdgeTTS Test: Starting...");
      
      final service = EdgeTtsService(
        voice: settings.ttsVoice.value,
        rate: settings.ttsRate.value,
        pitch: settings.ttsPitch.value,
      );
      
      final text = "你好，这是一个测试语音。";
      debugPrint("EdgeTTS Test: Synthesizing text: $text");

      // 增加超时控制 (15秒)
      final filePath = await service.synthesizeToFile(text).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException("连接服务器超时，请检查网络");
        },
      );
      
      debugPrint("EdgeTTS Test: File path generated: $filePath");

      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          debugPrint("EdgeTTS Test: File exists, size: ${await file.length()} bytes");
          
          // 注意：just_audio_background 需要在 init 之后才能使用 AudioSource.uri/file 并且带 tag
          // 如果没有 tag，默认行为取决于配置。
          // 这里的错误 Field '_audioHandler' has not been initialized 是因为 JustAudioBackground.init 还没完成
          // 或者我们在非后台模式下错误地触发了后台逻辑。
          
          // 对于简单的测试播放，我们不需要后台控制，可以尝试不使用 tag，
          // 但 setFilePath 默认会尝试使用 AudioSource.file
          
          try {
            // 调用 TtsService 的测试播放方法
            // 测试模式下关闭后台服务支持，避免因初始化问题导致无法试听
            await _ttsService.playAudioFile(file, useBackground: false);
            debugPrint("EdgeTTS Test: Playing started");
          } catch (playerError) {
             debugPrint("EdgeTTS Test Player Error: $playerError");
             throw Exception("播放器初始化失败: $playerError");
          }
        } else {
          throw Exception("生成的音频文件不存在");
        }
      } else {
        throw Exception("生成路径为空");
      }

      // 关闭加载框
      if (Get.isDialogOpen ?? false) Get.back();
      
    } catch (e) {
      debugPrint("EdgeTTS Test Failed: $e");
      
      // 关闭加载框
      if (Get.isDialogOpen ?? false) Get.back();
      
      Get.snackbar(
        "TTS 测试失败", 
        e.toString(),
        backgroundColor: Colors.red.withValues(alpha: 0.2),
        colorText: Colors.red,
        duration: const Duration(seconds: 5),
      );
    }
  }
}
