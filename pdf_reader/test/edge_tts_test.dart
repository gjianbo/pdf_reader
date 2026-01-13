import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:edge_tts_dart/edge_tts_dart.dart';

void main() {
  group('EdgeTtsService Tests', () {
    test('synthesizeToFile generates an audio file', () async {
      // Create the service instance
      // Using a standard voice
      final service = EdgeTtsService(
        voice: 'zh-CN-XiaoxiaoNeural',
        rate: 1.0,
        pitch: 1.0,
      );

      final text = "这是一个测试文本。Edge TTS 工作正常。";
      
      print("Starting synthesis...");
      try {
        // synthesizeToFile usually returns the path to the generated file
        final filePath = await service.synthesizeToFile(text);
        
        print("Synthesis result path: $filePath");

        expect(filePath, isNotNull);
        expect(filePath, isNotEmpty);

        final file = File(filePath!);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));

        print("File created successfully at: ${file.absolute.path}");
        print("File size: ${file.lengthSync()} bytes");

        // Cleanup
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        print("Error during synthesis: $e");
        // Fail the test if exception occurs
        fail("Synthesis failed: $e");
      }
    });
  });
}
