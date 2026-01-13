import 'package:get/get.dart';
import '../services/tts_service.dart';
import '../modules/bookshelf/controllers/bookshelf_controller.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(TtsService());
    Get.lazyPut(() => BookshelfController());
  }
}
