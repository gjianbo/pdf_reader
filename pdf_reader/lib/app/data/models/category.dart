import 'package:isar/isar.dart';
import 'book.dart';

part 'category.g.dart';

@collection
class Category {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  int sortOrder = 0;

  @Backlink(to: 'category')
  final books = IsarLinks<Book>();
}
