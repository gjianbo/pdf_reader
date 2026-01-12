import 'dart:async';
import 'package:edge_tts_dart/edge_tts_dart.dart';

/// TTS 服务类
/// 使用 edge_tts_dart 库与 Edge TTS 接口通信
class TtsService {
  late final EdgeTtsService _ttsService;

  // 默认语音，中文女声
  final String _voice = 'zh-CN-XiaoxiaoNeural';

  TtsService() {
    _ttsService = EdgeTtsService(
      voice: _voice,
      rate: 1.0,
      pitch: 1.0,
    );
  }

  /// 将文本转换为音频文件
  /// 返回生成的 MP3 文件路径
  Future<String> textToSpeech(String text) async {
    try {
      // 使用库提供的 synthesizeToFile 方法
      // 注意：该库生成的临时文件可能没有唯一 ID，如果并发请求可能会覆盖
      // 但我们的场景是顺序播放，应该问题不大
      // 库内部使用了 path_provider 获取临时目录
      String? filePath = await _ttsService.synthesizeToFile(text);
      
      if (filePath != null) {
        return filePath;
      } else {
        throw Exception("Failed to synthesize audio: filePath is null");
      }
    } catch (e) {
      print('TTS Error: $e');
      throw e;
    }
  }

  /// 获取可用声音列表
  Future<List<EdgeVoice>> getVoices() async {
    return await _ttsService.getVoices();
  }

  void dispose() {
    _ttsService.dispose();
  }
}
