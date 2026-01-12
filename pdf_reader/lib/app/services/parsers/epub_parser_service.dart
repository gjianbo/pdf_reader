import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;
import '../../data/models/universal_book.dart';
import 'book_parser.dart';

class EpubParserService implements BookParser {
  @override
  Future<UniversalBook> parse(String filePath) async {
    File targetFile = File(filePath);
    List<int> bytes = await targetFile.readAsBytes();
    EpubBook epubBook = await EpubReader.readBook(bytes);

    String title = epubBook.Title ?? "Untitled";
    List<Chapter> chapters = [];

    // 递归处理章节
    if (epubBook.Chapters != null) {
      for (var epubChapter in epubBook.Chapters!) {
        chapters.addAll(_parseChapters(epubChapter));
      }
    }

    return UniversalBook(title: title, chapters: chapters);
  }

  List<Chapter> _parseChapters(EpubChapter epubChapter) {
    List<Chapter> result = [];
    
    String chapterTitle = epubChapter.Title ?? "";
    String htmlContent = epubChapter.HtmlContent ?? "";
    
    // 提取纯文本用于 TTS
    // 使用 html 库解析去标签
    var document = html_parser.parse(htmlContent);
    String plainText = document.body?.text ?? "";

    // 如果内容不为空，添加章节
    if (plainText.trim().isNotEmpty) {
      result.add(Chapter(
        title: chapterTitle,
        content: plainText,
        htmlContent: htmlContent,
      ));
    }

    // 处理子章节
    if (epubChapter.SubChapters != null) {
      for (var subChapter in epubChapter.SubChapters!) {
        result.addAll(_parseChapters(subChapter));
      }
    }

    return result;
  }
}
