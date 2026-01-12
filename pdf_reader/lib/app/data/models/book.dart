import 'package:isar/isar.dart';
import 'category.dart';

part 'book.g.dart';

@collection
class Book {
  Id id = Isar.autoIncrement; // 自动自增ID

  late String title;         // 书名
  
  @Index(unique: true, replace: true)
  late String filePath;      // PDF 文件本地绝对路径 (作为唯一标识，避免重复添加)
  
  String? coverPath;         // 封面图片缓存路径 (可选)

  // --- 进度记忆核心 ---
  int lastPageIndex = 0;     // 上次读到第几页 (从0开始)
  
  int lastSentenceIndex = 0; // 上次读到该页的第几句
  
  double totalProgress = 0.0;// 总进度百分比 (0.0 - 1.0)
  
  DateTime lastReadTime = DateTime.now(); // 最近阅读时间

  @enumerated
  BookFormat format = BookFormat.pdf; // 书籍格式

  // 关联分类
  final category = IsarLink<Category>();
}

enum BookFormat {
  pdf,
  epub,
  txt,
}
