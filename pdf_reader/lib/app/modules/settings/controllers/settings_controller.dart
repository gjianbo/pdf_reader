import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
}
