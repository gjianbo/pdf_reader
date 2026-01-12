import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 确保 Controller 被注入
    Get.put(HomeController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edge TTS PDF Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: controller.pickPdfFile,
          ),
        ],
      ),
      body: Column(
        children: [
          // PDF 阅读区域
          Expanded(
            child: Obx(() {
              if (controller.filePath.value.isEmpty) {
                return const Center(child: Text('请点击右上角打开 PDF 文件'));
              }
              return SfPdfViewer.file(
                File(controller.filePath.value),
                controller: controller.pdfViewerController,
                currentSearchTextHighlightColor: Colors.yellow.withOpacity(0.6),
                otherSearchTextHighlightColor: Colors.yellow.withOpacity(0.3),
              );
            }),
          ),
          
          // 底部控制栏
          _buildControlBar(),
        ],
      ),
    );
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
                    ? "准备就绪"
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
}
