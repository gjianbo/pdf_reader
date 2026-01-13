import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart';
import 'package:pdf_reader/app/services/settings_service.dart';
import 'package:pdf_reader/app/services/cache_service.dart';
import 'package:pdf_reader/app/services/webdav_service.dart';

class SettingsController extends GetxController {
  final SettingsService settings = Get.find();
  final CacheService _cacheService = Get.find();
  final WebDavService _webDavService = Get.find();

  // WebDAV Text Controllers
  final webdavUrlCtrl = TextEditingController();
  final webdavUserCtrl = TextEditingController();
  final webdavPasswordCtrl = TextEditingController();

  final RxString cacheSize = "Calculating...".obs;
  
  // Test Player
  final AudioPlayer _testPlayer = AudioPlayer();

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
    _testPlayer.dispose();
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
          
          await _testPlayer.setFilePath(filePath);
          await _testPlayer.play();
          debugPrint("EdgeTTS Test: Playing started");
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
