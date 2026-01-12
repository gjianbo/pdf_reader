import '../../data/models/universal_book.dart';

abstract class BookParser {
  Future<UniversalBook> parse(String filePath);
}
