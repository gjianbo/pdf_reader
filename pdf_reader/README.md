# PDF Reader 📱

[![Flutter](https://img.shields.io/badge/Flutter-3.10%2B-blue.svg)](https://flutter.dev)
[![GetX](https://img.shields.io/badge/GetX-4.6-red.svg)](https://pub.dev/packages/get)
[![Isar](https://img.shields.io/badge/Isar-3.1-purple.svg)](https://isar.dev)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

一个基于 Flutter 开发的现代化移动端电子书阅读器。它不仅是一个阅读工具，更是一个集成了云同步和智能听书功能的个人知识管理终端。

## ✨ 核心特性

### 📚 沉浸式阅读
- **多格式支持**: 完美支持 **PDF** (基于 Syncfusion) 和 **EPUB** 格式。
- **智能重排 (Reflow)**: 针对 PDF 文档提供文本重排模式，在手机小屏上也能获得如同流式文档般的阅读体验。
- **个性化体验**: 支持仿真翻页动画、夜间模式、字体缩放、背景色调节。
- **阅读进度**: 自动记录每一本书的阅读位置，精确到章节和百分比。

### 🎧 智能听书 (TTS)
- **双引擎驱动**:
  - **在线引擎**: 集成微软 **Edge TTS**，提供媲美真人的自然语音（支持多种情感和角色，如 Xiaoxiao, Yunyang）。
  - **离线引擎**: 集成系统原生 TTS，无网络环境下也能流畅朗读。
- **后台播放**: 支持锁屏控制、通知栏控制，像听音乐一样听书。
- **智能分段**: 自动解析长文本，智能断句，确保朗读流畅连贯。
- **定时关闭**: 支持睡眠定时器，伴你入睡。

### ☁️ 云端同步
- **WebDAV 协议**: 标准化的 WebDAV 支持（已适配坚果云、Nextcloud 等）。
- **全量同步**: 自动同步书架列表、阅读进度和图书文件。
- **跨设备**: 在不同设备间无缝切换阅读状态。

### 📦 极简书架
- **自动扫描**: 智能识别设备中的文档文件。
- **封面生成**: 自动提取 PDF/EPUB 首页生成封面。
- **分类管理**: 支持创建自定义分类，整理你的数字图书馆。

---

## 🛠 技术架构

本项目采用 **GetX** 作为核心架构模式，遵循 **Clean Architecture** 原则。

### 技术栈
- **UI 框架**: Flutter
- **状态管理**: GetX (Reactive State Management)
- **依赖注入**: GetX Bindings
- **本地数据库**: Isar (高性能 NoSQL，用于存储图书元数据和进度)
- **网络层**: Dio / WebDAV Client
- **音频服务**: Just Audio + Audio Service (支持后台播放)
- **解析引擎**: 
  - PDF: `syncfusion_flutter_pdfviewer`
  - EPUB: `epubx`

### 目录结构
```
lib/
├── app/
│   ├── bindings/        # 依赖注入绑定
│   ├── data/
│   │   ├── models/      # Isar 数据模型 (Book, Category)
│   │   └── providers/   # 数据提供者
│   ├── modules/         # 业务模块 (MVVM)
│   │   ├── bookshelf/   # 书架首页
│   │   ├── reader/      # 阅读器核心
│   │   └── settings/    # 设置页面
│   ├── services/        # 全局后台服务
│   │   ├── database_service.dart # 数据库封装
│   │   ├── tts_service.dart      # 语音合成服务
│   │   ├── webdav_service.dart   # 云同步服务
│   │   └── ...
│   ├── routes/          # 路由定义
│   └── utils/           # 工具类
├── main.dart            # 应用入口
└── generated/           # 自动生成的代码
```

---

## 🚀 快速开始

### 环境要求
- **Flutter SDK**: >= 3.10.0
- **Dart SDK**: >= 3.0.0
- **Android**: API Level 21+ (Android 5.0)
- **iOS**: iOS 11.0+ (暂未完全适配)

### 安装步骤

1. **获取代码**
   ```bash
   git clone https://github.com/your-repo/pdf_reader.git
   cd pdf_reader
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **生成代码**
   本项目使用 `build_runner` 生成 Isar 模型适配代码，**首次运行或修改 Model 后必须执行**：
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. **运行应用**
   ```bash
   flutter run
   ```

### � Android 配置说明
由于使用了后台播放和网络功能，`AndroidManifest.xml` 已预置以下权限：
- `INTERNET`: 网络访问（WebDAV, 在线 TTS）
- `WAKE_LOCK`: 保持后台播放唤醒
- `FOREGROUND_SERVICE`: 前台服务（音频播放）
- `READ/WRITE_EXTERNAL_STORAGE`: 文件读取

---

## ⚙️ 配置指南

### WebDAV 设置
1. 进入 **设置 -> 数据同步**。
2. 填写 WebDAV 服务器地址（如 `https://dav.jianguoyun.com/dav/`）。
3. 填写用户名和**应用密码**（注意：不是登录密码）。
4. 点击“立即同步”测试连接。

### TTS 设置
1. 进入 **设置 -> 听书设置**。
2. 选择 **语音引擎**（推荐 Edge TTS 以获得更好效果）。
3. 调整 **语速** 和 **音调**。
4. 点击“测试语音”试听效果。

---

## ❓ 常见问题 (FAQ)

**Q: 点击“测试语音”没有声音？**
A: 请检查网络连接是否正常（Edge TTS 需要联网）。如果使用的是模拟器，请确保宿主机网络通畅。

**Q: 报错 `LateInitializationError: Field '_audioHandler' ...`？**
A: 这是由于后台音频服务初始化未完成导致的。请尝试**完全重启应用**（Stop -> Run），而不是热重载（Hot Reload）。

**Q: 书架扫描不到文件？**
A: 请检查应用是否已获得存储权限。在 Android 11+ 上，可能需要授予“所有文件访问权限”才能扫描特定目录。

---

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！
在提交代码前，请确保：
1. 遵循项目的代码风格（详见 `.trae/rules/规则.md`）。
2. 新增功能已添加必要的注释。
3. 运行 `flutter test` 确保没有破坏现有功能。

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。
