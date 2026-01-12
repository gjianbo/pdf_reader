import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../controllers/reader_controller.dart';

class ReflowReaderPage extends StatefulWidget {
  final ReaderController controller;

  const ReflowReaderPage({super.key, required this.controller});

  @override
  State<ReflowReaderPage> createState() => _ReflowReaderPageState();
}

class _ReflowReaderPageState extends State<ReflowReaderPage> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    // 监听当前索引变化，自动滚动
    ever(widget.controller.currentIndex, (index) {
      if (widget.controller.isReflowMode.value) {
        _scrollToIndex(index);
      }
    });
  }

  void _scrollToIndex(int index) {
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3, // 滚动到屏幕 30% 的位置，方便阅读
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sentences = widget.controller.sentences;
      final currentIndex = widget.controller.currentIndex.value;
      final fontSize = widget.controller.settings.fontSize.value;
      final lineHeight = widget.controller.settings.lineHeight.value;
      final themeColor = Color(widget.controller.settings.themeColor.value);
      final isDarkMode = widget.controller.settings.isDarkMode.value;

      final bgColor = isDarkMode ? Colors.black : themeColor;
      final textColor = isDarkMode ? Colors.white : Colors.black87;
      final activeColor = isDarkMode ? Colors.blueGrey[800]! : Colors.orange.withValues(alpha: 0.2);

      if (sentences.isEmpty) {
        return Container(
          color: bgColor,
          child: Center(
            child: Text(
              "没有可显示的文本",
              style: TextStyle(color: textColor),
            ),
          ),
        );
      }

      return Container(
        color: bgColor,
        child: ScrollablePositionedList.builder(
          itemCount: sentences.length,
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          initialScrollIndex: currentIndex,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemBuilder: (context, index) {
            final isCurrent = index == currentIndex;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isCurrent ? activeColor : null,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                sentences[index],
                style: TextStyle(
                  fontSize: fontSize,
                  height: lineHeight,
                  color: textColor,
                  fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                ),
                onTap: () {
                  widget.controller.currentIndex.value = index;
                  // 点击即播
                  widget.controller.play(); 
                },
                contextMenuBuilder: (context, editableTextState) {
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: [
                      ...editableTextState.contextMenuButtonItems,
                      ContextMenuButtonItem(
                        onPressed: () {
                          final text = editableTextState.textEditingValue.selection.textInside(editableTextState.textEditingValue.text);
                          if (text.isNotEmpty) widget.controller.translate(text);
                          editableTextState.hideToolbar();
                          // 显示翻译结果对话框
                          _showTranslationDialog(context);
                        },
                        label: '翻译',
                      ),
                      ContextMenuButtonItem(
                        onPressed: () {
                          widget.controller.currentIndex.value = index;
                          widget.controller.play();
                          editableTextState.hideToolbar();
                        },
                        label: '从这里播放',
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      );
    });
  }

  void _showTranslationDialog(BuildContext context) {
    Get.defaultDialog(
      title: "翻译结果",
      content: Obx(() {
        if (widget.controller.isTranslating.value) {
          return const CircularProgressIndicator();
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: SelectableText(widget.controller.translationResult.value),
          ),
        );
      }),
      textCancel: "关闭",
    );
  }
}
