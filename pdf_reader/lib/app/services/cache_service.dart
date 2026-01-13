import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

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
      final tempDir = await getTemporaryDirectory();
      final dir = Directory("${tempDir.path}/custom_pdf_reader_cache_v1"); // 猜测的路径
      
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
