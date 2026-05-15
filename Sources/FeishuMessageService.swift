import Foundation

enum FeishuMessageError: LocalizedError {
    case missingConfiguration
    case missingUserAccessToken
    case invalidURL
    case apiError(operation: String, message: String)
    case missingSentMessage

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "请先保存飞书应用配置、目标 chat_id、AI sender id/type，并完成有效授权。"
        case .missingUserAccessToken:
            "未找到可用的 user_access_token，请重新授权。"
        case .invalidURL:
            "飞书消息接口 URL 无效。"
        case .apiError(let operation, let message):
            "\(operation)失败：\(message)"
        case .missingSentMessage:
            "飞书发送接口未返回消息信息。"
        }
    }
}

struct FeishuSentMessage: Equatable {
    let messageID: String
    let chatID: String?
    let createTime: Date
}

struct FeishuReplyMessage: Equatable {
    let messageID: String
    let text: String
    let senderDescription: String
    let createTime: Date
}

final class FeishuMessageService: @unchecked Sendable {
    private enum SyncDefaults {
        static let overlapWindow: TimeInterval = 15
        static let initialLookback: TimeInterval = 30
        static let futureLeeway: TimeInterval = 5
        static let activeReplyInterval: TimeInterval = 2
        static let idleReplyInterval: TimeInterval = 5
        static let replyQuietWindow: TimeInterval = 8
        static let replyTimeout: TimeInterval = 300
    }

    private let configurationStore: FeishuConfigurationStore
    private let keychainStore: KeychainStore
    private let syncStore: FeishuMessageSyncStore
    private let oauthService: FeishuOAuthService
    private let session: URLSession

    init(
        configurationStore: FeishuConfigurationStore = FeishuConfigurationStore(),
        keychainStore: KeychainStore = KeychainStore(),
        syncStore: FeishuMessageSyncStore = FeishuMessageSyncStore(),
        oauthService: FeishuOAuthService? = nil,
        session: URLSession = .shared
    ) {
        self.configurationStore = configurationStore
        self.keychainStore = keychainStore
        self.syncStore = syncStore
        self.oauthService = oauthService ?? FeishuOAuthService(
            configurationStore: configurationStore,
            keychainStore: keychainStore,
            session: session
        )
        self.session = session
    }

    func sendTextMessage(_ text: String) async throws -> FeishuSentMessage {
        let context = try await loadRequestContext()
        guard var components = URLComponents(string: "https://open.feishu.cn/open-apis/im/v1/messages") else {
            throw FeishuMessageError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "receive_id_type", value: "chat_id")
        ]
        guard let url = components.url else {
            throw FeishuMessageError.invalidURL
        }

        let payload: [String: Any] = [
            "receive_id": context.configuration.targetChatID,
            "msg_type": "text",
            "content": try encodeContent(["text": text])
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(context.userAccessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let response = try await perform(request, as: FeishuSendMessageResponse.self, operation: "发送消息")
        guard let data = response.data, !data.messageID.isEmpty else {
            throw FeishuMessageError.missingSentMessage
        }
        return FeishuSentMessage(
            messageID: data.messageID,
            chatID: data.chatID,
            createTime: Self.date(fromFeishuTimestamp: data.createTime) ?? Date()
        )
    }

    func waitForReplies(
        after sentMessage: FeishuSentMessage,
        timeout: TimeInterval = SyncDefaults.replyTimeout,
        activeInterval: TimeInterval = SyncDefaults.activeReplyInterval,
        idleInterval: TimeInterval = SyncDefaults.idleReplyInterval,
        quietWindow: TimeInterval = SyncDefaults.replyQuietWindow
    ) async throws -> [FeishuReplyMessage] {
        let deadline = Date().addingTimeInterval(timeout)
        let minimumCreateTime = sentMessage.createTime.addingTimeInterval(-1)
        var collected: [FeishuReplyMessage] = []
        var lastReplyReceivedAt: Date?

        while Date() < deadline {
            let newMessages = try await syncIncomingMessages(minCreateTime: minimumCreateTime)
            if !newMessages.isEmpty {
                collected.append(contentsOf: newMessages)
                lastReplyReceivedAt = Date()
            }

            if let lastReplyReceivedAt,
               Date().timeIntervalSince(lastReplyReceivedAt) >= quietWindow {
                break
            }

            let interval = collected.isEmpty ? activeInterval : idleInterval
            let nanoseconds = UInt64(max(interval, 0.2) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }

        return collected
    }

    func syncIncomingMessages(
        minCreateTime: Date? = nil
    ) async throws -> [FeishuReplyMessage] {
        let context = try await loadRequestContext()
        var syncState = syncStore.loadState(for: context.configuration.targetChatID)
        let window = Self.makeSyncWindow(
            from: syncState.lastSuccessfulSyncAt,
            minCreateTime: minCreateTime
        )

        let items = try await listMessages(
            chatID: context.configuration.targetChatID,
            userAccessToken: context.userAccessToken,
            startTime: window.startTime,
            endTime: window.endTime
        )

        let recentIDs = Set(syncState.recentMessageIDs)
        let newMessages = items
            .compactMap { Self.aiMessage(from: $0, configuration: context.configuration) }
            .filter { message in
                !recentIDs.contains(message.messageID)
                    && (minCreateTime == nil || message.createTime >= minCreateTime!)
            }
            .sorted { lhs, rhs in
                if lhs.createTime == rhs.createTime {
                    return lhs.messageID < rhs.messageID
                }
                return lhs.createTime < rhs.createTime
            }
        syncState.lastSuccessfulSyncAt = window.syncedAt
        if !newMessages.isEmpty {
            syncState.recentMessageIDs.append(contentsOf: newMessages.map(\.messageID))
        }
        syncStore.saveState(syncState)
        return newMessages
    }

    func primeSyncState(with localMessages: [ChatMessage]) {
        let configuration = configurationStore.load()
        guard configuration.hasTargetChat else {
            return
        }

        let knownRemoteMessages = localMessages.compactMap { message -> (String, Date)? in
            guard message.sender == .assistant, let externalMessageID = message.externalMessageID else {
                return nil
            }
            return (externalMessageID, message.timestamp)
        }
        guard !knownRemoteMessages.isEmpty else {
            return
        }

        var state = syncStore.loadState(for: configuration.targetChatID)
        state.recentMessageIDs.append(contentsOf: knownRemoteMessages.map(\.0))
        let latestKnownTimestamp = knownRemoteMessages.map(\.1).max() ?? Date()
        if let lastSuccessfulSyncAt = state.lastSuccessfulSyncAt {
            state.lastSuccessfulSyncAt = max(lastSuccessfulSyncAt, latestKnownTimestamp)
        } else {
            state.lastSuccessfulSyncAt = latestKnownTimestamp
        }
        syncStore.saveState(state)
    }

    private func listMessages(
        chatID: String,
        userAccessToken: String,
        startTime: Int,
        endTime: Int
    ) async throws -> [FeishuMessageItem] {
        var pageToken: String?
        var collected: [FeishuMessageItem] = []

        for _ in 0..<5 {
            guard var components = URLComponents(string: "https://open.feishu.cn/open-apis/im/v1/messages") else {
                throw FeishuMessageError.invalidURL
            }
            var queryItems = [
                URLQueryItem(name: "container_id_type", value: "chat"),
                URLQueryItem(name: "container_id", value: chatID),
                URLQueryItem(name: "start_time", value: String(startTime)),
                URLQueryItem(name: "end_time", value: String(endTime)),
                URLQueryItem(name: "page_size", value: "20"),
                URLQueryItem(name: "sort_type", value: "ByCreateTimeAsc")
            ]
            if let pageToken, !pageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "page_token", value: pageToken))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw FeishuMessageError.invalidURL
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(userAccessToken)", forHTTPHeaderField: "Authorization")

            let response = try await perform(request, as: FeishuListMessagesResponse.self, operation: "读取消息")
            let data = response.data
            collected.append(contentsOf: data?.items ?? [])
            guard data?.hasMore == true, let nextPageToken = data?.pageToken, !nextPageToken.isEmpty else {
                break
            }
            pageToken = nextPageToken
        }

        return collected
    }

    private func loadRequestContext() async throws -> FeishuRequestContext {
        _ = try await oauthService.refreshUserAccessTokenIfNeeded()
        let configuration = configurationStore.load()
        guard configuration.hasTargetChat, configuration.hasAISenderFilter else {
            throw FeishuMessageError.missingConfiguration
        }
        guard let token = try keychainStore.read(account: .userAccessToken), !token.isEmpty else {
            try configurationStore.clearTokenMetadata()
            try configurationStore.updateCredentialMetadata(hasUserAccessToken: false)
            throw FeishuMessageError.missingUserAccessToken
        }
        try configurationStore.updateCredentialMetadata(hasUserAccessToken: true)
        return FeishuRequestContext(configuration: configuration, userAccessToken: token)
    }

    private func perform<Response: FeishuAPIResponse & Decodable>(
        _ request: URLRequest,
        as responseType: Response.Type,
        operation: String
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw FeishuMessageError.apiError(operation: operation, message: "HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(responseType, from: data)
        guard decoded.code == 0 else {
            throw FeishuMessageError.apiError(operation: operation, message: decoded.msg ?? "错误码 \(decoded.code)")
        }
        return decoded
    }

    private static func aiMessage(
        from item: FeishuMessageItem,
        configuration: FeishuStoredConfiguration
    ) -> FeishuReplyMessage? {
        guard isAISender(item.sender, configuration: configuration) else {
            return nil
        }
        guard let rawContent = item.body?.content ?? item.content, !rawContent.isEmpty else {
            return nil
        }
        let displayContent = contentForPresentation(rawContent: rawContent, item: item)
        let presentation = MessagePresentationParser.parse(
            rawText: displayContent,
            targetChatID: configuration.targetChatID,
            sourceMessageID: item.messageID
        )
        guard presentation.hasVisibleContent else {
            return nil
        }
        return FeishuReplyMessage(
            messageID: item.messageID,
            text: displayContent,
            senderDescription: item.sender?.description ?? "unknown",
            createTime: date(fromFeishuTimestamp: item.createTime) ?? Date()
        )
    }

    private static func contentForPresentation(rawContent: String, item: FeishuMessageItem) -> String {
        guard let quoteText = quoteText(from: item) else {
            return rawContent
        }

        let payload: [String: String] = [
            "quote_text": quoteText,
            "content": rawContent
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let wrapped = String(data: data, encoding: .utf8)
        else {
            return rawContent
        }
        return wrapped
    }

    private static func quoteText(from item: FeishuMessageItem) -> String? {
        if let quoteText = item.quote?.displayText {
            return quoteText
        }

        let hasReplyRelationship = [item.parentID, item.rootID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty && $0 != item.messageID }
        return hasReplyRelationship ? "回复了一条消息" : nil
    }

    private static func isAISender(
        _ sender: FeishuMessageSender?,
        configuration: FeishuStoredConfiguration
    ) -> Bool {
        let expectedID = configuration.aiSenderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedType = configuration.aiSenderType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedID.isEmpty, !expectedType.isEmpty else {
            return false
        }
        return sender?.id == expectedID && sender?.senderType == expectedType
    }

    private static func date(fromFeishuTimestamp value: String?) -> Date? {
        guard let value, let timestamp = Double(value) else {
            return nil
        }
        let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
        return Date(timeIntervalSince1970: seconds)
    }

    private func encodeContent(_ content: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: content)
        return String(decoding: data, as: UTF8.self)
    }

    private static func makeSyncWindow(
        from lastSuccessfulSyncAt: Date?,
        minCreateTime: Date?
    ) -> FeishuMessageSyncWindow {
        let syncedAt = Date()
        let startDate = lastSuccessfulSyncAt?
            .addingTimeInterval(-SyncDefaults.overlapWindow)
            ?? syncedAt.addingTimeInterval(-SyncDefaults.initialLookback)
        if let minCreateTime {
            let minimumStart = minCreateTime.addingTimeInterval(-SyncDefaults.overlapWindow)
            return FeishuMessageSyncWindow(
                startTime: max(0, Int(min(startDate, minimumStart).timeIntervalSince1970)),
                endTime: Int(syncedAt.addingTimeInterval(SyncDefaults.futureLeeway).timeIntervalSince1970),
                syncedAt: syncedAt
            )
        }
        return FeishuMessageSyncWindow(
            startTime: max(0, Int(startDate.timeIntervalSince1970)),
            endTime: Int(syncedAt.addingTimeInterval(SyncDefaults.futureLeeway).timeIntervalSince1970),
            syncedAt: syncedAt
        )
    }
}

private struct FeishuRequestContext {
    let configuration: FeishuStoredConfiguration
    let userAccessToken: String
}

private struct FeishuMessageSyncWindow {
    let startTime: Int
    let endTime: Int
    let syncedAt: Date
}

private protocol FeishuAPIResponse {
    var code: Int { get }
    var msg: String? { get }
}

private struct FeishuSendMessageResponse: Decodable, FeishuAPIResponse {
    let code: Int
    let msg: String?
    let data: FeishuSentMessageData?
}

private struct FeishuSentMessageData: Decodable {
    let messageID: String
    let chatID: String?
    let createTime: String?

    private enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case chatID = "chat_id"
        case createTime = "create_time"
    }
}

private struct FeishuListMessagesResponse: Decodable, FeishuAPIResponse {
    let code: Int
    let msg: String?
    let data: FeishuListMessagesData?
}

private struct FeishuListMessagesData: Decodable {
    let items: [FeishuMessageItem]
    let hasMore: Bool
    let pageToken: String?

    private enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
        case pageToken = "page_token"
    }
}

private struct FeishuMessageItem: Decodable {
    let messageID: String
    let createTime: String?
    let parentID: String?
    let rootID: String?
    let sender: FeishuMessageSender?
    let body: FeishuMessageBody?
    let content: String?
    let quote: FeishuMessageQuote?

    private enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case createTime = "create_time"
        case parentID = "parent_id"
        case rootID = "root_id"
        case sender
        case body
        case content
        case quote
    }
}

private struct FeishuMessageQuote: Decodable {
    let messageID: String?
    let text: String?
    let content: String?

    var displayText: String? {
        let candidates = [text, extractedText(from: content), messageID.map { "回复消息：\($0)" }]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case id
        case text
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageID = try container.decodeIfPresent(String.self, forKey: .messageID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        content = try container.decodeIfPresent(String.self, forKey: .content)
    }

    private func extractedText(from content: String?) -> String? {
        guard
            let content,
            let data = content.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return content
        }

        if let dictionary = object as? [String: Any] {
            if let text = dictionary["text"] as? String {
                return text
            }
            if let title = dictionary["title"] as? String {
                return title
            }
        }

        return nil
    }
}

private struct FeishuMessageSender: Decodable {
    let id: String?
    let senderType: String?
    let idType: String?

    var description: String {
        "\(senderType ?? "unknown"):\(id ?? "unknown") (\(idType ?? "unknown"))"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case senderType = "sender_type"
        case idType = "id_type"
    }
}

private struct FeishuMessageBody: Decodable {
    let content: String?
}
