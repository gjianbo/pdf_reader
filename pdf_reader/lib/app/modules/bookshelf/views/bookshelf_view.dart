import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/bookshelf_controller.dart';
import '../../../data/models/book.dart';
import '../../../data/models/category.dart';

import '../../settings/views/settings_view.dart';

class BookshelfView extends GetView<BookshelfController> {
  const BookshelfView({super.key});

  @override
  Widget build(BuildContext context) {
    // Controller 已通过 Binding 注入，无需手动 put

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的书架'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Get.to(() => const SettingsView()),
            tooltip: '设置',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: controller.importBook,
            tooltip: '导入图书',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCategoryBar(context),
          Expanded(
            child: Obx(() {
              if (controller.displayBooks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.library_books, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(controller.currentCategoryId.value == null 
                          ? '书架是空的，点击右上角导入图书' 
                          : '该分类下没有图书'),
                      const SizedBox(height: 16),
                      if (controller.currentCategoryId.value == null)
                        ElevatedButton.icon(
                          onPressed: controller.importBook,
                          icon: const Icon(Icons.add),
                          label: const Text('导入图书'),
                        ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, // 每行3本
                  childAspectRatio: 0.7, // 宽高比
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: controller.displayBooks.length,
                itemBuilder: (context, index) {
                  final book = controller.displayBooks[index];
                  return _buildBookCard(context, book);
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Obx(() {
        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: const Text('全部'),
                selected: controller.currentCategoryId.value == null,
                onSelected: (bool selected) {
                  if (selected) controller.selectCategory(null);
                },
              ),
            ),
            ...controller.categories.map((category) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onLongPress: () => _showDeleteCategoryDialog(context, category),
                  child: ChoiceChip(
                    label: Text(category.name),
                    selected: controller.currentCategoryId.value == category.id,
                    onSelected: (bool selected) {
                      if (selected) controller.selectCategory(category.id);
                    },
                  ),
                ),
              );
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('新建分类'),
                onPressed: () => _showAddCategoryDialog(context),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildBookCard(BuildContext context, Book book) {
    return GestureDetector(
      onTap: () => controller.openBook(book),
      onLongPress: () => _showBookOptions(context, book),
      child: Card(
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.grey[300],
                child: book.coverPath != null
                    ? Image.asset(book.coverPath!, fit: BoxFit.cover) 
                    : _buildFormatIcon(book.format),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  if (book.totalProgress > 0)
                    LinearProgressIndicator(
                      value: book.totalProgress,
                      backgroundColor: Colors.grey[200],
                      minHeight: 2,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatIcon(BookFormat format) {
    IconData icon;
    Color color;
    String text;

    switch (format) {
      case BookFormat.pdf:
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        text = 'PDF';
        break;
      case BookFormat.epub:
        icon = Icons.book;
        color = Colors.orange;
        text = 'EPUB';
        break;
      case BookFormat.txt:
        icon = Icons.description;
        color = Colors.blue;
        text = 'TXT';
        break;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    final textController = TextEditingController();
    Get.defaultDialog(
      title: "新建分类",
      content: TextField(
        controller: textController,
        decoration: const InputDecoration(
          hintText: "输入分类名称",
          border: OutlineInputBorder(),
        ),
      ),
      textConfirm: "创建",
      textCancel: "取消",
      confirmTextColor: Colors.white,
      onConfirm: () {
        controller.addCategory(textController.text);
      },
    );
  }

  void _showBookOptions(BuildContext context, Book book) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("《${book.title}》", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text("移动到分类"),
                onTap: () {
                  Get.back();
                  _showMoveToCategoryDialog(context, book);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("删除图书", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Get.back();
                  _showDeleteConfirmDialog(book);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoveToCategoryDialog(BuildContext context, Book book) {
    Get.bottomSheet(
      Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("选择分类", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text("未分类"),
                    selected: book.category.value == null,
                    onTap: () => controller.moveBookToCategory(book, null),
                  ),
                  ...controller.categories.map((category) {
                    return ListTile(
                      title: Text(category.name),
                      selected: book.category.value?.id == category.id,
                      onTap: () => controller.moveBookToCategory(book, category),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(Book book) {
    Get.defaultDialog(
      title: '删除图书',
      middleText: '确定要从书架删除《${book.title}》吗？',
      textConfirm: '删除',
      textCancel: '取消',
      confirmTextColor: Colors.white,
      onConfirm: () {
        controller.deleteBook(book);
        Get.back();
      },
    );
  }

  void _showDeleteCategoryDialog(BuildContext context, Category category) {
    Get.defaultDialog(
      title: "删除分类",
      middleText: "确定要删除分类 '${category.name}' 吗？\n该分类下的书籍将变为未分类。",
      textConfirm: "删除",
      textCancel: "取消",
      confirmTextColor: Colors.white,
      onConfirm: () {
        controller.deleteCategory(category);
        Get.back();
      },
    );
  }
}
