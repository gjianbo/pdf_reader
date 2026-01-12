import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// 音频播放服务
/// 负责播放 TTS 生成的音频文件
class AudioService {
  final AudioPlayer _player = AudioPlayer();

  /// 播放指定路径的音频文件
  /// [filePath] 本地文件路径
  /// [title] 显示在通知栏的标题 (可选)
  Future<void> playFile(String filePath, {String title = "正在朗读"}) async {
    try {
      // 设置音频源，包含元数据以便后台显示
      final source = AudioSource.file(
        filePath,
        tag: MediaItem(
          id: filePath,
          album: "PDF Reader",
          title: title,
          artUri: null, // 可以设置封面图
        ),
      );

      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      print("Error playing audio: $e");
    }
  }

  /// 停止播放
  Future<void> stop() async {
    await _player.stop();
  }

  /// 监听播放完成事件
  Stream<ProcessingState> get processingStateStream => _player.processingStateStream;
  
  /// 获取播放器实例 (如果需要更精细控制)
  AudioPlayer get player => _player;

  void dispose() {
    _player.dispose();
  }
}
