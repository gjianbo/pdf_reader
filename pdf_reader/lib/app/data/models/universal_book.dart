class UniversalBook {
  final String title;
  final List<Chapter> chapters;

  UniversalBook({required this.title, required this.chapters});
}

class Chapter {
  final String title;
  final String content; // 纯文本内容 (用于 TTS)
  final String? htmlContent; // HTML内容 (用于 EPUB 显示)
  
  Chapter({
    required this.title,
    required this.content,
    this.htmlContent,
  });
}
