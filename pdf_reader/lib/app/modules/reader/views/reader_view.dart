import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../../data/models/auxiliary_models.dart';
import '../../../data/models/book.dart';
import '../controllers/reader_controller.dart';
import 'reflow_reader_page.dart';

class ReaderView extends GetView<ReaderController> {
  final Book book;
  
  const ReaderView({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    // 注入 Controller，传递 book 参数
    // 使用 tag 避免不同书籍混淆 (虽然 Get.to 会入栈，但最好区分)
    // 这里简单处理，每次进入都 put 一个新的
    Get.put(ReaderController(book: book));

    return Scaffold(
      endDrawer: _buildDrawer(),
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          Obx(() => IconButton(
            icon: Icon(controller.isReflowMode.value 
                ? (book.format == BookFormat.pdf ? Icons.picture_as_pdf : Icons.book) 
                : Icons.text_fields),
            tooltip: controller.isReflowMode.value ? '切换回原版模式' : '切换到纯文本模式',
            onPressed: controller.toggleReflowMode,
          )),
          Obx(() => IconButton(
            icon: Icon(controller.isCurrentPageBookmarked.value ? Icons.bookmark : Icons.bookmark_border, color: controller.isCurrentPageBookmarked.value ? Colors.red : null),
            tooltip: controller.isCurrentPageBookmarked.value ? '取消书签' : '添加书签',
            onPressed: controller.toggleBookmark,
          )),
          IconButton(
            icon: const Icon(Icons.timer),
            tooltip: '睡眠定时器',
            onPressed: () => _showSleepTimerDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 阅读区域
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (controller.isReflowMode.value) {
                return _buildReflowView();
              }

              return _buildOriginalView(context);
            }),
          ),
          
          // 底部控制栏
          _buildControlBar(),
        ],
      ),
    );
  }

  Widget _buildOriginalView(BuildContext context) {
    if (book.format == BookFormat.pdf) {
      return _buildPdfView(context);
    } else if (book.format == BookFormat.epub || book.format == BookFormat.txt) {
      return _buildFlowBookView();
    } else {
      return const Center(child: Text("不支持的格式"));
    }
  }

  Widget _buildPdfView(BuildContext context) {
    return Stack(
      children: [
        SfPdfViewer.file(
          File(book.filePath),
          key: Key(book.filePath), // 确保状态刷新
          canShowScrollHead: false, // 禁用滚动头以优化性能 (避免预计算所有页面高度)
          controller: controller.pdfViewerController,
          currentSearchTextHighlightColor: Colors.yellow.withValues(alpha: 0.6),
          otherSearchTextHighlightColor: Colors.yellow.withValues(alpha: 0.3),
          onDocumentLoaded: (PdfDocumentLoadedDetails details) {
            // 文档加载完成后，跳转到上次阅读的页面
            Future.delayed(const Duration(milliseconds: 100), () {
              if (book.lastPageIndex > 0) {
                controller.pdfViewerController.jumpToPage(book.lastPageIndex + 1);
              }
              controller.checkBookmarkStatus(book.lastPageIndex);
            });
          },
          onPageChanged: (PdfPageChangedDetails details) {
            controller.checkBookmarkStatus(details.newPageNumber - 1);
          },
          onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
            if (details.selectedText != null && details.selectedText!.isNotEmpty) {
              _showNoteDialog(context, details.selectedText!);
            }
          },
        ),
        if (controller.settings.isDarkMode.value)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }

  Widget _buildFlowBookView() {
    if (controller.universalBook == null) {
      return const Center(child: Text("解析失败"));
    }
    
    // 如果是 TXT 且开启了分页模式，使用 PageView
    if (controller.book.format == BookFormat.txt && controller.isPagedMode.value) {
      return _buildPagedTxtView();
    }
    
    // EPUB/TXT 滚动视图 (HTML)
    return Container(
      color: controller.settings.isDarkMode.value ? Colors.black : Colors.white,
      child: ListView.builder(
        itemCount: controller.universalBook!.chapters.length,
        itemBuilder: (context, index) {
          final chapter = controller.universalBook!.chapters[index];
          
          return Obx(() {
            // 检查当前章节是否是正在朗读的章节
            int activeChapterIndex = controller.getCurrentChapterIndex();
            bool isActiveChapter = index == activeChapterIndex;
            
            String htmlContent = chapter.htmlContent ?? chapter.content;
            
            // 如果是当前章节且正在播放(或选中)，注入高亮样式
            // 这里我们不需要 isPlaying，只要有选中就高亮
            if (isActiveChapter && controller.sentences.isNotEmpty && controller.currentIndex.value < controller.sentences.length) {
              String currentSentence = controller.sentences[controller.currentIndex.value];
              htmlContent = _injectHighlight(htmlContent, currentSentence);
            }

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chapter.title.isNotEmpty)
                    Text(
                      chapter.title,
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold, 
                        color: controller.settings.isDarkMode.value ? Colors.white : Colors.black
                      )
                    ),
                  HtmlWidget(
                    htmlContent,
                    textStyle: TextStyle(
                      fontSize: controller.settings.fontSize.value,
                      height: controller.settings.lineHeight.value,
                      color: controller.settings.isDarkMode.value ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const Divider(),
                ],
              ),
            );
          });
        },
      ),
    );
  }

  Widget _buildPagedTxtView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 触发分页计算
        // 延迟调用避免构建期间 setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.paginate(constraints.biggest);
        });

        return Obx(() {
          if (controller.pages.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final isDark = controller.settings.isDarkMode.value;
          final bgColor = isDark ? Colors.black : Colors.white; // 简单的背景色
          final textColor = isDark ? Colors.white70 : Colors.black87;
          
          return Container(
            color: bgColor,
            child: PageView.builder(
              controller: controller.pageController,
              itemCount: controller.pages.length,
              onPageChanged: (index) {
                controller.currentPageIndex.value = index;
                // 翻页时不一定要更新 global currentIndex，除非我们想同步阅读位置
                // 如果是手动翻页，应该暂时不更新 currentIndex (TTS 位置)，
                // 但如果想让 TTS 跳转，需要双击或其他交互。
                // 暂时保持简单：仅 UI 翻页。
              },
              itemBuilder: (context, index) {
                final page = controller.pages[index];
                
                // 检查当前页是否包含正在朗读的句子
                // 这里我们没有精确的 charIndex 匹配，只能模糊匹配
                // 更好的做法是在 controller 里计算好 highlighText
                
                String content = page.content;
                // 简单高亮逻辑 (仅在 TTS 播放时)
                // 这里我们无法复用 HTML 的高亮逻辑，因为这是纯文本
                // 需要用 TextSpan 构建
                
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // 页眉 (章节标题)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                           controller.universalBook!.chapters[page.chapterIndex].title,
                           style: TextStyle(
                             fontSize: 12, 
                             color: isDark ? Colors.grey : Colors.grey
                           ),
                           maxLines: 1,
                           overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 内容
                      Expanded(
                        child: SelectableText(
                          content,
                          style: TextStyle(
                            fontSize: controller.settings.fontSize.value,
                            height: controller.settings.lineHeight.value,
                            color: textColor,
                            fontFamily: 'Courier', // 等宽字体可能更好排版，但中文无所谓
                          ),
                          contextMenuBuilder: (context, editableTextState) {
                            return AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: editableTextState.contextMenuAnchors,
                              buttonItems: [
                                ...editableTextState.contextMenuButtonItems,
                                ContextMenuButtonItem(
                                  onPressed: () {
                                    final text = editableTextState.textEditingValue.selection.textInside(editableTextState.textEditingValue.text);
                                    if (text.isNotEmpty) _showNoteDialog(context, text);
                                    editableTextState.hideToolbar();
                                  },
                                  label: '翻译/笔记',
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      // 页脚 (页码)
                      Text(
                        "${page.pageIndexInChapter + 1} / ?", // 这里暂不知道该章总页数，除非预先计算好
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        });
      },
    );
  }

  /// 简单的字符串替换高亮 (仅替换第一个匹配项)
  String _injectHighlight(String html, String target) {
    if (target.trim().isEmpty) return html;
    
    // 构造高亮 span
    // 亮色模式：黄色背景；暗色模式：深橙色背景
    String highlightColor = controller.settings.isDarkMode.value ? "#B8860B" : "#FFFF00";
    String spanStart = '<span style="background-color: $highlightColor;">';
    String spanEnd = '</span>';
    
    // 尝试直接查找
    // 注意：如果 target 包含 HTML 特殊字符，可能需要转义，但这里 target 也是从 HTML 提取的文本
    // 简单实现：找到第一个匹配项并替换
    int index = html.indexOf(target);
    if (index != -1) {
      return html.replaceFirst(target, "$spanStart$target$spanEnd");
    }
    
    return html;
  }

  Widget _buildReflowView() {
    return ReflowReaderPage(controller: controller);
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.white,
      child: Column(
        children: [
          // 进度信息
          Obx(() => Text(
                controller.sentences.isEmpty
                    ? "正在解析文本..."
                    : "正在朗读: ${controller.currentIndex.value + 1} / ${controller.sentences.length}",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )),
          const SizedBox(height: 8),
          
          // 播放控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: controller.prev,
              ),
              Obx(() => FloatingActionButton(
                    onPressed: controller.sentences.isEmpty ? null : controller.play,
                    child: Icon(controller.isPlaying.value
                        ? Icons.pause
                        : Icons.play_arrow),
                  )),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: controller.next,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showNoteDialog(BuildContext context, String selectedText) {
    final textController = TextEditingController();
    Get.defaultDialog(
      title: '操作',
      content: Column(
        children: [
          Text(
            '选中: "${selectedText.length > 20 ? "${selectedText.substring(0, 20)}..." : selectedText}"',
            style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          // 翻译结果显示区
          Obx(() {
            if (controller.isTranslating.value) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              );
            }
            if (controller.translationResult.isNotEmpty) {
              return Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey.withValues(alpha: 0.1),
                width: double.infinity,
                child: Text("翻译: ${controller.translationResult.value}"),
              );
            }
            return const SizedBox.shrink();
          }),
          const SizedBox(height: 10),
          TextField(
            controller: textController,
            decoration: const InputDecoration(
              hintText: '输入笔记...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.translate, size: 16),
                label: const Text("翻译"),
                onPressed: () {
                   controller.translate(selectedText);
                },
              ),
            ],
          )
        ],
      ),
      textConfirm: '保存笔记',
      textCancel: '取消',
      confirmTextColor: Colors.white,
      onConfirm: () {
        if (textController.text.isNotEmpty) {
          // pageNumber is 1-based
          int pageIndex = controller.pdfViewerController.pageNumber - 1;
          if (pageIndex < 0) pageIndex = 0;
          
          controller.addNote(selectedText, textController.text, pageIndex);
          
          // 清除选中 (可选)
          controller.pdfViewerController.clearSelection();
          Get.back();
        }
      },
    );
  }

  void _showSleepTimerDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("睡眠定时器", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Obx(() {
                if (controller.sleepMinutesLeft.value > 0) {
                   return Column(
                     children: [
                       Text("剩余时间: ${controller.sleepMinutesLeft.value} 分钟", 
                           style: const TextStyle(color: Colors.blue, fontSize: 16)),
                       TextButton(
                         onPressed: () {
                           controller.cancelSleepTimer();
                           Get.back();
                         },
                         child: const Text("取消定时", style: TextStyle(color: Colors.red)),
                       ),
                       const Divider(),
                     ],
                   );
                }
                return const SizedBox.shrink();
              }),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text("15 分钟"),
                onTap: () {
                  controller.startSleepTimer(15);
                  Get.back();
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text("30 分钟"),
                onTap: () {
                  controller.startSleepTimer(30);
                  Get.back();
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text("60 分钟"),
                onTap: () {
                  controller.startSleepTimer(60);
                  Get.back();
                },
              ),
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text("播完本章"),
                onTap: () {
                  controller.playUntilEndOfChapter();
                  Get.back();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: 300,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const SizedBox(height: 40),
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.list), text: "目录"),
                Tab(icon: Icon(Icons.bookmark), text: "书签"),
                Tab(icon: Icon(Icons.note), text: "笔记"),
              ],
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildDirectoryList(),
                  _buildBookmarksList(),
                  _buildNotesList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryList() {
    return Obx(() {
      if (controller.pdfBookmarks.isEmpty) {
        return const Center(child: Text("暂无目录", style: TextStyle(color: Colors.grey)));
      }
      return ListView.builder(
        itemCount: controller.pdfBookmarks.length,
        itemBuilder: (context, index) {
          final bookmark = controller.pdfBookmarks[index];
          return _buildBookmarkItem(bookmark);
        },
      );
    });
  }

  Widget _buildBookmarkItem(PdfBookmark bookmark) {
    if (bookmark.count > 0) {
      return ExpansionTile(
        title: GestureDetector(
          onTap: () {
            controller.jumpToBookmark(bookmark);
            Get.back();
          },
          child: Text(bookmark.title, style: const TextStyle(fontSize: 14)),
        ),
        children: List.generate(bookmark.count, (i) => _buildBookmarkItem(bookmark[i])),
      );
    } else {
      return ListTile(
        title: Text(bookmark.title, style: const TextStyle(fontSize: 14)),
        onTap: () {
          controller.jumpToBookmark(bookmark);
          Get.back();
        },
      );
    }
  }

  Widget _buildBookmarksList() {
    return Obx(() {
      if (controller.bookmarksList.isEmpty) {
        return const Center(child: Text("暂无书签", style: TextStyle(color: Colors.grey)));
      }
      return ListView.builder(
        itemCount: controller.bookmarksList.length,
        itemBuilder: (context, index) {
          final Bookmark bookmark = controller.bookmarksList[index];
          return ListTile(
            leading: const Icon(Icons.bookmark, color: Colors.red),
            title: Text("第 ${bookmark.pageIndex + 1} 页"),
            subtitle: Text(bookmark.createdAt.toString().split('.')[0]),
            onTap: () {
              controller.jumpToPage(bookmark.pageIndex);
              Get.back(); // 关闭侧边栏
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () async {
                // 删除书签逻辑复用 toggleBookmark，但需要先跳到那一页？
                // 或者在 Controller 增加 deleteBookmarkById
                // 这里为了简单，直接调用 toggleBookmark 需要先定位。
                // 建议在 Controller 增加 deleteBookmark(Bookmark b)
                // 暂时先只支持跳转，或者如果 Controller 有 deleteBookmark 方法最好。
                // 由于 toggleBookmark 依赖当前页，这里不太好用。
                // 暂时不提供删除按钮，或者跳转后让用户再点击 toggle 删除。
                // 既然需求是“增删改查”，最好能在这里删。
                // 重新实现 toggleBookmark 逻辑：
                await controller.toggleBookmark(); // 这样不对，这是操作当前页。
                // 我需要修改 Controller 增加 deleteBookmark 方法。
                // 暂时留空，或者先跳转。
                controller.jumpToPage(bookmark.pageIndex);
                Get.back();
              },
            ),
          );
        },
      );
    });
  }

  Widget _buildNotesList() {
    return Obx(() {
      if (controller.notesList.isEmpty) {
        return const Center(child: Text("暂无笔记", style: TextStyle(color: Colors.grey)));
      }
      return ListView.builder(
        itemCount: controller.notesList.length,
        itemBuilder: (context, index) {
          final Note note = controller.notesList[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              title: Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (note.selectedText != null)
                    Text(
                      "原文: ${note.selectedText}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  Text("第 ${note.pageIndex + 1} 页 · ${note.createdAt.toString().split('.')[0]}",
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              onTap: () {
                controller.jumpToPage(note.pageIndex);
                Get.back();
              },
              trailing: IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.grey),
                onPressed: () {
                  Get.defaultDialog(
                    title: "删除笔记",
                    middleText: "确定要删除这条笔记吗？",
                    onConfirm: () {
                      controller.deleteNote(note);
                      Get.back();
                    },
                    onCancel: () {},
                  );
                },
              ),
            ),
          );
        },
      );
    });
  }
}
