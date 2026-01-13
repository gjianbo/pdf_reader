import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:pdf_reader/app/utils/text_cleaner.dart';

/// PDF 服务类
/// 负责 PDF 文档的加载和文本提取
class PdfService {
  /// 从文件路径提取所有文本并清洗分句 (运行在 Isolate 中)
  Future<List<String>> extractText(String filePath) async {
    final File file = File(filePath);
    if (!file.existsSync()) {
      throw Exception("File not found: $filePath");
    }

    // 使用 compute 将耗时操作放入后台线程
    return await compute(_extractTextIsolate, filePath);
  }

  /// 静态函数，用于 Isolate 执行
  static Future<List<String>> _extractTextIsolate(String filePath) async {
    final File file = File(filePath);
    // 加载 PDF 文档
    final List<int> bytes = await file.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);

    // 提取文本
    String text = PdfTextExtractor(document).extractText();

    // 释放文档资源
    document.dispose();

    // 清洗并分句
    return TextProcessUtil.cleanAndSplit(text);
  }
}
