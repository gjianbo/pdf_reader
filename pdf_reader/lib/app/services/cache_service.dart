import 'dart:io';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

class CacheService extends GetxService {
  
  @override
  void onInit() {
    super.onInit();
    // 启动时自动清理过期缓存
    autoClean();
  }
  
  /// 获取缓存大小 (格式化字符串)
  Future<String> getCacheSize() async {
    int totalSize = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      final ttsCacheDir = Directory("${tempDir.path}/tts_cache");
      
      if (ttsCacheDir.existsSync()) {
         await for (var file in ttsCacheDir.list(recursive: true, followLinks: false)) {
           if (file is File) {
             totalSize += await file.length();
           }
         }
      }
    } catch (e) {
      return "0 B";
    }
    
    return _formatSize(totalSize);
  }

  /// 一键清理缓存
  Future<void> clearCache() async {
     final tempDir = await getTemporaryDirectory();
     final ttsCacheDir = Directory("${tempDir.path}/tts_cache");
     if (ttsCacheDir.existsSync()) {
       await ttsCacheDir.delete(recursive: true);
     }
  }
  
  /// 自动清理过期缓存 (7天前)
  Future<void> autoClean() async {
     final tempDir = await getTemporaryDirectory();
     final ttsCacheDir = Directory("${tempDir.path}/tts_cache");
     if (ttsCacheDir.existsSync()) {
        final now = DateTime.now();
        await for (var file in ttsCacheDir.list(recursive: false)) {
           if (file is File) {
             final stat = await file.stat();
             if (now.difference(stat.modified).inDays > 7) {
               await file.delete();
             }
           }
        }
     }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return "0 B";
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(2)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }
}
