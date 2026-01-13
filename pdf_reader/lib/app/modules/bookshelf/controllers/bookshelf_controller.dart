import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../data/models/book.dart';
import '../../../data/models/category.dart';
import '../../../services/database_service.dart';
import '../../reader/views/reader_view.dart';

class BookshelfController extends GetxController with GetSingleTickerProviderStateMixin, WidgetsBindingObserver {
  final DatabaseService _dbService = Get.find<DatabaseService>();
  
  // 所有书籍
  final allBooks = <Book>[].obs;
  // 当前显示的书籍
  final displayBooks = <Book>[].obs;
  
  // 分类列表
  final categories = <Category>[].obs;
  
  // 当前选中的分类 ID (null 表示全部)
  final Rx<int?> currentCategoryId = Rx<int?>(null);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    
    loadData();
    
    // 监听分类或书籍变化，更新显示列表
    ever(currentCategoryId, (_) => _filterBooks());
    ever(allBooks, (_) => _filterBooks());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 自动备份逻辑已移除
  }

  Future<void> loadData() async {
    await loadCategories();
    await loadBooks();
  }

  Future<void> loadBooks() async {
    final list = await _dbService.getAllBooks();
    // 确保 category 连接已加载
    for (var book in list) {
      await book.category.load();
    }
    allBooks.assignAll(list);
  }

  Future<void> loadCategories() async {
    final list = await _dbService.getAllCategories();
    categories.assignAll(list);
  }

  void _filterBooks() {
    if (currentCategoryId.value == null) {
      displayBooks.assignAll(allBooks);
    } else {
      displayBooks.assignAll(allBooks.where((b) => b.category.value?.id == currentCategoryId.value));
    }
  }

  void selectCategory(int? categoryId) {
    currentCategoryId.value = categoryId;
  }

  /// 导入图书
  Future<void> importBook() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'epub', 'txt'],
      allowMultiple: true,
    );

    if (result != null) {
      for (var file in result.files) {
        if (file.path != null) {
          await _dbService.addBook(file.path!);
        }
      }
      await loadBooks();
    }
  }

  /// 打开图书
  void openBook(Book book) {
    Get.to(() => ReaderView(book: book))?.then((_) {
      loadBooks(); // 刷新进度
    });
  }

  /// 删除图书
  Future<void> deleteBook(Book book) async {
    await _dbService.deleteBook(book.id);
    await loadBooks();
  }

  /// 添加分类
  Future<void> addCategory(String name) async {
    if (name.trim().isEmpty) return;
    try {
      await _dbService.addCategory(name);
      await loadCategories();
      Get.back(); // Close dialog
      Get.snackbar("成功", "分类 '$name' 已创建");
    } catch (e) {
      Get.snackbar("错误", "创建分类失败: $e");
    }
  }

  /// 删除分类
  Future<void> deleteCategory(Category category) async {
    try {
      // 如果当前选中了该分类，先切换到全部
      if (currentCategoryId.value == category.id) {
        selectCategory(null);
      }
      
      await _dbService.deleteCategory(category.id);
      await loadCategories();
      // 刷新书籍列表以更新分类状态
      await loadBooks(); 
      Get.snackbar("成功", "分类 '${category.name}' 已删除");
    } catch (e) {
      Get.snackbar("错误", "删除分类失败: $e");
    }
  }
  
  /// 移动书籍到分类
  Future<void> moveBookToCategory(Book book, Category? category) async {
    await _dbService.setBookCategory(book.id, category?.id);
    await book.category.load(); // Reload
    allBooks.refresh(); // Trigger update
    _filterBooks();
    Get.back(); // Close bottom sheet
    Get.snackbar("成功", "已移动到 ${category?.name ?? '未分类'}");
  }
}
