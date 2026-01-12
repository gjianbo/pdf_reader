import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_reader/app/data/models/book.dart';
import 'package:pdf_reader/app/data/models/auxiliary_models.dart';
import 'package:pdf_reader/app/data/models/category.dart';

/// 数据库服务
/// 负责图书的增删改查
class DatabaseService {
  late Isar _isar;

  /// 初始化数据库
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [BookSchema, BookmarkSchema, NoteSchema, CategorySchema],
      directory: dir.path,
    );
  }

  /// 删除分类
  Future<void> deleteCategory(int id) async {
    await _isar.writeTxn(() async {
      await _isar.categorys.delete(id);
    });
  }

  /// 获取所有图书 (按最近阅读时间排序)
  Future<List<Book>> getAllBooks() async {
    return await _isar.books.where().sortByLastReadTimeDesc().findAll();
  }

  /// 获取所有分类
  Future<List<Category>> getAllCategories() async {
    return await _isar.categorys.where().sortBySortOrder().findAll();
  }
  
  /// 添加分类
  Future<Category> addCategory(String name) async {
    final category = Category()..name = name;
    await _isar.writeTxn(() async {
      await _isar.categorys.put(category);
    });
    return category;
  }
  
  /// 设置图书分类
  Future<void> setBookCategory(int bookId, int? categoryId) async {
    final book = await _isar.books.get(bookId);
    if (book == null) return;
    
    await _isar.writeTxn(() async {
      if (categoryId == null) {
        book.category.reset();
      } else {
        final category = await _isar.categorys.get(categoryId);
        book.category.value = category;
      }
      await book.category.save();
    });
  }
  
  /// 获取某分类下的所有图书
  Future<List<Book>> getBooksByCategory(int categoryId) async {
    final category = await _isar.categorys.get(categoryId);
    if (category == null) return [];
    
    // Load linked books
    await category.books.load();
    return category.books.toList();
  }

  /// 添加图书
  /// 如果已存在 (filePath 相同)，则不重复添加，返回已存在的 Book
  Future<Book> addBook(String filePath) async {
    // 自动检测格式
    BookFormat format = BookFormat.pdf;
    String lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.epub')) {
      format = BookFormat.epub;
    } else if (lowerPath.endsWith('.txt')) {
      format = BookFormat.txt;
    }

    // 提取标题 (移除扩展名)
    String fileName = filePath.split('/').last;
    String title = fileName;
    if (fileName.contains('.')) {
      title = fileName.substring(0, fileName.lastIndexOf('.'));
    }
    
    // 检查是否已存在
    final existingBook = await _isar.books.filter().filePathEqualTo(filePath).findFirst();
    if (existingBook != null) {
      // 更新一下最近访问时间
      existingBook.lastReadTime = DateTime.now();
      // 如果之前是默认值，更新格式
      existingBook.format = format;
      
      await _isar.writeTxn(() async {
        await _isar.books.put(existingBook);
      });
      return existingBook;
    }

    final newBook = Book()
      ..title = title
      ..filePath = filePath
      ..format = format
      ..lastReadTime = DateTime.now();

    await _isar.writeTxn(() async {
      await _isar.books.put(newBook);
    });
    
    return newBook;
  }

  /// 更新阅读进度
  Future<void> updateProgress({
    required int bookId,
    required int pageIndex,
    required int sentenceIndex,
    required double totalProgress,
  }) async {
    final book = await _isar.books.get(bookId);
    if (book != null) {
      book.lastPageIndex = pageIndex;
      book.lastSentenceIndex = sentenceIndex;
      book.totalProgress = totalProgress;
      book.lastReadTime = DateTime.now();

      await _isar.writeTxn(() async {
        await _isar.books.put(book);
      });
    }
  }

  /// 删除图书
  Future<void> deleteBook(int id) async {
    await _isar.writeTxn(() async {
      await _isar.books.delete(id);
      // 同时删除关联的书签和笔记
      await _isar.bookmarks.filter().bookIdEqualTo(id).deleteAll();
      await _isar.notes.filter().bookIdEqualTo(id).deleteAll();
    });
  }

  // 获取所有书签 (用于备份)
  Future<List<Bookmark>> getAllBookmarksGlobal() async {
    return await _isar.bookmarks.where().findAll();
  }
  
  // 获取所有笔记 (用于备份)
  Future<List<Note>> getAllNotesGlobal() async {
    return await _isar.notes.where().findAll();
  }

  /// 保存图书信息 (用于同步更新)
  Future<void> saveBook(Book book) async {
    await _isar.writeTxn(() async {
      await _isar.books.put(book);
      await book.category.save();
    });
  }

  /// 确保书签存在 (用于同步)
  Future<void> ensureBookmark(Bookmark bookmark) async {
    await _isar.writeTxn(() async {
      final count = await _isar.bookmarks
          .filter()
          .bookIdEqualTo(bookmark.bookId)
          .pageIndexEqualTo(bookmark.pageIndex)
          .count();
          
      if (count == 0) {
        await _isar.bookmarks.put(bookmark);
      }
    });
  }
  
  /// 确保笔记存在 (用于同步)
  Future<void> ensureNote(Note note) async {
    await _isar.writeTxn(() async {
      // 简单查重：同一页内容相同
      final count = await _isar.notes
          .filter()
          .bookIdEqualTo(note.bookId)
          .pageIndexEqualTo(note.pageIndex)
          .contentEqualTo(note.content)
          .count();
          
      if (count == 0) {
        await _isar.notes.put(note);
      }
    });
  }

  // --- 书签逻辑 ---

  // 获取某本书的所有书签
  Future<List<Bookmark>> getBookmarks(int bookId) async {
    return await _isar.bookmarks
        .filter()
        .bookIdEqualTo(bookId)
        .sortByPageIndex()
        .findAll();
  }

  // 检查当前页是否有书签
  Future<bool> isBookmarked(int bookId, int pageIndex) async {
    final count = await _isar.bookmarks
        .filter()
        .bookIdEqualTo(bookId)
        .pageIndexEqualTo(pageIndex)
        .count();
    return count > 0;
  }

  // 切换书签状态 (有则删，无则加)
  Future<void> toggleBookmark(int bookId, int pageIndex) async {
    await _isar.writeTxn(() async {
      final existing = await _isar.bookmarks
          .filter()
          .bookIdEqualTo(bookId)
          .pageIndexEqualTo(pageIndex)
          .findFirst();

      if (existing != null) {
        await _isar.bookmarks.delete(existing.id);
      } else {
        final newBookmark = Bookmark(
          bookId: bookId,
          pageIndex: pageIndex,
          title: "第 ${pageIndex + 1} 页",
          createdAt: DateTime.now(),
        );
        await _isar.bookmarks.put(newBookmark);
      }
    });
  }

  // --- 笔记逻辑 ---

  // 获取某本书的所有笔记
  Future<List<Note>> getNotes(int bookId) async {
    return await _isar.notes
        .filter()
        .bookIdEqualTo(bookId)
        .sortByPageIndex()
        .findAll();
  }

  // 添加笔记
  Future<void> addNote(Note note) async {
    await _isar.writeTxn(() async {
      await _isar.notes.put(note);
    });
  }

  // 删除笔记
  Future<void> deleteNote(int noteId) async {
    await _isar.writeTxn(() async {
      await _isar.notes.delete(noteId);
    });
  }
}
