# ONEsa

ONEsa 是一个 macOS 原生极简悬浮客户端。它聚焦一个核心交互：**one sentence anytime**，用户可以随时用一句话向模型发起输入，并通过桌面边缘接收模型回复。

## 版本

- 当前版本：`v0.4.1`
- 运行形态：`LSUIElement` 后台应用，无 Dock 图标
- 技术栈：Swift、SwiftUI、AppKit、Swift Package Manager
- 最低系统：macOS 14

## 核心能力

- `Option + Space` 唤起中央输入条，输入一句话后回车发送。
- 边缘悬浮入口展示监听、输出、未读和断连等状态。
- 收到回复时从桌面边缘弹出通知，并进入未读 turn 队列。
- 有未读时支持浏览、自动已读倒计时和状态收敛。
- 完整聊天窗口用于查看历史消息、富文本内容和必要的会话操作。
- 设置窗口用于配置飞书 App、OAuth、目标会话和 AI sender 过滤条件。

## 消息展示

- 支持 Markdown 基础结构：标题、段落、引用、列表、代码块、分隔线、简单表格和内联样式。
- 支持解析常见飞书富文本结构，并优先提取可读文本内容。
- 支持展示飞书回复引用上下文和常见 AI 输出表格。
- 支持下载并展示飞书消息内图片资源；收到新回复时会立即预取可访问图片，并缓存在本机应用支持目录。
- 文件、视频等暂不直接渲染的内容会显示占位卡，并提供飞书查看入口。

## 消息链路

1. 用户通过中央输入条或完整聊天窗口发送文本。
2. 客户端调用飞书消息接口，把文本发送到目标 `chat_id`。
3. 后台轮询目标会话，只消费匹配 AI sender 过滤条件的回复。
4. 回复进入本地消息历史，并按 turn 聚合为边缘通知、未读徽标和未读浏览。
5. 完整聊天窗口未激活时，新回复会进入未读队列并触发边缘提示。

## 项目结构

```text
ONEsa/
├── AppResources/
│   └── Info.plist
├── Scripts/
│   └── build-app-bundle.sh
├── Sources/
│   ├── AppStateModel.swift
│   ├── FloatingWindowController.swift
│   ├── ChatWindowView.swift
│   ├── MessagePresentation.swift
│   └── ...
├── LICENSE
├── Package.swift
└── README.md
```

## 构建

源码构建：

```bash
swift build --disable-sandbox
```

构建本地 `.app` bundle：

```bash
./Scripts/build-app-bundle.sh debug
```

构建产物路径：

```text
.build/app/debug/ONEsa.app
```

## 配置

首次运行后，在设置窗口中填写：

- 飞书 App ID
- 飞书 App Secret
- Loopback Redirect URI
- 目标 `chat_id`
- AI sender ID
- AI sender type
- OAuth scopes

敏感凭证保存到 macOS Keychain，普通配置保存到本机 `UserDefaults`。

v0.1 使用独立的 Keychain service 命名空间。若从开发过程版本升级，首次运行后需要重新保存一次 `app_secret`，再发起飞书授权。

## 数据与安全

- 本项目不是端到端加密客户端；消息内容会经过飞书开放平台与目标会话。
- `app_secret`、`user_access_token`、`refresh_token` 保存到 macOS Keychain。
- 消息内图片资源会使用 `tenant_access_token` 下载，token 仅在内存中短期缓存。
- `app_id`、`redirect_uri`、`chat_id`、sender 过滤条件保存到 `UserDefaults`。
- 本地聊天历史仅用于恢复最近会话，默认保留最近 80 条消息。
- 客户端只按 sender 过滤规则读取 AI 回复，不主动遍历无关会话。

## 版本管理

v0.4.1 增加了收到消息后的图片资源即时预取，降低飞书短期资源失效对展示体验的影响；v0.4 增强了飞书消息内图片资源下载与本地缓存；v0.3 增强了飞书回复引用上下文、Markdown 简单表格和可抽取文本的富文本表格。调试日志、过程文档、原型文件、测试目录和构建产物不纳入版本。

## License

This project is released under the MIT License. See [LICENSE](LICENSE) for details.
