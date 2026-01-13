import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:translator/translator.dart';
import '../../../data/models/auxiliary_models.dart';
import '../../../data/models/book.dart';
import '../../../data/models/universal_book.dart';
import '../../../services/database_service.dart';
import '../../../services/pdf_service.dart';
import '../../../services/parsers/epub_parser_service.dart';
import '../../../services/parsers/txt_parser_service.dart';
import '../../../services/pagination_service.dart';
import '../../../services/tts_service.dart';
import '../../../services/settings_service.dart';
import '../../../utils/text_cleaner.dart';

/// 阅读器控制器
/// 负责协调 PDF 加载、文本提取、TTS 合成与播放、以及 UI 高亮同步
class ReaderController extends GetxController with WidgetsBindingObserver {
  // 传入的 Book 对象
  final Book book;

  // 服务实例
  final PdfService _pdfService = PdfService();
  final EpubParserService _epubParser = EpubParserService();
  final TxtParserService _txtParser = TxtParserService();
  final PaginationService _paginationService = PaginationService();
  final TtsService _ttsService = Get.find<TtsService>(); // 使用全局单例
  final DatabaseService _dbService = Get.find<DatabaseService>();
  final SettingsService settings = Get.find<SettingsService>();
  final GoogleTranslator _translator = GoogleTranslator();

  // 状态变量
  UniversalBook? universalBook; // 通用图书对象 (EPUB/TXT)
  final RxList<String> sentences = <String>[].obs; // 提取并分句后的文本列表
  final RxInt currentIndex = 0.obs; // 当前朗读句子的索引
  final RxBool isLoading = false.obs; // 加载状态
  final RxBool isPlaying = false.obs; // 播放状态
  final RxBool isReflowMode = false.obs; // 是否开启纯文本重排模式
  final RxBool isCurrentPageBookmarked = false.obs; // 当前页是否已收藏

  // 翻译相关
  final RxBool isTranslating = false.obs;
  final RxString translationResult = ''.obs;

  // 睡眠定时器相关
  RxInt get sleepMinutesLeft => _ttsService.sleepMinutesLeft;

  final RxList<Bookmark> bookmarksList = <Bookmark>[].obs;
  final RxList<Note> notesList = <Note>[].obs;
  
  // 分页相关 (针对 TXT/EPUB)
  final RxList<PageInfo> pages = <PageInfo>[].obs;
  final RxInt currentPageIndex = 0.obs; // 当前页索引 (0-based)
  final RxBool isPagedMode = true.obs; // 是否开启分页模式 (vs 滚动模式)
  final PageController pageController = PageController();

  // 章节映射 (用于 EPUB/TXT 原版高亮)
  // chapterStartSentenceIndices[i] 表示第 i 章的第一个句子在全局 sentences 中的索引
  final List<int> chapterStartSentenceIndices = [];

  // UI 控制器
  final PdfViewerController pdfViewerController = PdfViewerController();

  // PDF 目录相关
  final RxList<PdfBookmark> pdfBookmarks = <PdfBookmark>[].obs;
  PdfDocument? _pdfDocument;
  
  ReaderController({required this.book});

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    
    // 初始化设置
    _applySettings();

    // 监听设置变化
    ever(settings.keepScreenOn, (_) => _updateWakelock());
    ever(settings.orientationMode, (_) => _updateOrientation());
    
    // 监听字体大小变化，重新分页
    ever(settings.fontSize, (_) {
      if (book.format == BookFormat.txt && universalBook != null) {
        // 需要重新分页，但需要 View 提供新的尺寸，或者我们只能在这里标记需要重排
        // 实际上，View 的 LayoutBuilder 会触发重排，这里可能不需要做太多
        // 但是我们需要清空旧的 pages
        pages.clear();
      }
    });

    // 初始化加载
    _loadBook();
    _loadAuxiliaryData();

    // 监听播放状态流
    ever(_ttsService.state, (state) {
      isPlaying.value = state == TtsState.playing || state == TtsState.loading;
    });

    // 监听 TTS 当前朗读的句子索引
    ever(_ttsService.currentSentenceIndex, (index) {
      if (index != currentIndex.value) {
        currentIndex.value = index;
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          _highlightCurrentSentence();
        }
      }
    });
  }

  @override
  void onClose() {
    // 退出时保存进度
    _saveProgress();

    // 恢复默认设置
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WidgetsBinding.instance.removeObserver(this);
    // TtsService 由 Get.put 管理，如果不希望全局常驻，可以 delete，但为了后台播放通常保留
    // _ttsService.stop(); // 可以在退出页面时停止，也可以继续播放
    _ttsService.stop(); 
    super.onClose();
  }

  void _applySettings() {
    _updateWakelock();
    _updateOrientation();
  }

  void _updateWakelock() {
    if (settings.keepScreenOn.value) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _updateOrientation() {
    switch (settings.orientationMode.value) {
      case 1: // 锁定竖屏
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        break;
      case 2: // 锁定横屏
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case 0: // 跟随系统
      default:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
  }

  /// 触发分页计算 (由 View 的 LayoutBuilder 调用)
  Future<void> paginate(Size size) async {
    if (universalBook == null) return;
    if (pages.isNotEmpty) return; // 已经分页过，且未失效
    
    // 避免重复计算
    if (isLoading.value) return; 
    
    try {
      isLoading.value = true;
      
      final style = TextStyle(
        fontSize: settings.fontSize.value,
        height: settings.lineHeight.value,
        // color 不影响布局
      );
      
      final newPages = await _paginationService.paginateBook(
        book: universalBook!,
        style: style,
        pageSize: size,
        padding: const EdgeInsets.all(16.0),
      );
      
      pages.value = newPages;
      
      // 分页完成后，恢复阅读位置
      _restorePagePosition();
      
    } catch (e) {
      debugPrint("分页计算失败: $e");
    } finally {
      isLoading.value = false;
    }
  }

  /// 恢复分页模式下的阅读位置
  void _restorePagePosition() {
    if (pages.isEmpty) return;
    
    // 简单策略：根据当前的 sentenceIndex 找到对应的 page
    // 如果没有 sentenceIndex (刚打开)，则根据 lastSentenceIndex
    
    int targetSentenceIndex = currentIndex.value;
    if (targetSentenceIndex < 0) targetSentenceIndex = 0;
    
    // 我们需要知道 targetSentenceIndex 属于哪个章节，以及该句子在章节中的字符位置
    int chapterIndex = getCurrentChapterIndex();
    
    // 找到该章节对应的 pages
    int targetPageIndex = -1;
    
    // 遍历所有页面找到包含当前进度的页面
    // 这里比较粗略，因为我们只知道 sentenceIndex，不知道具体的 charIndex
    // 但我们可以通过 chapterIndex 先定位到该章的页面范围
    
    for (int i = 0; i < pages.length; i++) {
      if (pages[i].chapterIndex == chapterIndex) {
        // 找到了该章节的页面
        // 如果我们能知道当前句子的 charIndex 就完美了，但目前没有存
        // 暂时跳转到该章节的第一页
        targetPageIndex = i;
        break;
      }
    }
    
    if (targetPageIndex >= 0) {
      currentPageIndex.value = targetPageIndex;
      // 如果 PageView 已经构建，跳转
      if (pageController.hasClients) {
        pageController.jumpToPage(targetPageIndex);
      }
    }
  }

  /// 切换纯文本重排模式
  void toggleReflowMode() {
    isReflowMode.value = !isReflowMode.value;
  }


  /// 生命周期变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 🟢 回到前台：立即同步一次视觉位置
      if (sentences.isNotEmpty && currentIndex.value < sentences.length) {
         _highlightCurrentSentence();
      }
    } else if (state == AppLifecycleState.paused) {
      // 切到后台时也保存一下进度
      _saveProgress();
    }
  }

  /// 加载图书
  Future<void> _loadBook() async {
    try {
      // 仅对非 PDF 格式显示全局 Loading，因为 PDF Viewer 自带加载且需要快速显示
      if (book.format != BookFormat.pdf) {
        isLoading.value = true;
      }
      
      if (book.format == BookFormat.pdf) {
        // 1. PDF 提取文本 (异步执行，不阻塞 UI)
        _pdfService.extractText(book.filePath).then((result) {
          if (isClosed) return;
          sentences.value = result;
          _onTextExtracted();
        }).catchError((e) {
          debugPrint('PDF 文本提取失败: $e');
          Get.snackbar('提示', '未能提取到文本，可能是图片型 PDF');
        });
      } else if (book.format == BookFormat.epub) {
        // 2. EPUB 解析
        universalBook = await _epubParser.parse(book.filePath);
        _processUniversalBook();
        _onTextExtracted();
      } else if (book.format == BookFormat.txt) {
        // 3. TXT 解析
        universalBook = await _txtParser.parse(book.filePath);
        _processUniversalBook();
        _onTextExtracted();
      }
    } catch (e) {
      Get.snackbar('错误', '解析图书失败: $e');
      debugPrint('$e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 文本提取完成后的回调
  void _onTextExtracted() {
    if (sentences.isNotEmpty) {
      // 2. 恢复进度
      if (book.lastSentenceIndex < sentences.length) {
        currentIndex.value = book.lastSentenceIndex;
      } else {
        currentIndex.value = 0;
      }

      // 4. 设置 TTS 播放列表
      _ttsService.setPlaylist(sentences, currentIndex.value);
    } else {
      if (book.format == BookFormat.epub) {
         Get.snackbar('提示', 'EPUB 解析为空');
      }
    }
  }
  
  /// 处理通用图书对象，提取文本
  void _processUniversalBook() {
    List<String> allSentences = [];
    chapterStartSentenceIndices.clear();
    
    if (universalBook != null) {
      for (var chapter in universalBook!.chapters) {
        // 记录当前章节的起始句子索引
        chapterStartSentenceIndices.add(allSentences.length);
        
        allSentences.addAll(TextProcessUtil.cleanAndSplit(chapter.content));
      }
    }
    sentences.value = allSentences;
  }

  /// 获取当前句子所属的章节索引
  int getCurrentChapterIndex() {
    if (chapterStartSentenceIndices.isEmpty) return 0;
    
    // 找到最后一个 start index <= currentIndex 的章节
    // 简单二分查找或遍历
    for (int i = chapterStartSentenceIndices.length - 1; i >= 0; i--) {
      if (chapterStartSentenceIndices[i] <= currentIndex.value) {
        return i;
      }
    }
    return 0;
  }

  /// 保存进度
  Future<void> _saveProgress() async {
    // pageNumber 是 1-based
    int currentPage = pdfViewerController.pageNumber; 
    
    // 计算总进度 (简单用句子比例)
    double progress = 0.0;
    if (sentences.isNotEmpty) {
      progress = currentIndex.value / sentences.length;
    }

    await _dbService.updateProgress(
      bookId: book.id,
      pageIndex: currentPage > 0 ? currentPage - 1 : 0, // 存为 0-based
      sentenceIndex: currentIndex.value,
      totalProgress: progress,
    );
  }

  /// 播放当前句子
  Future<void> play() async {
    if (sentences.isEmpty) return;
    
    // 如果已经在播放，则是暂停逻辑
    if (_ttsService.state.value == TtsState.playing) {
      await _ttsService.pause();
      return;
    } else if (_ttsService.state.value == TtsState.paused) {
      // 如果已经准备好（暂停中），直接恢复
      await _ttsService.resume();
      return;
    }

    // 设置播放列表 (如果是第一次播放或列表未设置)
    // 注意：每次 loadBook 时都应该设置一次，这里作为保险
    // 为了避免重复设置导致 stop，可以在 TtsService 里加个检查，或者我们这里只调用 play
    // 假设 _loadBook 中已经设置了
    
    // 如果是首次播放，调用 play(currentIndex)
    await _ttsService.play(currentIndex.value);
  }

  /// 停止播放
  Future<void> stop() async {
    await _ttsService.stop();
  }

  // _playCurrentIndex 和 _playNext 已经被废弃，由 TtsService 内部托管
  // 但 prev 和 next 仍需要调用 TtsService.play

  /// 高亮当前句子
  void _highlightCurrentSentence() {
    if (sentences.isEmpty || currentIndex.value >= sentences.length) return;
    String text = sentences[currentIndex.value];
    // 简单实现：搜索该句子
    pdfViewerController.searchText(text);
  }

  /// 上一句
  void prev() {
    if (currentIndex.value > 0) {
      currentIndex.value--;
      _ttsService.play(currentIndex.value);
    }
  }

  /// 下一句
  void next() {
    if (currentIndex.value < sentences.length - 1) {
      currentIndex.value++;
      _ttsService.play(currentIndex.value);
    }
  }

  // --- 书签与笔记逻辑 ---

  Future<void> _loadAuxiliaryData() async {
    bookmarksList.value = await _dbService.getBookmarks(book.id);
    notesList.value = await _dbService.getNotes(book.id);
  }

  /// 检查当前页书签状态
  Future<void> checkBookmarkStatus(int pageIndex) async {
    isCurrentPageBookmarked.value = await _dbService.isBookmarked(book.id, pageIndex);
  }

  /// 切换当前页书签
  Future<void> toggleBookmark() async {
    // pageNumber 是 1-based
    int pageIndex = pdfViewerController.pageNumber - 1;
    if (pageIndex < 0) pageIndex = 0;
    
    await _dbService.toggleBookmark(book.id, pageIndex);
    await checkBookmarkStatus(pageIndex);
    
    // 刷新列表
    bookmarksList.value = await _dbService.getBookmarks(book.id);

    // 提示
    if (isCurrentPageBookmarked.value) {
      Get.snackbar('成功', '书签已添加', duration: const Duration(seconds: 1));
    } else {
      Get.snackbar('提示', '书签已移除', duration: const Duration(seconds: 1));
    }
  }

  /// 添加笔记
  Future<void> addNote(String selectedText, String content, int pageIndex) async {
    final note = Note(
      bookId: book.id,
      pageIndex: pageIndex,
      selectedText: selectedText,
      content: content,
      createdAt: DateTime.now(),
    );
    await _dbService.addNote(note);
    // 刷新列表
    notesList.value = await _dbService.getNotes(book.id);
    Get.snackbar('成功', '笔记已保存');
  }
  
  /// 跳转到指定页
  void jumpToPage(int pageIndex) {
    if (pageIndex >= 0) {
      pdfViewerController.jumpToPage(pageIndex + 1); // jumpToPage takes 1-based index
    }
  }
  
  /// 删除笔记
  Future<void> deleteNote(Note note) async {
    await _dbService.deleteNote(note.id);
    notesList.remove(note);
  }

  // --- 翻译功能 ---
  Future<void> translate(String text) async {
    if (text.isEmpty) return;
    try {
      isTranslating.value = true;
      var translation = await _translator.translate(text, to: 'zh-cn');
      translationResult.value = translation.text;
    } catch (e) {
      translationResult.value = "翻译失败: $e";
    } finally {
      isTranslating.value = false;
    }
  }

  // --- 睡眠定时器 ---
  void startSleepTimer(int minutes) {
    if (minutes == 0) {
      _ttsService.cancelSleepTimer();
    } else {
      _ttsService.startSleepTimer(minutes);
    }
  }
  
  void playUntilEndOfChapter() {
    _ttsService.cancelSleepTimer(); // 清除普通定时器
    
    if (book.format == BookFormat.pdf) {
       Get.snackbar("提示", "PDF 模式下暂不支持'播完本章'，请使用定时器");
       return;
    }
    
    // 1. 找到当前章节
    int chapterIndex = getCurrentChapterIndex();
    
    // 2. 找到下一章的起始位置，即本章的结束位置
    int stopIndex = sentences.length - 1;
    if (chapterIndex < chapterStartSentenceIndices.length - 1) {
      stopIndex = chapterStartSentenceIndices[chapterIndex + 1] - 1;
    }
    
    // 3. 设置 TTS
    _ttsService.setStopAtIndex(stopIndex);
    Get.snackbar("定时", "将在播完本章后停止");
  }
  
  void cancelSleepTimer() {
    _ttsService.cancelSleepTimer();
  }

  // --- PDF 目录功能 ---

  /// 加载 PDF 目录
  void loadPdfBookmarks(PdfDocument document) {
    _pdfDocument = document;
    pdfBookmarks.clear();
    if (document.bookmarks.count > 0) {
      List<PdfBookmark> bookmarks = [];
      for (int i = 0; i < document.bookmarks.count; i++) {
        bookmarks.add(document.bookmarks[i]);
      }
      pdfBookmarks.value = bookmarks;
    }
  }

  /// 跳转到 PDF 书签
  void jumpToBookmark(PdfBookmark bookmark) {
    if (_pdfDocument == null) return;
    
    PdfDestination? dest = bookmark.destination;
    if (dest != null) {
      // 获取目标页面的索引
      int index = _pdfDocument!.pages.indexOf(dest.page);
      if (index >= 0) {
        pdfViewerController.jumpToPage(index + 1); // jumpToPage 是 1-based
      }
    }
  }
}
