import Foundation

enum UserFacingCopy {
    enum Connection {
        static let notConfiguredTitle = "未配置"
        static let notLoggedInTitle = "未登录"
        static let connectedTitle = "已连接"
        static let errorTitle = "错误"

        static let notConfiguredDetail = "请先在设置中填写飞书应用、目标 chat_id 和 AI sender。"
        static let notLoggedInDetail = "配置已保存，请完成飞书授权。"
        static let connectedDetail = "ONEsa 已就绪，并将只读取匹配 sender 的回复。"

        static func chatStatus(for snapshot: FeishuConnectionSnapshot, hasMessages: Bool) -> String {
            if !snapshot.isConfigured {
                return notConfiguredDetail
            }
            if snapshot.hasValidUserAccessToken {
                return hasMessages ? "已恢复最近本地历史，可继续发送消息。" : "已连接，可向 AI 发送第一条消息。"
            }
            if snapshot.hasRefreshToken {
                return hasMessages ? "已恢复最近本地历史，发送前会自动恢复飞书登录态。" : "已具备自动恢复登录条件，可直接发送第一条消息。"
            }
            return notLoggedInDetail
        }

        static func errorStatus(_ message: String) -> String {
            "当前连接异常：\(message)"
        }
    }

    enum Configuration {
        static let saveSucceeded = "配置已保存。敏感值保存在 Keychain，其他配置保存在本地。"
        static let missingAuthorizationConfig = "请填写飞书 app_id 和 loopback redirect_uri（仅支持 http://127.0.0.1:<port>/<path>）。"
        static let missingAppSecret = "请先保存飞书 app_secret；该值只会写入 Keychain。"
        static let missingTargetChat = "请填写目标 chat_id。"
        static let missingSenderFilter = "请填写 AI sender id 和 sender type，避免误判其他消息。"
        static let authorized = "已授权，user_access_token 当前有效。"
        static let expiredButRefreshable = "飞书登录已过期，发送前会自动尝试刷新；如刷新失败，请重新授权。"
        static let expiredNeedsAuthorization = "user_access_token 已过期或缺少过期时间，请重新授权。"
        static let readyForAuthorization = "配置已就绪，请完成飞书授权；如需自动刷新，请确保 scope 包含 offline_access。"

        static func summary(for snapshot: FeishuConnectionSnapshot) -> String {
            if !snapshot.configuration.isReadyForAuthorization {
                return missingAuthorizationConfig
            }
            if !snapshot.hasAppSecret {
                return missingAppSecret
            }
            if !snapshot.configuration.hasTargetChat {
                return missingTargetChat
            }
            if !snapshot.configuration.hasAISenderFilter {
                return missingSenderFilter
            }
            if snapshot.hasValidUserAccessToken {
                return authorized
            }
            if snapshot.hasRefreshToken {
                return expiredButRefreshable
            }
            if snapshot.hasUserAccessToken {
                return expiredNeedsAuthorization
            }
            return readyForAuthorization
        }
    }

    enum Authorization {
        static let browserOpened = "已打开系统浏览器，请在飞书授权页完成授权；若未自动回调，可改用下方“手动输入授权码”。"
        static let success = "飞书授权成功，user_access_token 已保存到 Keychain。"
        static let manualSuccess = "手动授权成功，user_access_token 已保存到 Keychain。"
        static let chatReady = "飞书授权已连接，可发送消息并等待 AI 回复。"
        static let submitWhileAuthorizing = "当前仍在等待自动回调，请先取消授权等待，或等待自动回调结束后再手动提交 code。"
        static let manualExchanging = "正在使用手动输入的授权码换取 user_access_token..."
        static let cancelledWithFallback = "已取消当前授权等待；如果浏览器中已经拿到 code，可直接在下方“手动输入授权码”，否则请检查回调地址后重新授权。"
        static let cancelled = "已取消当前授权等待，可检查飞书后台回调地址或权限后重新授权。"
        static let cleared = "已清除本地 user_access_token 和 refresh_token，请重新授权。"
        static let startupRefreshing = "检测到飞书登录已过期，正在尝试自动刷新..."
        static let startupRestoring = "正在恢复飞书登录状态..."
        static let startupRefreshSucceeded = "已自动刷新飞书登录态。"
        static let manualFallbackHint = "可在下方“手动输入授权码”中粘贴浏览器返回的 code 继续换取 token，或重新发起授权。"
        static let callbackCancelledFallback = "已取消当前授权等待；如果浏览器中已经拿到 code，可直接在下方“手动输入授权码”中继续完成授权。"
    }

    enum Chat {
        static let sendBlockedPrefix = "发送前还缺："
        static let sendBlockedSuffix = "。请先到设置页补齐或重新授权。"
        static let connectedReady = "已连接，可向 AI 发送消息。"
        static let clearedConfigured = "已清空本地会话，可继续发送新消息。"
        static let clearedNeedsSetup = "已清空本地会话，请先补齐配置并完成授权。"
        static let emptyInput = "请输入消息内容。"
        static let sendBusy = "上一条消息仍在发送或等待回复，请稍后再试。"
        static let sendUnavailable = "当前无法发送消息。"
        static let sending = "正在通过飞书发送消息..."
        static let waitingReply = "消息已发送，正在持续轮询目标会话并等待 AI 回复；如果任务较长，后台会继续监听新消息。"
        static let replyReceivedPrefix = "已读取 AI 回复"
        static let timeoutSystemMessage = "当前任务等待超时：在限定时间内未读到 AI 回复，但后台仍会继续监听该会话中的新消息。"
        static let timeoutStatusMessage = "当前任务等待超时，后台仍会继续监听 AI 新消息。"
        static let waitStopped = "已停止当前前台等待；后台仍会继续监听 AI 新消息。"
        static let clearHistoryTooltip = "清空本地保存的当前会话历史"
        static let emptyHistoryConfigured = "发送第一条消息后，最近聊天记录会自动保存到本机并在下次打开时恢复。"
        static let startupPendingFailure = "应用关闭前该消息未完成，已改为失败状态，可点击重试。"
        static let backgroundListening = "后台正在监听 AI 新消息。"

        static func missingItems(_ titles: [String]) -> String {
            "\(sendBlockedPrefix)\(titles.joined(separator: "、"))\(sendBlockedSuffix)"
        }

        static func sendFailure(_ message: String) -> String {
            "发送或读取失败：\(message)"
        }

        static func replyReceived(senderDescription: String) -> String {
            "\(replyReceivedPrefix)（\(senderDescription)）。"
        }

        static func backgroundReceived(count: Int, hasOfflineBadge: Bool) -> String {
            let prefix = count == 1
                ? "已在后台收到 1 条新的 AI 消息。"
                : "已在后台收到 \(count) 条新的 AI 消息。"
            guard hasOfflineBadge else {
                return prefix
            }
            return "\(prefix) 这些内容来自离线期间。"
        }
    }

    enum Turn {
        static let offlinePeriodBadge = "离线期间"
        static let nextTurnAction = "下一条"
        static let markReadAction = "标记已读"

        static func browserStatus(remaining: Int) -> String {
            remaining == 1 ? "最后 1 条未读 turn" : "还剩 \(remaining) 条未读 turn"
        }
    }

    enum Recovery {
        static let readyTitle = "配置已就绪"
        static let configurationRequiredTitle = "待完成配置"
        static let keychainAccessRequiredTitle = "需要钥匙串权限"
        static let authorizationRequiredTitle = "需要飞书授权"
        static let authorizationExpiredTitle = "授权已过期"
        static let agentOfflineTitle = "AI 当前离线"
        static let invalidChatTitle = "目标会话不可用"

        static let openSettingsAction = "打开设置"
        static let startAuthorizationAction = "开始授权"
        static let reauthorizeAction = "重新授权"
        static let reconnectAction = "重新连接"
        static let keychainAccessContinueAction = "继续连接"

        static func configurationRequired(missingTitles: [String]) -> String {
            guard !missingTitles.isEmpty else {
                return "请先补齐飞书应用配置、目标会话和 AI sender 信息。"
            }
            return "当前还缺：\(missingTitles.joined(separator: "、"))。请先补齐这些配置。"
        }

        static let authorizationRequiredDetail = "当前配置已保存，但还没有可用的飞书登录态，请先完成授权。"
        static let authorizationRefreshableDetail = "当前登录态已过期，但已具备自动刷新条件；发送或重试连接时会先尝试恢复。"
        static let keychainAccessRequiredDetail = "ONEsa 需要访问钥匙串以读取飞书凭证。点击“继续连接”后系统会弹出密码或允许访问提示。"

        static func authorizationExpired(_ message: String) -> String {
            "当前飞书登录态已失效：\(message)"
        }

        static func agentOffline(_ message: String) -> String {
            "当前无法确认 AI 在线，已阻止继续发送。\(message)"
        }

        static func invalidChat(_ message: String) -> String {
            "当前 chat_id 可能无效或无权限访问，请检查设置中的目标会话。\(message)"
        }
    }
}

enum MessageTextFormatter {
    static func normalize(_ rawText: String) -> String {
        MessagePresentationParser.parse(rawText: rawText).summaryText
    }
}
