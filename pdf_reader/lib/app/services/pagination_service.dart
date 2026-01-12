import 'package:flutter/material.dart';
import '../data/models/universal_book.dart';

class PageInfo {
  final int chapterIndex;
  final int pageIndexInChapter;
  final String content;
  final int startCharIndex; // 在本章内容中的起始字符索引
  final int endCharIndex;   // 在本章内容中的结束字符索引

  PageInfo({
    required this.chapterIndex,
    required this.pageIndexInChapter,
    required this.content,
    required this.startCharIndex,
    required this.endCharIndex,
  });
}

class PaginationService {
  /// 计算整个书籍的分页 (针对纯文本)
  /// 注意：这是一个耗时操作，建议在大量文本时放入 Isolate，这里简化为异步
  Future<List<PageInfo>> paginateBook({
    required UniversalBook book,
    required TextStyle style,
    required Size pageSize,
    required EdgeInsets padding,
  }) async {
    List<PageInfo> allPages = [];
    double contentWidth = pageSize.width - padding.horizontal;
    double contentHeight = pageSize.height - padding.vertical;

    for (int i = 0; i < book.chapters.length; i++) {
      List<PageInfo> chapterPages = _paginateChapter(
        chapterIndex: i,
        content: book.chapters[i].content,
        style: style,
        width: contentWidth,
        height: contentHeight,
      );
      allPages.addAll(chapterPages);
      
      // 让出事件循环，避免卡顿
      await Future.delayed(Duration.zero);
    }

    return allPages;
  }

  /// 计算单个章节的分页
  List<PageInfo> _paginateChapter({
    required int chapterIndex,
    required String content,
    required TextStyle style,
    required double width,
    required double height,
  }) {
    List<PageInfo> pages = [];
    int start = 0;
    int pageIndex = 0;
    
    // 预处理内容：统一换行符，避免 TextPainter 异常
    // 这里假设 content 已经被清洗过，或者直接使用原始 content
    
    TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    while (start < content.length) {
      // 1. 粗略估计剩余文本是否能放下一页
      // 如果剩余很少，直接作为一页
      // 但为了准确，我们还是用 TextPainter 测量
      
      // 构造剩余文本的 TextSpan
      String remaining = content.substring(start);
      textPainter.text = TextSpan(text: remaining, style: style);
      
      // 2. 布局
      textPainter.layout(maxWidth: width);

      // 3. 判断是否超出一页
      if (textPainter.height <= height) {
        // 剩下的都能放下
        pages.add(PageInfo(
          chapterIndex: chapterIndex,
          pageIndexInChapter: pageIndex,
          content: remaining,
          startCharIndex: start,
          endCharIndex: content.length,
        ));
        break;
      }

      // 4. 寻找分割点
      // getPositionForOffset 获取指定坐标下的文本位置
      // 我们查找 (width, height) 也就是右下角位置的字符索引
      TextPosition endPos = textPainter.getPositionForOffset(Offset(width, height));
      int end = start + endPos.offset;

      // 修正：getPositionForOffset 可能返回的是最后一个字符的中间或者甚至之后
      // 我们需要确保这个 offset 是在合理范围内的
      if (end <= start) {
        // 极端情况：一个字都放不下（例如字号巨大），强制放一个字避免死循环
        end = start + 1;
      } else if (end > content.length) {
        end = content.length;
      }

      // 5. 避免单词/行截断优化 (可选)
      // 向前回溯找到最近的换行符或空格，防止切断单词
      // 简单处理：如果切分点后面不是换行，尝试回溯到上一个标点或空格
      // 这里为了中文阅读体验，主要防止把成对标点切开，或者把英文单词切开
      // 简单起见，暂不深度回溯，依赖 TextPainter 的软换行逻辑
      // 但是 TextPainter 只是布局，我们硬切字符串可能会破坏原本的软换行逻辑
      // 最准确的做法是利用 getLineBoundary 等
      
      // 尝试找到这一页最后一个完整的 line
      // 但 getPositionForOffset 返回的是字符索引，TextPainter 已经处理了换行
      // 只要我们截取到 offset，这一段文本渲染出来应该和 TextPainter 第一页看到的一样
      
      String pageContent = content.substring(start, end);
      
      pages.add(PageInfo(
        chapterIndex: chapterIndex,
        pageIndexInChapter: pageIndex,
        content: pageContent,
        startCharIndex: start,
        endCharIndex: end,
      ));

      start = end;
      pageIndex++;
    }

    return pages;
  }
}
