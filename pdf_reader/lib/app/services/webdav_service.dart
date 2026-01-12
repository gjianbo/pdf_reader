import 'dart:convert';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:pdf_reader/app/data/models/auxiliary_models.dart';
import 'package:pdf_reader/app/services/database_service.dart';
import 'package:pdf_reader/app/services/settings_service.dart';

class WebDavService extends GetxService {
  final SettingsService _settings = Get.find<SettingsService>();
  final DatabaseService _db = Get.find<DatabaseService>();
  
  webdav.Client? _client;

  Future<WebDavService> init() async {
    _initClient();
    
    // 监听配置变化
    ever(_settings.webdavUrl, (_) => _initClient());
    ever(_settings.webdavUser, (_) => _initClient());
    ever(_settings.webdavPassword, (_) => _initClient());
    
    return this;
  }

  void _initClient() {
    if (_settings.webdavUrl.value.isNotEmpty &&
        _settings.webdavUser.value.isNotEmpty &&
        _settings.webdavPassword.value.isNotEmpty) {
      _client = webdav.newClient(
        _settings.webdavUrl.value,
        user: _settings.webdavUser.value,
        password: _settings.webdavPassword.value,
        debug: true,
      );
    } else {
      _client = null;
    }
  }
  
  /// 测试连接
  Future<void> testConnection() async {
    if (_client == null) throw "WebDAV 未配置";
    try {
      await _client!.ping();
    } catch (e) {
      throw "连接失败: $e";
    }
  }

  /// 备份数据到 WebDAV
  Future<void> backup() async {
    if (_client == null) throw "WebDAV 未配置";

    try {
      final categories = await _db.getAllCategories();
      final books = await _db.getAllBooks();
      final bookmarks = await _db.getAllBookmarksGlobal();
      final notes = await _db.getAllNotesGlobal();

      final data = {
        'version': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'categories': categories.map((c) => {
          'name': c.name,
          'sortOrder': c.sortOrder,
        }).toList(),
        'books': books.map((b) => {
          'title': b.title,
          'fileName': b.filePath.split('/').last,
          'format': b.format.index,
          'lastReadTime': b.lastReadTime.toIso8601String(),
          'lastPageIndex': b.lastPageIndex,
          'lastSentenceIndex': b.lastSentenceIndex,
          'totalProgress': b.totalProgress,
          'categoryName': b.category.value?.name,
        }).toList(),
        'bookmarks': bookmarks.map((b) {
           final book = books.firstWhereOrNull((bk) => bk.id == b.bookId);
           return {
             'bookFileName': book?.filePath.split('/').last,
             'bookTitle': book?.title,
             'pageIndex': b.pageIndex,
             'title': b.title,
             'createdAt': b.createdAt.toIso8601String(),
           };
        }).where((m) => m['bookFileName'] != null).toList(),
        'notes': notes.map((n) {
           final book = books.firstWhereOrNull((bk) => bk.id == n.bookId);
           return {
             'bookFileName': book?.filePath.split('/').last,
             'bookTitle': book?.title,
             'pageIndex': n.pageIndex,
             'content': n.content,
             'selectedText': n.selectedText,
             'createdAt': n.createdAt.toIso8601String(),
           };
        }).where((m) => m['bookFileName'] != null).toList(),
      };

      final jsonString = jsonEncode(data);
      await _client!.write('backup.json', Uint8List.fromList(utf8.encode(jsonString)));
    } catch (e) {
      throw "备份失败: $e";
    }
  }

  /// 从 WebDAV 恢复数据
  Future<void> restore() async {
    if (_client == null) throw "WebDAV 未配置";

    try {
      final contentBytes = await _client!.read('backup.json');
      final jsonString = utf8.decode(contentBytes);
      final data = jsonDecode(jsonString);

      // 1. 恢复分类
      final List cats = data['categories'] ?? [];
      final currentCats = await _db.getAllCategories();
      for (var c in cats) {
        final name = c['name'];
        if (currentCats.firstWhereOrNull((ec) => ec.name == name) == null) {
          await _db.addCategory(name);
        }
      }
      final allCats = await _db.getAllCategories();

      // 2. 恢复书籍进度和分类
      final List booksData = data['books'] ?? [];
      final localBooks = await _db.getAllBooks();
      
      for (var bData in booksData) {
        final fileName = bData['fileName'];
        final title = bData['title'];
        
        // 匹配本地书籍
        final localBook = localBooks.firstWhereOrNull((lb) => 
          lb.filePath.split('/').last == fileName || lb.title == title);
          
        if (localBook != null) {
          // 恢复分类
          final catName = bData['categoryName'];
          if (catName != null) {
            final cat = allCats.firstWhereOrNull((c) => c.name == catName);
            if (cat != null) {
              await _db.setBookCategory(localBook.id, cat.id);
            }
          }
          
          // 恢复进度 (如果远程时间较新，或者简单覆盖)
          // 这里简化为直接覆盖，假设用户点击恢复就是为了同步云端状态
          localBook.lastPageIndex = bData['lastPageIndex'];
          localBook.lastSentenceIndex = bData['lastSentenceIndex'];
          localBook.totalProgress = (bData['totalProgress'] as num).toDouble();
          localBook.lastReadTime = DateTime.parse(bData['lastReadTime']);
          
          await _db.saveBook(localBook);
          
          // 3. 恢复该书的书签
          final List bookmarksData = data['bookmarks'] ?? [];
          for (var bmData in bookmarksData) {
            if (bmData['bookFileName'] == fileName || bmData['bookTitle'] == title) {
               final bm = Bookmark(
                 bookId: localBook.id,
                 pageIndex: bmData['pageIndex'],
                 title: bmData['title'],
                 createdAt: DateTime.parse(bmData['createdAt']),
               );
               await _db.ensureBookmark(bm);
            }
          }
          
          // 4. 恢复该书的笔记
          final List notesData = data['notes'] ?? [];
          for (var nData in notesData) {
             if (nData['bookFileName'] == fileName || nData['bookTitle'] == title) {
               final note = Note(
                 bookId: localBook.id,
                 pageIndex: nData['pageIndex'],
                 content: nData['content'],
                 selectedText: nData['selectedText'],
                 createdAt: DateTime.parse(nData['createdAt']),
               );
               await _db.ensureNote(note);
             }
          }
        }
      }
    } catch (e) {
      throw "恢复失败: $e";
    }
  }
}
