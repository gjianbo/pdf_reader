import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends GetxService {
  late SharedPreferences _prefs;

  // TTS 设置
  final ttsVoice = 'zh-CN-XiaoxiaoNeural'.obs;
  final ttsRate = 1.0.obs; // 0.5 - 2.0
  final ttsPitch = 1.0.obs; // 0.5 - 2.0
  final autoPageTurn = true.obs;

  // 外观设置
  final isDarkMode = false.obs;
  final themeColor = 0xFFF5F5DC.obs; // 默认羊皮纸色
  final fontSize = 16.0.obs;
  final lineHeight = 1.5.obs;
  final keepScreenOn = false.obs;

  // 屏幕方向
  // 0: 跟随系统, 1: 锁定竖屏, 2: 锁定横屏
  final orientationMode = 0.obs;
  // 横屏滚动方式: 0: 垂直滚动, 1: 水平翻页
  final landscapeScrollMode = 1.obs;

  // WebDAV 设置
  final webdavUrl = ''.obs;
  final webdavUser = ''.obs;
  final webdavPassword = ''.obs;
  final webdavAutoSync = false.obs;

  Future<SettingsService> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    ttsVoice.value = _prefs.getString('ttsVoice') ?? 'zh-CN-XiaoxiaoNeural';
    ttsRate.value = _prefs.getDouble('ttsRate') ?? 1.0;
    ttsPitch.value = _prefs.getDouble('ttsPitch') ?? 1.0;
    autoPageTurn.value = _prefs.getBool('autoPageTurn') ?? true;

    isDarkMode.value = _prefs.getBool('isDarkMode') ?? false;
    themeColor.value = _prefs.getInt('themeColor') ?? 0xFFF5F5DC;
    fontSize.value = _prefs.getDouble('fontSize') ?? 16.0;
    lineHeight.value = _prefs.getDouble('lineHeight') ?? 1.5;
    keepScreenOn.value = _prefs.getBool('keepScreenOn') ?? false;
    
    orientationMode.value = _prefs.getInt('orientationMode') ?? 0;
    landscapeScrollMode.value = _prefs.getInt('landscapeScrollMode') ?? 1;

    webdavUrl.value = _prefs.getString('webdavUrl') ?? '';
    webdavUser.value = _prefs.getString('webdavUser') ?? '';
    webdavPassword.value = _prefs.getString('webdavPassword') ?? '';
    webdavAutoSync.value = _prefs.getBool('webdavAutoSync') ?? false;

    // 监听变化并保存
    ever(ttsVoice, (v) => _prefs.setString('ttsVoice', v));
    ever(ttsRate, (v) => _prefs.setDouble('ttsRate', v));
    ever(ttsPitch, (v) => _prefs.setDouble('ttsPitch', v));
    ever(autoPageTurn, (v) => _prefs.setBool('autoPageTurn', v));

    ever(isDarkMode, (v) => _prefs.setBool('isDarkMode', v));
    ever(themeColor, (v) => _prefs.setInt('themeColor', v));
    ever(fontSize, (v) => _prefs.setDouble('fontSize', v));
    ever(lineHeight, (v) => _prefs.setDouble('lineHeight', v));
    ever(keepScreenOn, (v) => _prefs.setBool('keepScreenOn', v));
    
    ever(orientationMode, (v) => _prefs.setInt('orientationMode', v));
    ever(landscapeScrollMode, (v) => _prefs.setInt('landscapeScrollMode', v));

    ever(webdavUrl, (v) => _prefs.setString('webdavUrl', v));
    ever(webdavUser, (v) => _prefs.setString('webdavUser', v));
    ever(webdavPassword, (v) => _prefs.setString('webdavPassword', v));
    ever(webdavAutoSync, (v) => _prefs.setBool('webdavAutoSync', v));

    return this;
  }
}
