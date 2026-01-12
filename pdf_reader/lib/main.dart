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
  
  // 初始化后台播放服务
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  // 初始化设置服务
  await Get.putAsync(() => SettingsService().init());

  // 初始化数据库服务
  final dbService = DatabaseService();
  await dbService.init();
  Get.put(dbService); // 注入全局

  // 初始化其他服务
  Get.put(CacheService());
  await Get.putAsync(() => WebDavService().init());

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
