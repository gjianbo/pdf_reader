import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../services/audio_service.dart';
import '../../../services/pdf_service.dart';
import '../../../services/tts_service.dart';

/// 首页控制器
/// 负责协调 PDF 加载、文本提取、TTS 合成与播放、以及 UI 高亮同步
class HomeController extends GetxController with WidgetsBindingObserver {
  // 服务实例
  final PdfService _pdfService = PdfService();
  final TtsService _ttsService = TtsService();
  final AudioService _audioService = AudioService();

  // 状态变量
  final RxString filePath = ''.obs; // 当前 PDF 文件路径
  final RxList<String> sentences = <String>[].obs; // 提取并分句后的文本列表
  final RxInt currentIndex = 0.obs; // 当前朗读句子的索引
  final RxBool isLoading = false.obs; // 加载状态
  final RxBool isPlaying = false.obs; // 播放状态

  // UI 控制器
  final PdfViewerController pdfViewerController = PdfViewerController();
  
  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    
    // 监听播放状态流，自动处理下一句
    _audioService.player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        // 当前句子播放完毕，自动播放下一句
        _playNext();
      }
      
      // 更新播放按钮状态
      isPlaying.value = playerState.playing;
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioService.dispose();
    _ttsService.dispose();
    super.onClose();
  }

  /// 生命周期变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 🟢 回到前台：立即同步一次视觉位置
      if (sentences.isNotEmpty && currentIndex.value < sentences.length) {
         _highlightCurrentSentence();
      }
    }
    // 🔴 切到后台：UI 线程暂停，Syncfusion 的搜索高亮不需要在后台执行
  }

  /// 选择并打开 PDF 文件
  Future<void> pickPdfFile() async {
    // 请求存储权限 (Android 11+ 可能需要 MANAGE_EXTERNAL_STORAGE，这里先请求基本的)
    var status = await Permission.storage.request();
    if (status.isDenied) {
      Get.snackbar('权限错误', '需要存储权限来读取 PDF 文件');
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      filePath.value = result.files.single.path!;
      await _loadAndExtractText(filePath.value);
    }
  }

  /// 加载 PDF 并提取文本
  Future<void> _loadAndExtractText(String path) async {
    try {
      isLoading.value = true;
      sentences.value = await _pdfService.extractText(path);
      currentIndex.value = 0;
      
      if (sentences.isNotEmpty) {
        Get.snackbar('解析成功', '共提取 ${sentences.length} 句话');
      } else {
        Get.snackbar('提示', '未能提取到文本，可能是图片型 PDF');
      }
    } catch (e) {
      Get.snackbar('错误', '解析 PDF 失败: $e');
      print(e);
    } finally {
      isLoading.value = false;
    }
  }

  /// 播放当前句子
  Future<void> play() async {
    if (sentences.isEmpty) return;
    
    // 如果已经在播放，则是暂停逻辑 (AudioService 暂未封装 pause，直接用 player)
    if (_audioService.player.playing) {
      await _audioService.player.pause();
      return;
    } else if (_audioService.player.processingState == ProcessingState.ready) {
      // 如果已经准备好（暂停中），直接恢复
      await _audioService.player.play();
      return;
    }

    await _playCurrentIndex();
  }

  /// 停止播放
  Future<void> stop() async {
    await _audioService.stop();
  }

  /// 播放指定索引的句子 (内部核心逻辑)
  Future<void> _playCurrentIndex() async {
    if (currentIndex.value >= sentences.length) return;

    try {
      String text = sentences[currentIndex.value];
      
      // 1. 高亮 (仅在前台时)
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _highlightCurrentSentence();
      }

      // 2. 合成音频
      // 优化：可以做预加载，这里先实现 MVP
      String audioPath = await _ttsService.textToSpeech(text);

      // 3. 播放
      await _audioService.playFile(audioPath, title: text.length > 20 ? "${text.substring(0, 20)}..." : text);

    } catch (e) {
      print("播放失败: $e");
      Get.snackbar('播放错误', 'TTS 合成失败，跳过该句');
      _playNext(); // 出错跳过
    }
  }

  /// 播放下一句
  void _playNext() {
    if (currentIndex.value < sentences.length - 1) {
      currentIndex.value++;
      _playCurrentIndex();
    } else {
      Get.snackbar('结束', '全文朗读完毕');
      stop();
    }
  }

  /// 高亮当前句子
  void _highlightCurrentSentence() {
    String text = sentences[currentIndex.value];
    
    // 使用 Syncfusion PDF Viewer 的搜索功能进行高亮
    // 注意：这会搜索全文，如果有重复句子可能会定位错误。
    // 解决方案：可以使用 nextInstance，但需要维护状态。MVP 阶段暂简单处理。
    // 另外，searchText 是异步的，但在 UI 线程触发
    
    // 清除上一次的高亮 (Syncfusion 似乎没有直接清除单个的 API，searchText 会覆盖或清除)
    // 实际上 searchText 会高亮所有匹配项，我们需要跳转到当前实例
    
    // 这里简单实现：搜索该句子，并跳转到第一个匹配项 (或者尝试根据页码优化，暂未实现)
    pdfViewerController.searchText(text);
  }
  
  /// 上一句
  void prev() {
    if (currentIndex.value > 0) {
      currentIndex.value--;
      stop(); // 停止当前播放
      _playCurrentIndex();
    }
  }

  /// 下一句
  void next() {
    if (currentIndex.value < sentences.length - 1) {
      currentIndex.value++;
      stop();
      _playCurrentIndex();
    }
  }
}
