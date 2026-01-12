import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SettingsController>()) {
      Get.put(SettingsController());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _buildTtsSection(context),
          const Divider(),
          _buildWebDavSection(context),
          const Divider(),
          _buildCacheSection(context),
        ],
      ),
    );
  }

  Widget _buildTtsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('TTS 设置', style: Theme.of(context).textTheme.titleMedium),
        ),
        Obx(() => ListTile(
          title: const Text('语音'),
          subtitle: Text(controller.settings.ttsVoice.value),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
             _showVoiceSelectionDialog();
          },
        )),
        Obx(() => _buildSliderTile(
          title: '语速',
          value: controller.settings.ttsRate.value,
          min: 0.5,
          max: 2.0,
          onChanged: (val) => controller.settings.ttsRate.value = val,
        )),
        Obx(() => _buildSliderTile(
          title: '语调',
          value: controller.settings.ttsPitch.value,
          min: 0.5,
          max: 2.0,
          onChanged: (val) => controller.settings.ttsPitch.value = val,
        )),
      ],
    );
  }

  Widget _buildWebDavSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('WebDAV 同步', style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              TextField(
                controller: controller.webdavUrlCtrl,
                decoration: const InputDecoration(
                  labelText: '服务器地址 (URL)',
                  hintText: 'https://dav.jianguoyun.com/dav/',
                ),
              ),
              TextField(
                controller: controller.webdavUserCtrl,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              TextField(
                controller: controller.webdavPasswordCtrl,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
              Obx(() => SwitchListTile(
                title: const Text('自动同步'),
                subtitle: const Text('应用切后台时自动备份'),
                value: controller.settings.webdavAutoSync.value,
                onChanged: (val) => controller.settings.webdavAutoSync.value = val,
                contentPadding: EdgeInsets.zero,
              )),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: controller.saveWebDavSettings,
                    child: const Text('保存配置'),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.cloud_upload),
                        tooltip: '备份到云端',
                        onPressed: controller.backup,
                      ),
                      IconButton(
                        icon: const Icon(Icons.cloud_download),
                        tooltip: '从云端恢复',
                        onPressed: controller.restore,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCacheSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('存储管理', style: Theme.of(context).textTheme.titleMedium),
        ),
        ListTile(
          title: const Text('TTS 音频缓存'),
          subtitle: Obx(() => Text(controller.cacheSize.value)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _showClearCacheDialog(context),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
  }) {
    return Column(
      children: [
        ListTile(
          title: Text(title),
          trailing: Text(value.toStringAsFixed(1)),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: 15,
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    Get.defaultDialog(
      title: "清理缓存",
      middleText: "确定要清理所有 TTS 音频缓存吗？",
      textConfirm: "清理",
      textCancel: "取消",
      confirmTextColor: Colors.white,
      onConfirm: () {
        controller.clearCache();
        Get.back();
      },
    );
  }

  void _showVoiceSelectionDialog() {
    final voices = [
      'zh-CN-XiaoxiaoNeural',
      'zh-CN-YunxiNeural',
      'zh-CN-YunjianNeural',
      'zh-CN-XiaoyiNeural',
      'zh-CN-Liaoning-XiaobeiNeural',
      'zh-CN-Shaanxi-XiaoniNeural',
    ];
    
    Get.defaultDialog(
      title: "选择语音",
      content: SizedBox(
        height: 300,
        width: 300,
        child: ListView.builder(
          itemCount: voices.length,
          itemBuilder: (ctx, i) {
            return ListTile(
              title: Text(voices[i]),
              selected: controller.settings.ttsVoice.value == voices[i],
              onTap: () {
                controller.settings.ttsVoice.value = voices[i];
                Get.back();
              },
            );
          },
        ),
      ),
    );
  }
}
