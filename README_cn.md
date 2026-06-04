# Etonify

<div align="center">

[English](README.md) / [Русский](README_ru.md) / [Українська](README_uk.md) / [简体中文](README_cn.md) / [فارسی](README_fa.md)

<img width="1672" height="941" alt="etonify" src="https://github.com/user-attachments/assets/c5a9780c-6b26-45e1-9458-42c23e204dde" />

[![Android](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter)](#)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-@etonify-26A5E4?style=flat-square&logo=telegram)](https://t.me/etonify)

**面向 Android 的开源 VPN 客户端，基于修改版 sing-box 核心。**

</div>

Etonify 是一个以 Android 为核心目标的 VPN 客户端，面向需要透明、可维护、社区驱动替代方案的用户。项目最初受 Hiddify 相关思路启发，但 Android 运行时、订阅处理、界面、诊断和维护流程正在围绕 Etonify 与修改版 **MeowSingBox** 核心重建。

本应用不提供 VPN 服务器。它是用于导入和使用你拥有或有权使用的订阅与配置的客户端。

## 状态

Etonify 仍处于早期公开开发阶段。目前 Android 是唯一的生产目标。仓库中可能保留其他 Flutter 平台目录，但它们暂时不是发布目标。

## 功能

- 基于修改版 sing-box 的 Android VPN TUN 模式。
- 本地 mixed proxy inbound，供手动配置 HTTP/SOCKS 的应用或设备使用。
- 支持通过 URL、二维码、本地文件、剪贴板和 deep links 导入订阅。
- Deep link 处理：`etonify://`、`happ://add`、`happ://crypt*`、`sing-box://import-remote-profile`。
- Happ link decryptor，支持 `crypt`、`crypt2`、`crypt3`、`crypt4` 和 `crypt5`。
- 支持 Happ 订阅，并在 provider 要求 HWID 时先请求用户明确确认。
- 订阅刷新、重新解析、流量/到期时间显示，以及对无效刷新结果的安全处理。
- 代理列表支持国家旗帜、延迟、订阅原始顺序、按延迟/名称/国家排序、URL-test 和快速切换服务器。
- Split tunneling：Android VPN 应用 allow/disallow 规则，并保留 sing-box 路由 fallback。
- DNS 预设与自定义 DNS resolver，支持 UDP、TCP、DoT、DoH 和设备 DNS。
- Russia routing helpers 与本地 AdGuard 风格规则。
- 流量仪表板，显示实时速度、会话统计、活动 profile、活动 proxy 和轻量图表。
- GitHub Releases 更新中心，可按设备架构选择 APK 并显示下载进度。
- Runtime 日志、诊断、内存清理 hooks，以及对已知敏感值的脱敏。
- 应用内已有 RU/EN 本地化，计划继续扩展用户界面翻译。

## 社区

- Telegram 频道：[@etonify](https://t.me/etonify)
- 欢迎 Issues 和 Pull Requests。
- 欢迎报告安全问题。请在团队有时间调查前，避免公开发布可利用细节。

## 开发

要求：

- Flutter 3.44.0 或更新版本，Dart `>=3.11.4`。
- Android SDK 36。
- 可使用 JDK 21 运行 Gradle；为了兼容当前 AGP，Android bytecode 仍以 Java 17 为目标。

常用命令：

```powershell
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
```

用于设备测试的本地 release APK：

```powershell
$env:MEOW_ALLOW_DEBUG_RELEASE_SIGNING='true'
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

公开发布需要真实的 release keystore 和 `android/key.properties`。该文件已被 Git 忽略。

## 说明

- 生产目标是 Android。
- 除非单独验证 sing-box API 兼容性，否则 `libbox.aar` 保持不变。
- `lib/l10n/generated` 下的生成文件会保留在源码树中，因为应用会直接导入它们。
- `third_party/flutter_circle_flags` 是 `pubspec.yaml` 中需要的本地 path dependency。
- 第三方组件和项目历史说明记录在 [NOTICE.md](NOTICE.md)。
- 官方 release 构建可以包含通过 GitHub Actions secrets 恢复的私有 Happ crypto compatibility assets。这些 assets 不属于公开源码树。

## 许可证

Etonify 使用 [Apache License 2.0](LICENSE) 授权。
