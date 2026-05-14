# OpenClaw Floating Client

OpenClaw 的 macOS 极简悬浮客户端，使用 SwiftUI + AppKit 实现。应用以 `LSUIElement` 方式运行，默认不展示 Dock 图标，边缘悬浮入口负责消息提醒和未读浏览，中央 Command Input 负责快速发送。

## 当前能力

- 悬浮入口支持 6px 贴边细条、状态点、未读徽标、边缘通知卡片和未读浏览。
- 已接入未读 turn 队列、2 秒已读规则、全屏自动隐藏与恢复。
- 已接入轻量入口快捷操作：
  - `Option + Space` 打开或聚焦中央 Command Input
  - `Esc` 收起中央输入或当前未读浏览
  - 双击悬浮入口在有未读时进入未读浏览，否则打开中央输入
  - 右键悬浮入口打开极简菜单
- 完整对话窗与设置窗均使用 `NSPanel` 承载 SwiftUI 内容。

## 消息链路

1. 用户在中央 Command Input 或完整聊天窗输入文本。
2. 客户端通过飞书消息接口把文本发送到目标 `chat_id`。
3. 后台轮询飞书会话，只消费匹配 `OpenClaw sender id/type` 的回复。
4. 回复进入本地消息历史，并按 turn 聚合为悬浮入口展示与未读队列。
5. 当聊天窗未激活时，悬浮入口以边缘通知、未读徽标或未读浏览模式承接新回复。

## 安全边界

- 本项目不是端到端加密客户端；消息内容会经过飞书开放平台与目标会话。
- `app_secret`、`user_access_token`、`refresh_token` 仅保存在 macOS Keychain。
- 普通配置如 `app_id`、`redirect_uri`、`chat_id`、sender 过滤条件保存在本机 `UserDefaults`。
- 本地聊天历史会保存在 `UserDefaults`，仅用于下次启动恢复最近会话。
- 客户端只按 sender 过滤规则读取 OpenClaw 回复，不会主动遍历无关会话历史。

## 本地缓存与日志

- 聊天历史：保留最近 80 条消息，存于 `UserDefaults`。
- 去重/同步状态：飞书轮询的元数据会存于本地 `UserDefaults`。
- 悬浮位置：贴边方向与纵向锚点位置会存于 `UserDefaults`。
- 敏感凭证：全部存于 Keychain，不写入源码仓库或普通配置文件。
- DEBUG 调试事件：`DEBUG` 构建下会向本机 `http://127.0.0.1:7777/event` 发送诊断事件，用于本地调试输入与悬浮交互；默认不写入独立持久日志文件。

## 卸载与清理

卸载应用前，如需一并清理本地数据，建议执行以下步骤：

1. 删除应用本体或构建产物目录。
2. 从 Keychain 删除当前服务名下的 `app_secret`、`user_access_token`、`refresh_token`。
3. 清理应用对应的 `UserDefaults` 域，移除聊天历史、配置、同步状态和悬浮位置。
4. 如曾启用本地调试服务器，额外删除工作区中的 `.dbg/` 调试文件。

## 构建

当前环境可以先使用 Swift Package Manager 做源码级验证：

```bash
swift test --disable-sandbox
swift build --disable-sandbox
```

构建本地 `.app` bundle 并校验 `LSUIElement=true`：

```bash
./Scripts/build-app-bundle.sh debug
```

如果后续切换到完整 Xcode，请确保 target 继续使用 `AppResources/Info.plist`，以保留 `LSUIElement=true` 的后台应用形态。
