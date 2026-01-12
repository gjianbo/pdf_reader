import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:charset_converter/charset_converter.dart';
import '../../data/models/universal_book.dart';
import 'book_parser.dart';

class TxtParserService implements BookParser {
  @override
  Future<UniversalBook> parse(String filePath) async {
    File file = File(filePath);
    if (!await file.exists()) {
      throw Exception("File not found: $filePath");
    }

    Uint8List bytes = await file.readAsBytes();
    String content;

    // 1. 尝试解码 (UTF-8 优先，失败尝试 GBK)
    try {
      content = utf8.decode(bytes);
    } catch (e) {
      try {
        // charset_converter 需要 Uint8List
        content = await CharsetConverter.decode("gbk", bytes);
      } catch (e2) {
        // 如果 GBK 也失败，尝试 ISO-8859-1 或直接报错
        content = latin1.decode(bytes);
      }
    }

    // 2. 智能分章
    List<Chapter> chapters = _splitChapters(content);

    // 3. 获取标题 (文件名)
    String title = filePath.split(Platform.pathSeparator).last;
    // 去掉扩展名
    if (title.contains('.')) {
      title = title.substring(0, title.lastIndexOf('.'));
    }

    return UniversalBook(title: title, chapters: chapters);
  }

  List<Chapter> _splitChapters(String content) {
    List<Chapter> chapters = [];
    
    // 正则匹配：第 x 章/回
    // 允许前面有少量空白，后面跟标题
    final RegExp chapterRegex = RegExp(
      r'^\s*第\s*[0-9一二三四五六七八九十百千]+\s*[章回].*$',
      multiLine: true,
    );

    Iterable<RegExpMatch> matches = chapterRegex.allMatches(content);
    
    if (matches.isEmpty) {
      // 如果没有匹配到章节，整本书作为一个章节
      chapters.add(Chapter(title: "正文", content: content));
      return chapters;
    }

    int lastIndex = 0;
    String? lastTitle;

    // 处理序章（如果有）
    if (matches.first.start > 0) {
      String preContent = content.substring(0, matches.first.start).trim();
      if (preContent.isNotEmpty) {
        chapters.add(Chapter(title: "序章/前言", content: preContent));
      }
    }

    for (var match in matches) {
      if (lastTitle != null) {
        // 添加上一章
        String chapterContent = content.substring(lastIndex, match.start).trim();
        if (chapterContent.isNotEmpty) {
           // 简单的 HTML 包装，保持换行
          String htmlContent = _convertToHtml(chapterContent);
          chapters.add(Chapter(
            title: lastTitle, 
            content: chapterContent,
            htmlContent: htmlContent
          ));
        }
      }
      
      lastTitle = match.group(0)?.trim() ?? "未知章节";
      lastIndex = match.end;
    }

    // 添加最后一章
    if (lastTitle != null && lastIndex < content.length) {
      String chapterContent = content.substring(lastIndex).trim();
       if (chapterContent.isNotEmpty) {
          String htmlContent = _convertToHtml(chapterContent);
          chapters.add(Chapter(
            title: lastTitle, 
            content: chapterContent,
            htmlContent: htmlContent
          ));
       }
    }

    return chapters;
  }

  String _convertToHtml(String text) {
    // 将纯文本换行符转换为 HTML <p> 标签
    List<String> paragraphs = text.split('\n');
    StringBuffer html = StringBuffer();
    for (var p in paragraphs) {
      if (p.trim().isNotEmpty) {
        html.write('<p>${p.trim()}</p>');
      }
    }
    return html.toString();
  }
}
