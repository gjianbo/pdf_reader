import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app/modules/bookshelf/views/bookshelf_view.dart';
import 'app/services/database_service.dart';
import 'app/services/settings_service.dart';
import 'app/services/cache_service.dart';
import 'app/services/webdav_service.dart';

Future<void> main() async {
  // 初始化绑定
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('App Start: WidgetsFlutterBinding initialized');
  
  // 初始化后台播放服务
  debugPrint('App Start: Initializing JustAudioBackground...');
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    );
    debugPrint('App Start: JustAudioBackground initialized');
  } catch (e) {
    debugPrint('App Start: JustAudioBackground error: $e');
  }

  // 初始化设置服务
  debugPrint('App Start: Initializing SettingsService...');
  await Get.putAsync(() => SettingsService().init());
  debugPrint('App Start: SettingsService initialized');

  // 初始化数据库服务
  debugPrint('App Start: Initializing DatabaseService...');
  final dbService = DatabaseService();
  await dbService.init();
  Get.put(dbService); // 注入全局
  debugPrint('App Start: DatabaseService initialized');

  // 初始化其他服务
  debugPrint('App Start: Initializing CacheService & WebDavService...');
  Get.put(CacheService());
  await Get.putAsync(() => WebDavService().init());
  debugPrint('App Start: All services initialized, calling runApp');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Flutter PDF Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BookshelfView(),
    );
  }
}
