import 'package:isar/isar.dart';

part 'auxiliary_models.g.dart';

@collection
class Bookmark {
  Id id = Isar.autoIncrement;

  @Index()
  int bookId; // 关联哪本书

  int pageIndex; // 第几页 (从 0 开始)
  
  String? title; // 书签标题 (默认为 "第 X 页" 或该页首句)
  
  DateTime createdAt;

  Bookmark({
    required this.bookId,
    required this.pageIndex,
    this.title,
    required this.createdAt,
  });
}

@collection
class Note {
  Id id = Isar.autoIncrement;

  @Index()
  int bookId;

  int pageIndex; // 笔记所在的页面

  String? selectedText; // 用户高亮选中的原文
  String content; // 用户输入的笔记内容
  
  // 颜色标记 (如 0xFFFFFF00)
  int colorValue;
  
  DateTime createdAt;

  Note({
    required this.bookId,
    required this.pageIndex,
    this.selectedText,
    required this.content,
    this.colorValue = 0xFFFFEB3B, // 默认黄色
    required this.createdAt,
  });
}
