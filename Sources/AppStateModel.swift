import Foundation

enum AppConnectionState: Equatable {
    case notConfigured
    case notLoggedIn
    case connected
    case error(String)

    var title: String {
        switch self {
        case .notConfigured:
            UserFacingCopy.Connection.notConfiguredTitle
        case .notLoggedIn:
            UserFacingCopy.Connection.notLoggedInTitle
        case .connected:
            UserFacingCopy.Connection.connectedTitle
        case .error:
            UserFacingCopy.Connection.errorTitle
        }
    }

    var detail: String {
        switch self {
        case .notConfigured:
            UserFacingCopy.Connection.notConfiguredDetail
        case .notLoggedIn:
            UserFacingCopy.Connection.notLoggedInDetail
        case .connected:
            UserFacingCopy.Connection.connectedDetail
        case .error(let message):
            message
        }
    }
}

enum ChatMessageSender: String, Codable, Equatable {
    case user
    case assistant
    case system

    var displayName: String {
        switch self {
        case .user:
            "我"
        case .assistant:
            "OpenClaw"
        case .system:
            "系统"
        }
    }
}

enum ChatMessageDeliveryState: Codable, Equatable {
    case local
    case sending
    case waitingReply
    case sent
    case failed(String)

    private enum CodingKeys: String, CodingKey {
        case name
        case message
    }

    private enum Name: String, Codable {
        case local
        case sending
        case waitingReply
        case sent
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(Name.self, forKey: .name)
        switch name {
        case .local:
            self = .local
        case .sending:
            self = .sending
        case .waitingReply:
            self = .waitingReply
        case .sent:
            self = .sent
        case .failed:
            self = .failed(try container.decodeIfPresent(String.self, forKey: .message) ?? "未知错误")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .local:
            try container.encode(Name.local, forKey: .name)
        case .sending:
            try container.encode(Name.sending, forKey: .name)
        case .waitingReply:
            try container.encode(Name.waitingReply, forKey: .name)
        case .sent:
            try container.encode(Name.sent, forKey: .name)
        case .failed(let message):
            try container.encode(Name.failed, forKey: .name)
            try container.encode(message, forKey: .message)
        }
    }

    var title: String {
        switch self {
        case .local:
            "本地"
        case .sending:
            "发送中"
        case .waitingReply:
            "等待回复"
        case .sent:
            "已发送"
        case .failed:
            "失败"
        }
    }

    var isInFlight: Bool {
        switch self {
        case .sending, .waitingReply:
            true
        case .local, .sent, .failed:
            false
        }
    }
}

enum BackgroundPollingStatus: Equatable {
    case paused(String)
    case listening
    case retrying
}

struct BackgroundPollingUIState: Equatable {
    var status: BackgroundPollingStatus
    var latestSyncAt: Date?
    var consecutiveFailureCount: Int
    var nextRetryAt: Date?

    static let paused = BackgroundPollingUIState(
        status: .paused("后台监听暂停"),
        latestSyncAt: nil,
        consecutiveFailureCount: 0,
        nextRetryAt: nil
    )

    var title: String {
        switch status {
        case .paused:
            "监听暂停"
        case .listening:
            "后台监听中"
        case .retrying:
            "轮询重试中"
        }
    }

    var detail: String {
        switch status {
        case .paused(let reason):
            return reason
        case .listening:
            if let latestSyncAt {
                return "最近同步 \(latestSyncAt.formatted(date: .omitted, time: .standard))"
            }
            return "等待首次同步"
        case .retrying:
            let retryText = nextRetryAt.map { "，下次重试 \($0.formatted(date: .omitted, time: .standard))" } ?? ""
            return "已连续失败 \(consecutiveFailureCount) 次\(retryText)"
        }
    }
}

struct ForegroundTaskUIState: Equatable {
    enum Phase: Equatable {
        case sending
        case waiting
        case timedOut
    }

    let messageID: UUID
    let startedAt: Date
    var phase: Phase

    var title: String {
        switch phase {
        case .sending:
            "正在发送"
        case .waiting:
            "等待 OpenClaw 回复"
        case .timedOut:
            "已转后台监听"
        }
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let externalMessageID: String?
    let sender: ChatMessageSender
    let text: String
    let timestamp: Date
    let deliveryState: ChatMessageDeliveryState

    init(
        id: UUID = UUID(),
        externalMessageID: String? = nil,
        sender: ChatMessageSender,
        text: String,
        timestamp: Date = Date(),
        deliveryState: ChatMessageDeliveryState = .local
    ) {
        self.id = id
        self.externalMessageID = externalMessageID
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.deliveryState = deliveryState
    }
}

enum SetupChecklistGroup: String, Equatable {
    case required
    case recommended
    case automatic
}

struct SetupChecklistItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let group: SetupChecklistGroup
    let isMissing: Bool
    let isBlocking: Bool
}

enum RecoveryActionKind: Equatable {
    case openSettings
    case startAuthorization
    case reauthorize
    case reconnect
}

struct RecoveryActionDescriptor: Identifiable, Equatable {
    let kind: RecoveryActionKind
    let title: String

    var id: RecoveryActionKind { kind }
}

enum RecoveryStateKind: Equatable {
    case ready
    case configurationRequired
    case authorizationRequired
    case authorizationExpired
    case agentOffline
    case invalidChat
}

struct RecoveryStateProjection: Equatable {
    let kind: RecoveryStateKind
    let title: String
    let detail: String
    let primaryAction: RecoveryActionDescriptor?
    let secondaryAction: RecoveryActionDescriptor?
    let blocksSending: Bool

    var isReady: Bool {
        kind == .ready
    }
}

struct ConfigurationStatusProjection: Equatable {
    let title: String
    let detail: String
    let tokenStatusText: String
    let missingItems: [SetupChecklistItem]
    let requiredItems: [SetupChecklistItem]
    let recommendedItems: [SetupChecklistItem]
    let automaticItems: [SetupChecklistItem]
    let primaryAction: RecoveryActionDescriptor?
    let secondaryAction: RecoveryActionDescriptor?

    var missingCount: Int {
        missingItems.count
    }
}

struct ChatSendReadiness: Equatable {
    let blockingItems: [SetupChecklistItem]
    let recoveryState: RecoveryStateProjection?

    var canAttemptSend: Bool {
        blockingItems.isEmpty && recoveryState == nil
    }

    var blockingMessage: String? {
        if let recoveryState {
            return recoveryState.detail
        }
        guard !blockingItems.isEmpty else {
            return nil
        }
        return UserFacingCopy.Chat.missingItems(blockingItems.map(\.title))
    }

    var primaryAction: RecoveryActionDescriptor? {
        recoveryState?.primaryAction
    }

    var secondaryAction: RecoveryActionDescriptor? {
        recoveryState?.secondaryAction
    }
}

struct FloatingNotificationState: Identifiable, Equatable {
    let id: UUID
    let turn: AssistantTurn
    let createdAt: Date

    var text: String { turn.summaryText }

    init(id: UUID = UUID(), turn: AssistantTurn, createdAt: Date) {
        self.id = id
        self.turn = turn
        self.createdAt = createdAt
    }
}

enum FloatingPrimaryVisualState: Equatable {
    case idle
    case listening
    case thinking
    case outputting
    case disconnected
}

enum EdgeNotifyMode: Equatable {
    case idle
    case liveNotification
    case unreadBadge
    case fullscreenSuppressed
}

struct EdgeNotifyState: Equatable {
    let mode: EdgeNotifyMode
    let unreadCount: Int
    let notification: FloatingNotificationState?
    let latestTurn: AssistantTurn?

    var isComposeSurface: Bool { false }
}

struct CommandInputState: Equatable {
    let isPresented: Bool
    let isSending: Bool
    let draft: String
    let recoveryState: RecoveryStateProjection?
}

struct UnreadBrowserState: Equatable {
    let isActive: Bool
    let currentTurn: AssistantTurn?
    let remainingCount: Int
    let statusText: String?
}

struct FullChatWindowState: Equatable {
    let isPresented: Bool
    let isActive: Bool
}

struct LightweightSurfaceProjection: Equatable {
    let edgeNotify: EdgeNotifyState
    let commandInput: CommandInputState
    let unreadBrowser: UnreadBrowserState
    let fullChat: FullChatWindowState
}

enum AssistantTurnBadge: Equatable {
    case offlinePeriod

    var title: String {
        switch self {
        case .offlinePeriod:
            return UserFacingCopy.Turn.offlinePeriodBadge
        }
    }
}

struct AssistantTurn: Identifiable, Equatable {
    let id: UUID
    let messageIDs: [String]
    let summaryText: String
    let latestTimestamp: Date
    let badge: AssistantTurnBadge?

    init(
        id: UUID = UUID(),
        messageIDs: [String],
        summaryText: String,
        latestTimestamp: Date,
        badge: AssistantTurnBadge? = nil
    ) {
        self.id = id
        self.messageIDs = messageIDs
        self.summaryText = summaryText
        self.latestTimestamp = latestTimestamp
        self.badge = badge
    }
}

struct RecoveryIssue: Equatable {
    let kind: RecoveryStateKind
    let message: String
}

@MainActor
final class AppStateModel: ObservableObject {
    static let shared = AppStateModel()
    private static let maxLocalMessageCount = 80
    private static let maxUnreadTurnCount = 20
    private static let normalBackgroundPollingInterval: TimeInterval = 4
    private static let retryBackgroundPollingInterval: TimeInterval = 8

    @Published var connectionState: AppConnectionState
    @Published private(set) var messages: [ChatMessage] {
        didSet {
            historyStore.save(messages)
        }
    }
    @Published private(set) var chatStatusMessage: String
    @Published private(set) var feishuSnapshot: FeishuConnectionSnapshot
    @Published private(set) var configurationStatusMessage: String
    @Published private(set) var isAuthorizing: Bool
    @Published private(set) var isSendingMessage: Bool
    @Published private(set) var pollingUIState: BackgroundPollingUIState
    @Published private(set) var foregroundTaskUIState: ForegroundTaskUIState?
    @Published private(set) var unreadAssistantTurnCount: Int
    @Published private(set) var isMiniChatExpanded: Bool
    @Published private(set) var isExpandedConversationPresented: Bool
    @Published private(set) var isUnreadTurnBrowserActive: Bool
    @Published private(set) var isCommandInputPresented: Bool
    @Published private(set) var displayedAssistantTurn: AssistantTurn?
    @Published private(set) var floatingNotification: FloatingNotificationState?
    @Published private(set) var isFloatingHiddenForFullscreen: Bool
    @Published private(set) var recoveryIssue: RecoveryIssue?

    private let oauthService: FeishuOAuthService
    private let messageService: FeishuMessageService
    private let historyStore: ChatHistoryStore
    private let miniCollapseDelay: Duration
    private let notificationDismissDelay: Duration
    private let unreadTurnReadDelay: Duration
    private var authorizationTask: Task<Void, Never>?
    private var backgroundPollingTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var miniCollapseTask: Task<Void, Never>?
    private var unreadTurnReadWorkItem: DispatchWorkItem?
    private var floatingNotificationWorkItem: DispatchWorkItem?
    private var authorizationAttemptID: UInt64 = 0
    private var isChatWindowActive = false
    private var isFloatingHovered = false
    private var isMiniComposerFocused = false
    private var isFloatingPanelDragging = false
    private var commandInputDraft = ""
    private var commandInputSubmissionDrafts: [UUID: String] = [:]
    private var shouldCollapseMiniChatAfterUnreadRead = false
    private var suppressMiniChatExpansionUntil: Date?
    private var stoppedForegroundMessageIDs = Set<UUID>()
    private var unreadAssistantTurns: [AssistantTurn] = [] {
        didSet {
            unreadAssistantTurnCount = unreadAssistantTurns.count
            refreshDisplayedAssistantTurn()
        }
    }
    private var latestAssistantTurn: AssistantTurn? {
        didSet {
            refreshDisplayedAssistantTurn()
        }
    }

    init(
        oauthService: FeishuOAuthService = FeishuOAuthService(),
        messageService: FeishuMessageService = FeishuMessageService(),
        historyStore: ChatHistoryStore = ChatHistoryStore(),
        messages: [ChatMessage]? = nil,
        chatStatusMessage: String? = nil,
        miniCollapseDelay: Duration = .milliseconds(800),
        notificationDismissDelay: Duration = .seconds(6),
        unreadTurnReadDelay: Duration = .seconds(2)
    ) {
        let snapshot = oauthService.loadSnapshot()
        let connectionState = Self.connectionState(for: snapshot)
        let restoredMessages = Self.normalizedRestoredMessages(messages ?? historyStore.load())
        self.oauthService = oauthService
        self.messageService = messageService
        self.historyStore = historyStore
        self.miniCollapseDelay = miniCollapseDelay
        self.notificationDismissDelay = notificationDismissDelay
        self.feishuSnapshot = snapshot
        self.connectionState = connectionState
        self.messages = restoredMessages
        self.chatStatusMessage = chatStatusMessage ?? Self.chatStatusMessage(
            for: snapshot,
            state: connectionState,
            hasMessages: !restoredMessages.isEmpty
        )
        self.configurationStatusMessage = UserFacingCopy.Configuration.summary(for: snapshot)
        self.isAuthorizing = false
        self.isSendingMessage = false
        self.pollingUIState = .paused
        self.foregroundTaskUIState = nil
        self.unreadAssistantTurnCount = 0
        self.isMiniChatExpanded = false
        self.isExpandedConversationPresented = false
        self.isUnreadTurnBrowserActive = false
        self.isCommandInputPresented = false
        self.displayedAssistantTurn = nil
        self.floatingNotification = nil
        self.isFloatingHiddenForFullscreen = false
        self.recoveryIssue = nil
        self.historyStore.save(restoredMessages)
        self.messageService.primeSyncState(with: restoredMessages)
        self.latestAssistantTurn = Self.restoreLatestAssistantTurn(
            from: restoredMessages,
            targetChatID: snapshot.configuration.targetChatID
        )
        self.unreadTurnReadDelay = unreadTurnReadDelay
        updateBackgroundPolling()
        attemptStartupTokenRefreshIfNeeded()
    }

    var feishuConfiguration: FeishuStoredConfiguration {
        feishuSnapshot.configuration
    }

    var hasSavedAppSecret: Bool {
        feishuSnapshot.hasAppSecret
    }

    var hasUserAccessToken: Bool {
        feishuSnapshot.hasUserAccessToken
    }

    var hasRefreshToken: Bool {
        feishuSnapshot.hasRefreshToken
    }

    var hasAnySavedAuthorization: Bool {
        feishuSnapshot.hasUserAccessToken || feishuSnapshot.hasRefreshToken
    }

    var canUseManualAuthorizationCodeFallback: Bool {
        oauthService.hasPendingAuthorizationCodeExchange
    }

    var setupChecklistItems: [SetupChecklistItem] {
        Self.setupChecklistItems(for: feishuSnapshot)
    }

    var requiredSetupItems: [SetupChecklistItem] {
        setupChecklistItems.filter { $0.group == .required }
    }

    var recommendedSetupItems: [SetupChecklistItem] {
        setupChecklistItems.filter { $0.group == .recommended }
    }

    var automaticSetupItems: [SetupChecklistItem] {
        setupChecklistItems.filter { $0.group == .automatic }
    }

    var missingSetupItems: [SetupChecklistItem] {
        setupChecklistItems.filter(\.isMissing)
    }

    var chatSendReadiness: ChatSendReadiness {
        ChatSendReadiness(
            blockingItems: setupChecklistItems.filter { $0.isMissing && $0.isBlocking },
            recoveryState: recoveryState.blocksSending ? recoveryState : nil
        )
    }

    var recoveryState: RecoveryStateProjection {
        Self.recoveryState(
            for: feishuSnapshot,
            missingItems: missingSetupItems,
            recoveryIssue: recoveryIssue
        )
    }

    var configurationStatusProjection: ConfigurationStatusProjection {
        let recoveryState = recoveryState
        let primaryAction = recoveryState.isReady ? nil : recoveryState.primaryAction
        let secondaryAction = recoveryState.isReady ? nil : recoveryState.secondaryAction
        let title: String
        if recoveryState.kind == .authorizationRequired || recoveryState.kind == .authorizationExpired {
            title = recoveryState.title
        } else {
            title = missingSetupItems.isEmpty ? UserFacingCopy.Recovery.readyTitle : "还缺 \(missingSetupItems.count) 项配置"
        }
        let detail = recoveryState.isReady ? configurationStatusMessage : recoveryState.detail
        return ConfigurationStatusProjection(
            title: title,
            detail: detail,
            tokenStatusText: tokenStatusText,
            missingItems: missingSetupItems,
            requiredItems: requiredSetupItems,
            recommendedItems: recommendedSetupItems,
            automaticItems: automaticSetupItems,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        )
    }

    func presentationModel(for message: ChatMessage) -> MessagePresentationModel {
        MessagePresentationParser.parse(
            rawText: message.text,
            targetChatID: feishuSnapshot.configuration.targetChatID
        )
    }

    var latestAssistantPreviewText: String? {
        displayedAssistantTurn?.summaryText
    }

    var latestAssistantPreviewTimestamp: Date? {
        displayedAssistantTurn?.latestTimestamp
    }

    var currentAssistantTurnBadgeTitle: String? {
        displayedAssistantTurn?.badge?.title
    }

    var lightweightSurfaceProjection: LightweightSurfaceProjection {
        LightweightSurfaceProjection(
            edgeNotify: edgeNotifyState,
            commandInput: commandInputState,
            unreadBrowser: unreadBrowserState,
            fullChat: fullChatWindowState
        )
    }

    var edgeNotifyState: EdgeNotifyState {
        let mode: EdgeNotifyMode
        if isFloatingHiddenForFullscreen {
            mode = .fullscreenSuppressed
        } else if floatingNotification != nil {
            mode = .liveNotification
        } else if unreadAssistantTurnCount > 0 {
            mode = .unreadBadge
        } else {
            mode = .idle
        }
        return EdgeNotifyState(
            mode: mode,
            unreadCount: unreadAssistantTurnCount,
            notification: floatingNotification,
            latestTurn: latestAssistantTurn
        )
    }

    var commandInputState: CommandInputState {
        let recoveryState = chatSendReadiness.canAttemptSend ? nil : self.recoveryState
        return CommandInputState(
            isPresented: isCommandInputPresented,
            isSending: isSendingMessage,
            draft: commandInputDraft,
            recoveryState: recoveryState
        )
    }

    var unreadBrowserState: UnreadBrowserState {
        UnreadBrowserState(
            isActive: isUnreadTurnBrowserActive,
            currentTurn: isUnreadTurnBrowserActive ? unreadAssistantTurns.first : nil,
            remainingCount: unreadAssistantTurnCount,
            statusText: unreadTurnBrowserStatusText
        )
    }

    var fullChatWindowState: FullChatWindowState {
        FullChatWindowState(
            isPresented: isExpandedConversationPresented,
            isActive: isChatWindowActive
        )
    }

    var floatingPrimaryVisualState: FloatingPrimaryVisualState {
        if !recoveryState.isReady || isFloatingHiddenForFullscreen || pollingUIState.status == .retrying {
            return .disconnected
        }
        if unreadAssistantTurnCount > 0 && isUnreadTurnBrowserActive {
            return .outputting
        }
        if unreadAssistantTurnCount > 0 || floatingNotification != nil {
            return .outputting
        }
        if displayedAssistantTurn != nil && (isMiniChatExpanded || floatingNotification != nil) {
            return .outputting
        }
        if let foregroundTaskUIState {
            switch foregroundTaskUIState.phase {
            case .sending, .waiting:
                return .thinking
            case .timedOut:
                break
            }
        }
        if isMiniChatExpanded || isExpandedConversationPresented || isFloatingHovered || isMiniComposerFocused {
            return .listening
        }
        return .idle
    }

    var hasUnreadTurnOverlay: Bool {
        unreadAssistantTurnCount > 0
    }

    var unreadTurnBrowserActionTitle: String {
        unreadAssistantTurnCount > 1 ? UserFacingCopy.Turn.nextTurnAction : UserFacingCopy.Turn.markReadAction
    }

    var unreadTurnBrowserStatusText: String? {
        guard unreadAssistantTurnCount > 0 else {
            return nil
        }
        return UserFacingCopy.Turn.browserStatus(remaining: unreadAssistantTurnCount)
    }

    var showsCircularFloatingAnchor: Bool {
        isMiniChatExpanded || isExpandedConversationPresented || isCommandInputPresented
    }

    var canDismissLightweightEntryWithEscape: Bool {
        isMiniChatExpanded && !isExpandedConversationPresented
    }

    var tokenStatusText: String {
        if let tokenExpiresAt = feishuConfiguration.tokenExpiresAt {
            return tokenExpiresAt.formatted(date: .abbreviated, time: .standard)
        }
        if hasRefreshToken {
            return "等待自动刷新"
        }
        return "未授权"
    }

    func markNotConfigured() {
        connectionState = .notConfigured
        chatStatusMessage = connectionState.detail
    }

    func markNotLoggedIn() {
        connectionState = .notLoggedIn
        chatStatusMessage = connectionState.detail
    }

    func markConnected() {
        connectionState = .connected
        chatStatusMessage = UserFacingCopy.Chat.connectedReady
    }

    func markError(_ message: String) {
        connectionState = .error(message)
        chatStatusMessage = message
    }

    func refreshFeishuSnapshot() {
        applySnapshot(oauthService.loadSnapshot())
    }

    func saveFeishuConfiguration(
        appID: String,
        appSecret: String,
        redirectURI: String,
        targetChatID: String,
        openClawSenderID: String,
        openClawSenderType: String,
        scopes: String
    ) -> Bool {
        do {
            try oauthService.saveConfiguration(
                appID: appID,
                appSecret: appSecret,
                redirectURI: redirectURI,
                targetChatID: targetChatID,
                openClawSenderID: openClawSenderID,
                openClawSenderType: openClawSenderType,
                scopes: scopes
            )
            applySnapshot(oauthService.loadSnapshot())
            messageService.primeSyncState(with: messages)
            configurationStatusMessage = UserFacingCopy.Configuration.saveSucceeded
            recoveryIssue = nil
            return true
        } catch {
            markError(error.localizedDescription)
            configurationStatusMessage = error.localizedDescription
            return false
        }
    }

    func authorizeWithFeishu() {
        guard !isAuthorizing else { return }
        guard hasSavedAppSecret else {
            let message = FeishuOAuthError.missingAppSecret.localizedDescription
            configurationStatusMessage = message
            chatStatusMessage = message
            return
        }

        authorizationAttemptID &+= 1
        let attemptID = authorizationAttemptID
        isAuthorizing = true
        configurationStatusMessage = UserFacingCopy.Authorization.browserOpened
        chatStatusMessage = configurationStatusMessage

        authorizationTask = Task {
            do {
                let snapshot = try await oauthService.authorize()
                guard !Task.isCancelled, attemptID == self.authorizationAttemptID else {
                    return
                }
                applySnapshot(snapshot)
                configurationStatusMessage = UserFacingCopy.Authorization.success
                chatStatusMessage = UserFacingCopy.Authorization.chatReady
                recoveryIssue = nil
            } catch {
                guard !Task.isCancelled, attemptID == self.authorizationAttemptID else {
                    return
                }
                let latestSnapshot = oauthService.loadSnapshot()
                applySnapshot(latestSnapshot)
                let message = Self.authorizationFailureMessage(
                    for: error,
                    canUseManualFallback: oauthService.hasPendingAuthorizationCodeExchange
                )
                configurationStatusMessage = message
                chatStatusMessage = message
                recoveryIssue = Self.recoveryIssue(for: error)
            }
            if attemptID == self.authorizationAttemptID {
                isAuthorizing = false
                authorizationTask = nil
            }
        }
    }

    func submitManualAuthorizationCode(_ rawCode: String) {
        guard !isAuthorizing else {
            configurationStatusMessage = UserFacingCopy.Authorization.submitWhileAuthorizing
            chatStatusMessage = configurationStatusMessage
            return
        }
        guard canUseManualAuthorizationCodeFallback else {
            let message = FeishuOAuthError.missingPendingAuthorization.localizedDescription
            configurationStatusMessage = message
            chatStatusMessage = message
            return
        }

        authorizationAttemptID &+= 1
        let attemptID = authorizationAttemptID
        isAuthorizing = true
        configurationStatusMessage = UserFacingCopy.Authorization.manualExchanging
        chatStatusMessage = configurationStatusMessage

        authorizationTask = Task {
            do {
                let snapshot = try await oauthService.exchangePendingAuthorizationCode(rawCode)
                guard !Task.isCancelled, attemptID == self.authorizationAttemptID else {
                    return
                }
                applySnapshot(snapshot)
                configurationStatusMessage = UserFacingCopy.Authorization.manualSuccess
                chatStatusMessage = UserFacingCopy.Authorization.chatReady
                recoveryIssue = nil
            } catch {
                guard !Task.isCancelled, attemptID == self.authorizationAttemptID else {
                    return
                }
                let latestSnapshot = oauthService.loadSnapshot()
                applySnapshot(latestSnapshot)
                let message = Self.authorizationFailureMessage(
                    for: error,
                    canUseManualFallback: oauthService.hasPendingAuthorizationCodeExchange
                )
                configurationStatusMessage = message
                chatStatusMessage = message
                recoveryIssue = Self.recoveryIssue(for: error)
            }
            if attemptID == self.authorizationAttemptID {
                isAuthorizing = false
                authorizationTask = nil
            }
        }
    }

    func cancelAuthorization() {
        guard isAuthorizing else { return }

        authorizationAttemptID &+= 1
        authorizationTask?.cancel()
        authorizationTask = nil
        isAuthorizing = false

        let snapshot = oauthService.loadSnapshot()
        applySnapshot(snapshot)
        recoveryIssue = nil
        if oauthService.hasPendingAuthorizationCodeExchange {
            configurationStatusMessage = UserFacingCopy.Authorization.cancelledWithFallback
        } else {
            configurationStatusMessage = UserFacingCopy.Authorization.cancelled
        }
        chatStatusMessage = configurationStatusMessage
    }

    func clearFeishuAuthorization() {
        do {
            let snapshot = try oauthService.clearAuthorization()
            applySnapshot(snapshot)
            configurationStatusMessage = UserFacingCopy.Authorization.cleared
            recoveryIssue = nil
        } catch {
            markError(error.localizedDescription)
            configurationStatusMessage = error.localizedDescription
        }
    }

    func clearConversationHistory() {
        messages.removeAll()
        unreadAssistantTurns.removeAll()
        latestAssistantTurn = nil
        isUnreadTurnBrowserActive = false
        unreadTurnReadWorkItem?.cancel()
        unreadTurnReadWorkItem = nil
        dismissFloatingNotification()
        chatStatusMessage = feishuSnapshot.isConfigured
            ? UserFacingCopy.Chat.clearedConfigured
            : UserFacingCopy.Chat.clearedNeedsSetup
    }

    func chatWindowDidBecomeActive() {
        isChatWindowActive = true
    }

    func chatWindowDidResignActive() {
        isChatWindowActive = false
    }

    func floatingHoverChanged(_ isHovered: Bool) {
        guard !isFloatingPanelDragging else {
            return
        }
        isFloatingHovered = isHovered
        if floatingNotification != nil {
            if isHovered {
                floatingNotificationWorkItem?.cancel()
                floatingNotificationWorkItem = nil
            } else if floatingNotificationWorkItem == nil {
                scheduleFloatingNotificationDismiss()
            }
        }
        if isHovered {
            if let suppressMiniChatExpansionUntil {
                if Date() < suppressMiniChatExpansionUntil {
                    return
                }
                self.suppressMiniChatExpansionUntil = nil
            }
        } else {
            scheduleMiniChatCollapseIfNeeded()
        }
    }

    func floatingDragChanged(_ isDragging: Bool) {
        isFloatingPanelDragging = isDragging
        if isDragging {
            miniCollapseTask?.cancel()
            miniCollapseTask = nil
            isFloatingHovered = true
            suppressMiniChatExpansionUntil = nil
        } else {
            scheduleMiniChatCollapseIfNeeded()
        }
    }

    func miniComposerFocusChanged(_ isFocused: Bool) {
        isMiniComposerFocused = isFocused
        if !isFocused {
            scheduleMiniChatCollapseIfNeeded()
        }
    }

    func presentCommandInput(restoringDraft draft: String? = nil) {
        if let draft {
            commandInputDraft = draft
        }
        miniCollapseTask?.cancel()
        miniCollapseTask = nil
        suppressMiniChatExpansionUntil = nil
        isCommandInputPresented = true
        isMiniChatExpanded = true
        if unreadAssistantTurnCount > 0 {
            shouldCollapseMiniChatAfterUnreadRead = true
            isUnreadTurnBrowserActive = true
            scheduleUnreadTurnReadIfNeeded()
        }
        dismissFloatingNotification()
    }

    func updateCommandInputDraft(_ draft: String) {
        commandInputDraft = draft
    }

    func dismissCommandInput(preserveDraft: Bool = true) {
        isCommandInputPresented = false
        if !preserveDraft {
            commandInputDraft = ""
        }
        resolveLightweightSurfaceAfterCommandInputChange()
    }

    @discardableResult
    func submitCommandInputDraft() -> Bool {
        let submittedDraft = commandInputDraft
        guard let messageID = beginSendingMessage(submittedDraft) else {
            isCommandInputPresented = true
            commandInputDraft = submittedDraft
            return false
        }
        commandInputSubmissionDrafts[messageID] = submittedDraft
        isCommandInputPresented = false
        if unreadAssistantTurnCount > 0 {
            shouldCollapseMiniChatAfterUnreadRead = true
        }
        resolveLightweightSurfaceAfterCommandInputChange()
        return true
    }

    func presentUnreadBrowserFromEdge() {
        guard unreadAssistantTurnCount > 0 else {
            return
        }
        miniCollapseTask?.cancel()
        miniCollapseTask = nil
        suppressMiniChatExpansionUntil = nil
        shouldCollapseMiniChatAfterUnreadRead = isCommandInputPresented
        isMiniChatExpanded = true
        isUnreadTurnBrowserActive = true
        scheduleUnreadTurnReadIfNeeded()
        dismissFloatingNotification()
    }

    func presentMiniChat() {
        guard unreadAssistantTurnCount > 0 else {
            return
        }
        presentUnreadBrowserFromEdge()
    }

    func collapseMiniChatImmediately() {
        miniCollapseTask?.cancel()
        miniCollapseTask = nil
        guard !isFloatingHovered, !isMiniComposerFocused, !isFloatingPanelDragging else {
            return
        }
        isMiniChatExpanded = false
        unreadTurnReadWorkItem?.cancel()
        unreadTurnReadWorkItem = nil
    }

    func dismissMiniChatForExplicitUserAction() {
        miniCollapseTask?.cancel()
        miniCollapseTask = nil
        unreadTurnReadWorkItem?.cancel()
        unreadTurnReadWorkItem = nil
        isFloatingHovered = false
        isMiniComposerFocused = false
        isMiniChatExpanded = false
        isUnreadTurnBrowserActive = false
        shouldCollapseMiniChatAfterUnreadRead = false
        suppressMiniChatExpansionUntil = Date().addingTimeInterval(0.6)
    }

    func setExpandedConversationPresented(_ isPresented: Bool) {
        isExpandedConversationPresented = isPresented
        if isPresented {
            miniCollapseTask?.cancel()
            miniCollapseTask = nil
            isFloatingHovered = false
            isMiniComposerFocused = false
            suppressMiniChatExpansionUntil = nil
            dismissFloatingNotification()
            return
        }
        if (isFloatingHovered || isMiniComposerFocused), unreadAssistantTurnCount > 0 {
            presentUnreadBrowserFromEdge()
        }
    }

    func dismissFloatingNotification() {
        floatingNotificationWorkItem?.cancel()
        floatingNotificationWorkItem = nil
        floatingNotification = nil
    }

    func advanceUnreadTurn() {
        guard !unreadAssistantTurns.isEmpty else {
            return
        }
        unreadTurnReadWorkItem?.cancel()
        unreadTurnReadWorkItem = nil
        unreadAssistantTurns.removeFirst()
        isUnreadTurnBrowserActive = !unreadAssistantTurns.isEmpty
        dismissFloatingNotification()
        if isMiniChatExpanded && isUnreadTurnBrowserActive {
            scheduleUnreadTurnReadIfNeeded()
        } else if shouldCollapseMiniChatAfterUnreadRead {
            resolveLightweightSurfaceAfterCommandInputChange()
        }
    }

    func setFloatingHiddenForFullscreen(_ isHidden: Bool) {
        guard isFloatingHiddenForFullscreen != isHidden else {
            return
        }
        isFloatingHiddenForFullscreen = isHidden
        if isHidden {
            dismissFloatingNotification()
            unreadTurnReadWorkItem?.cancel()
            unreadTurnReadWorkItem = nil
            isMiniChatExpanded = false
            isUnreadTurnBrowserActive = false
            isCommandInputPresented = false
        }
    }

    func stopCurrentForegroundWait() {
        guard let foregroundTaskUIState else {
            return
        }
        stoppedForegroundMessageIDs.insert(foregroundTaskUIState.messageID)
        sendTask?.cancel()
        sendTask = nil
        isSendingMessage = false
        self.foregroundTaskUIState = nil
        updateMessage(id: foregroundTaskUIState.messageID, deliveryState: .sent)
        chatStatusMessage = UserFacingCopy.Chat.waitStopped
        updateBackgroundPolling()
    }

    func retryConnectionRecovery() {
        recoveryIssue = nil
        refreshFeishuSnapshot()
        updateBackgroundPolling()
        attemptStartupTokenRefreshIfNeeded()
    }

    func performRecoveryAction(_ action: RecoveryActionKind) {
        switch action {
        case .startAuthorization, .reauthorize:
            authorizeWithFeishu()
        case .reconnect:
            retryConnectionRecovery()
        case .openSettings:
            break
        }
    }

    @discardableResult
    func sendMessage(_ rawText: String) -> Bool {
        beginSendingMessage(rawText) != nil
    }

    @discardableResult
    private func beginSendingMessage(_ rawText: String) -> UUID? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            chatStatusMessage = UserFacingCopy.Chat.emptyInput
            return nil
        }
        guard !isSendingMessage else {
            chatStatusMessage = UserFacingCopy.Chat.sendBusy
            return nil
        }
        if !feishuSnapshot.isConfigured || (!feishuSnapshot.hasUserAccessToken && !feishuSnapshot.hasRefreshToken) {
            refreshFeishuSnapshot()
        }
        let sendReadiness = chatSendReadiness
        guard sendReadiness.canAttemptSend else {
            chatStatusMessage = sendReadiness.blockingMessage ?? UserFacingCopy.Chat.sendUnavailable
            return nil
        }

        let message = ChatMessage(
            sender: .user,
            text: text,
            deliveryState: .sending
        )
        appendMessage(message)
        performSend(messageID: message.id, text: text)
        return message.id
    }

    func retryMessage(id: UUID) {
        guard !isSendingMessage else {
            chatStatusMessage = UserFacingCopy.Chat.sendBusy
            return
        }
        guard let message = messages.first(where: { $0.id == id }), message.sender == .user else {
            return
        }
        updateMessage(id: id, deliveryState: .sending)
        performSend(messageID: id, text: message.text)
    }

    private func applySnapshot(_ snapshot: FeishuConnectionSnapshot) {
        feishuSnapshot = snapshot
        connectionState = Self.connectionState(for: snapshot)
        chatStatusMessage = Self.chatStatusMessage(for: snapshot, state: connectionState, hasMessages: !messages.isEmpty)
        configurationStatusMessage = UserFacingCopy.Configuration.summary(for: snapshot)
        updateBackgroundPolling()
    }

    private static func connectionState(for snapshot: FeishuConnectionSnapshot) -> AppConnectionState {
        guard snapshot.isConfigured else {
            return .notConfigured
        }

        if snapshot.hasValidUserAccessToken || snapshot.hasRefreshToken {
            return .connected
        }

        return .notLoggedIn
    }

    private static func chatStatusMessage(
        for snapshot: FeishuConnectionSnapshot,
        state: AppConnectionState,
        hasMessages: Bool
    ) -> String {
        switch state {
        case .notConfigured, .notLoggedIn, .connected:
            UserFacingCopy.Connection.chatStatus(for: snapshot, hasMessages: hasMessages)
        case .error(let message):
            UserFacingCopy.Connection.errorStatus(message)
        }
    }

    private static func authorizationFailureMessage(for error: Error, canUseManualFallback: Bool) -> String {
        let baseMessage = error.localizedDescription
        guard canUseManualFallback else {
            return baseMessage
        }

        switch error {
        case FeishuOAuthError.callbackTimeout,
             FeishuOAuthError.callbackServerFailed,
             FeishuOAuthError.invalidCallbackRequest,
             FeishuOAuthError.callbackError,
             FeishuOAuthError.missingAuthorizationCode:
            return "\(baseMessage) \(UserFacingCopy.Authorization.manualFallbackHint)"
        case FeishuOAuthError.callbackCancelled:
            return UserFacingCopy.Authorization.callbackCancelledFallback
        default:
            return baseMessage
        }
    }

    private static func setupChecklistItems(for snapshot: FeishuConnectionSnapshot) -> [SetupChecklistItem] {
        let configuration = snapshot.configuration
        let scopeTokens = configuration.scopes
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let hasOfflineAccessScope = scopeTokens.contains("offline_access")

        let authorizationDetail: String
        let authorizationMissing: Bool
        if snapshot.hasValidUserAccessToken {
            authorizationDetail = "已授权，当前有可用的 user_access_token。"
            authorizationMissing = false
        } else if snapshot.hasRefreshToken {
            authorizationDetail = "当前主要依赖 refresh_token；发送时会先自动刷新登录态。"
            authorizationMissing = false
        } else if snapshot.hasUserAccessToken {
            authorizationDetail = "旧的 user_access_token 已过期且没有可用 refresh_token，请重新授权。"
            authorizationMissing = true
        } else {
            authorizationDetail = "尚未完成 OAuth 授权；完成授权后系统会自动拿到 user_access_token。"
            authorizationMissing = true
        }

        return [
            SetupChecklistItem(
                id: "app_credentials",
                title: "App ID 与 Loopback Redirect URI",
                detail: configuration.isReadyForAuthorization
                    ? "已填写授权所需的 app_id 和 127.0.0.1 loopback 回调地址。"
                    : "需要填写 app_id 和 127.0.0.1 loopback 回调地址，才能发起 OAuth 授权。",
                group: .required,
                isMissing: !configuration.isReadyForAuthorization,
                isBlocking: true
            ),
            SetupChecklistItem(
                id: "app_secret",
                title: "App Secret",
                detail: snapshot.hasAppSecret
                    ? "已保存到 Keychain；留空保存不会覆盖已存值。"
                    : "尚未保存 app_secret；这是换取和刷新 token 的必填项。",
                group: .required,
                isMissing: !snapshot.hasAppSecret,
                isBlocking: true
            ),
            SetupChecklistItem(
                id: "target_chat",
                title: "目标 chat_id",
                detail: configuration.hasTargetChat
                    ? "已指定要发送消息的目标会话。"
                    : "尚未填写 chat_id，系统不知道把消息发到哪个会话。",
                group: .required,
                isMissing: !configuration.hasTargetChat,
                isBlocking: true
            ),
            SetupChecklistItem(
                id: "sender_filter",
                title: "OpenClaw sender 过滤",
                detail: configuration.hasOpenClawSenderFilter
                    ? "已配置 sender id 和 sender type，只会读取 OpenClaw 的回复。"
                    : "尚未填写 sender id/type，系统无法可靠区分 OpenClaw 回复和其他消息。",
                group: .required,
                isMissing: !configuration.hasOpenClawSenderFilter,
                isBlocking: true
            ),
            SetupChecklistItem(
                id: "offline_access_scope",
                title: "offline_access Scope",
                detail: hasOfflineAccessScope
                    ? "已包含 offline_access，可在 access_token 过期后自动刷新。"
                    : "建议把 offline_access 加入 scope，减少 access_token 过期后的手动重登。",
                group: .recommended,
                isMissing: !hasOfflineAccessScope,
                isBlocking: false
            ),
            SetupChecklistItem(
                id: "oauth_session",
                title: "飞书登录态",
                detail: authorizationDetail,
                group: .automatic,
                isMissing: authorizationMissing,
                isBlocking: authorizationMissing
            )
        ]
    }

    private func performSend(messageID: UUID, text: String) {
        isSendingMessage = true
        connectionState = .connected
        chatStatusMessage = UserFacingCopy.Chat.sending
        foregroundTaskUIState = ForegroundTaskUIState(
            messageID: messageID,
            startedAt: Date(),
            phase: .sending
        )
        updateBackgroundPolling()

        sendTask = Task {
            defer {
                isSendingMessage = false
                if self.foregroundTaskUIState?.messageID == messageID {
                    self.foregroundTaskUIState = nil
                }
                updateBackgroundPolling()
            }

            do {
                let sentMessage = try await messageService.sendTextMessage(text)
                if commandInputSubmissionDrafts.removeValue(forKey: messageID) != nil {
                    commandInputDraft = ""
                    isCommandInputPresented = false
                }
                applySnapshot(oauthService.loadSnapshot())
                updateMessage(id: messageID, deliveryState: .waitingReply)
                foregroundTaskUIState = ForegroundTaskUIState(
                    messageID: messageID,
                    startedAt: foregroundTaskUIState?.startedAt ?? Date(),
                    phase: .waiting
                )
                chatStatusMessage = UserFacingCopy.Chat.waitingReply

                let replies = try await messageService.waitForReplies(after: sentMessage)
                guard !Task.isCancelled, !stoppedForegroundMessageIDs.contains(messageID) else {
                    updateMessage(id: messageID, deliveryState: .sent)
                    chatStatusMessage = UserFacingCopy.Chat.waitStopped
                    return
                }
                if !replies.isEmpty {
                    applySnapshot(oauthService.loadSnapshot())
                    recoveryIssue = nil
                    updateMessage(id: messageID, deliveryState: .sent)
                    appendAssistantMessages(replies, countUnread: !isChatWindowActive)
                    if let latestReply = replies.last {
                        chatStatusMessage = UserFacingCopy.Chat.replyReceived(senderDescription: latestReply.senderDescription)
                    }
                } else {
                    updateMessage(id: messageID, deliveryState: .sent)
                    foregroundTaskUIState = ForegroundTaskUIState(
                        messageID: messageID,
                        startedAt: foregroundTaskUIState?.startedAt ?? Date(),
                        phase: .timedOut
                    )
                    appendMessage(
                        ChatMessage(
                            sender: .system,
                            text: UserFacingCopy.Chat.timeoutSystemMessage,
                            deliveryState: .local
                        )
                    )
                    chatStatusMessage = UserFacingCopy.Chat.timeoutStatusMessage
                }
            } catch is CancellationError {
                updateMessage(id: messageID, deliveryState: .sent)
                chatStatusMessage = UserFacingCopy.Chat.waitStopped
            } catch {
                let message = error.localizedDescription
                if let draft = commandInputSubmissionDrafts[messageID] {
                    commandInputDraft = draft
                    isCommandInputPresented = true
                }
                updateMessage(id: messageID, deliveryState: .failed(message))
                let latestSnapshot = oauthService.loadSnapshot()
                applySnapshot(latestSnapshot)
                recoveryIssue = Self.recoveryIssue(for: error)
                if case FeishuOAuthError.missingRefreshToken = error {
                    configurationStatusMessage = message
                    chatStatusMessage = message
                } else if case FeishuOAuthError.reauthorizationRequired = error {
                    configurationStatusMessage = message
                    chatStatusMessage = message
                } else {
                    connectionState = .error(message)
                    chatStatusMessage = recoveryState.blocksSending
                        ? recoveryState.detail
                        : UserFacingCopy.Chat.sendFailure(message)
                }
            }
            commandInputSubmissionDrafts.removeValue(forKey: messageID)
        }
    }

    private func attemptStartupTokenRefreshIfNeeded() {
        guard feishuSnapshot.isConfigured, feishuSnapshot.hasRefreshToken, !feishuSnapshot.hasValidUserAccessToken else {
            return
        }
        configurationStatusMessage = UserFacingCopy.Authorization.startupRefreshing
        chatStatusMessage = UserFacingCopy.Authorization.startupRestoring

        Task {
            do {
                let snapshot = try await oauthService.refreshUserAccessTokenIfNeeded()
                applySnapshot(snapshot)
                if snapshot.hasValidUserAccessToken {
                    configurationStatusMessage = UserFacingCopy.Authorization.startupRefreshSucceeded
                    chatStatusMessage = Self.chatStatusMessage(for: snapshot, state: connectionState, hasMessages: !messages.isEmpty)
                    recoveryIssue = nil
                }
            } catch {
                let latestSnapshot = oauthService.loadSnapshot()
                applySnapshot(latestSnapshot)
                configurationStatusMessage = error.localizedDescription
                chatStatusMessage = error.localizedDescription
                recoveryIssue = Self.recoveryIssue(for: error)
            }
        }
    }

    private func updateBackgroundPolling() {
        if shouldRunBackgroundPolling {
            guard backgroundPollingTask == nil else {
                return
            }
            if case .retrying = pollingUIState.status {
            } else {
                pollingUIState.status = .listening
                pollingUIState.nextRetryAt = nil
            }
            backgroundPollingTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    await self.performBackgroundPollingCycle()
                    let interval = UInt64(self.nextBackgroundPollingInterval * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: interval)
                }
            }
            if !isSendingMessage && !recoveryState.blocksSending {
                chatStatusMessage = UserFacingCopy.Chat.backgroundListening
            }
        } else {
            backgroundPollingTask?.cancel()
            backgroundPollingTask = nil
            pollingUIState.status = .paused(pollingPauseReason)
            pollingUIState.nextRetryAt = nil
        }
    }

    private var shouldRunBackgroundPolling: Bool {
        feishuSnapshot.isConfigured
            && (feishuSnapshot.hasValidUserAccessToken || feishuSnapshot.hasRefreshToken)
            && !isAuthorizing
            && !isSendingMessage
    }

    private var pollingPauseReason: String {
        if isAuthorizing {
            return "飞书授权进行中，暂时暂停后台监听。"
        }
        if isSendingMessage {
            return "前台正在等待当前任务，后台监听会在结束后继续。"
        }
        if !feishuSnapshot.isConfigured {
            return "请先完成飞书应用、目标会话和 OpenClaw sender 配置。"
        }
        return "请完成飞书授权后开启后台监听。"
    }

    private var nextBackgroundPollingInterval: TimeInterval {
        pollingUIState.consecutiveFailureCount > 0
            ? Self.retryBackgroundPollingInterval
            : Self.normalBackgroundPollingInterval
    }

    private func performBackgroundPollingCycle() async {
        guard shouldRunBackgroundPolling else {
            return
        }

        do {
            let shouldBadgeOfflinePeriod = pollingUIState.consecutiveFailureCount > 0 || isFloatingHiddenForFullscreen
            let replies = try await messageService.syncIncomingMessages()
            recordPollingSuccess()
            guard !replies.isEmpty else {
                return
            }

            appendAssistantMessages(
                replies,
                countUnread: !isChatWindowActive,
                badge: shouldBadgeOfflinePeriod ? .offlinePeriod : nil
            )
            let latestSnapshot = oauthService.loadSnapshot()
            applySnapshot(latestSnapshot)
            recoveryIssue = nil
            chatStatusMessage = UserFacingCopy.Chat.backgroundReceived(
                count: replies.count,
                hasOfflineBadge: shouldBadgeOfflinePeriod
            )
        } catch {
            recordPollingFailure()
            let latestSnapshot = oauthService.loadSnapshot()
            applySnapshot(latestSnapshot)
            recoveryIssue = Self.recoveryIssue(for: error)
            if case FeishuOAuthError.missingRefreshToken = error {
                configurationStatusMessage = error.localizedDescription
                chatStatusMessage = error.localizedDescription
            } else if case FeishuOAuthError.reauthorizationRequired = error {
                configurationStatusMessage = error.localizedDescription
                chatStatusMessage = error.localizedDescription
            } else if recoveryState.blocksSending {
                chatStatusMessage = recoveryState.detail
            }
        }
    }

    func recordPollingSuccess(at date: Date = Date()) {
        pollingUIState.latestSyncAt = date
        pollingUIState.consecutiveFailureCount = 0
        pollingUIState.nextRetryAt = nil
        if recoveryIssue?.kind == .agentOffline || recoveryIssue?.kind == .invalidChat {
            recoveryIssue = nil
        }
        if shouldRunBackgroundPolling {
            pollingUIState.status = .listening
        }
    }

    func recordPollingFailure(at date: Date = Date()) {
        pollingUIState.consecutiveFailureCount += 1
        pollingUIState.status = .retrying
        pollingUIState.nextRetryAt = date.addingTimeInterval(nextBackgroundPollingInterval)
    }

    private func scheduleMiniChatCollapseIfNeeded() {
        guard isMiniChatExpanded, !isFloatingHovered, !isMiniComposerFocused, !isFloatingPanelDragging, !isExpandedConversationPresented, !isCommandInputPresented else {
            miniCollapseTask?.cancel()
            miniCollapseTask = nil
            return
        }
        guard miniCollapseTask == nil else {
            return
        }
        let delay = miniCollapseDelay
        miniCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else {
                return
            }
            self.miniCollapseTask = nil
            guard !self.isFloatingHovered, !self.isMiniComposerFocused, !self.isFloatingPanelDragging, !self.isExpandedConversationPresented else {
                return
            }
            self.isMiniChatExpanded = false
            self.unreadTurnReadWorkItem?.cancel()
            self.unreadTurnReadWorkItem = nil
            self.isUnreadTurnBrowserActive = false
            self.miniCollapseTask = nil
            self.suppressMiniChatExpansionUntil = Date().addingTimeInterval(0.9)
        }
    }

    private func resolveLightweightSurfaceAfterCommandInputChange() {
        guard !isCommandInputPresented, !isExpandedConversationPresented else {
            return
        }
        if unreadAssistantTurnCount > 0 {
            miniCollapseTask?.cancel()
            miniCollapseTask = nil
            shouldCollapseMiniChatAfterUnreadRead = true
            isMiniChatExpanded = true
            isUnreadTurnBrowserActive = true
            scheduleUnreadTurnReadIfNeeded()
            return
        }
        guard !isFloatingHovered, !isMiniComposerFocused, !isFloatingPanelDragging else {
            scheduleMiniChatCollapseIfNeeded()
            return
        }
        miniCollapseTask?.cancel()
        miniCollapseTask = nil
        unreadTurnReadWorkItem?.cancel()
        unreadTurnReadWorkItem = nil
        isMiniChatExpanded = false
        isUnreadTurnBrowserActive = false
        shouldCollapseMiniChatAfterUnreadRead = false
    }

    private func presentFloatingNotificationIfNeeded(text: String, createdAt: Date = Date()) {
        guard let turn = buildAssistantTurn(from: [], fallbackSummaryText: text, createdAt: createdAt, badge: nil) else {
            return
        }
        presentFloatingNotificationIfNeeded(turn: turn, createdAt: createdAt)
    }

    private func presentFloatingNotificationIfNeeded(turn: AssistantTurn, createdAt: Date = Date()) {
        guard !isChatWindowActive, !isMiniChatExpanded, !isExpandedConversationPresented else {
            return
        }
        guard !shouldSuppressLiveNotification(for: turn) else {
            return
        }
        let presentationID = floatingNotification?.id ?? UUID()
        floatingNotificationWorkItem?.cancel()
        floatingNotification = FloatingNotificationState(id: presentationID, turn: turn, createdAt: createdAt)
        guard !isFloatingHovered else {
            floatingNotificationWorkItem = nil
            return
        }
        scheduleFloatingNotificationDismiss()
    }

    private func scheduleFloatingNotificationDismiss() {
        floatingNotificationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            guard !self.isFloatingHovered else {
                self.floatingNotificationWorkItem = nil
                return
            }
            self.floatingNotification = nil
            self.floatingNotificationWorkItem = nil
        }
        floatingNotificationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + durationTimeInterval(notificationDismissDelay),
            execute: workItem
        )
    }

    private func durationTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        let seconds = TimeInterval(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds + attoseconds
    }

    private var shouldTreatAssistantMessagesAsRead: Bool {
        isChatWindowActive || isExpandedConversationPresented
    }

    private func markAllAssistantTurnsRead() {
        unreadAssistantTurns.removeAll()
        isUnreadTurnBrowserActive = false
        unreadTurnReadWorkItem?.cancel()
        unreadTurnReadWorkItem = nil
        dismissFloatingNotification()
    }

    private func markCurrentAssistantTurnReadIfNeeded() {
        guard !unreadAssistantTurns.isEmpty else {
            return
        }
        advanceUnreadTurn()
    }

    private func scheduleUnreadTurnReadIfNeeded() {
        unreadTurnReadWorkItem?.cancel()
        unreadTurnReadWorkItem = nil
        guard isUnreadTurnBrowserActive, isMiniChatExpanded, !isExpandedConversationPresented, !unreadAssistantTurns.isEmpty else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.unreadTurnReadWorkItem = nil
            guard self.isUnreadTurnBrowserActive, self.isMiniChatExpanded, !self.isExpandedConversationPresented else {
                return
            }
            self.markCurrentAssistantTurnReadIfNeeded()
        }
        unreadTurnReadWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + durationTimeInterval(unreadTurnReadDelay),
            execute: workItem
        )
    }

    private func refreshDisplayedAssistantTurn() {
        displayedAssistantTurn = unreadAssistantTurns.first ?? latestAssistantTurn
    }

    private func shouldSuppressLiveNotification(for turn: AssistantTurn) -> Bool {
        isFloatingHiddenForFullscreen
            || isCommandInputPresented
            || isUnreadTurnBrowserActive
            || turn.badge == .offlinePeriod
    }

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        trimMessagesIfNeeded()
    }

    func appendAssistantMessagesForTesting(
        _ replies: [FeishuReplyMessage],
        chatIsActive: Bool,
        badge: AssistantTurnBadge? = nil
    ) {
        appendAssistantMessages(replies, countUnread: !chatIsActive, badge: badge)
    }

    private func appendAssistantMessages(
        _ replies: [FeishuReplyMessage],
        countUnread: Bool,
        badge: AssistantTurnBadge? = nil
    ) {
        var appendedMessages: [ChatMessage] = []
        var existingMessageIDs = Set(messages.compactMap(\.externalMessageID))
        for reply in replies where !existingMessageIDs.contains(reply.messageID) {
            let message = ChatMessage(
                externalMessageID: reply.messageID,
                sender: .assistant,
                text: reply.text,
                timestamp: reply.createTime,
                deliveryState: .sent
            )
            appendMessage(message)
            existingMessageIDs.insert(reply.messageID)
            appendedMessages.append(message)
        }
        guard let turn = buildAssistantTurn(from: appendedMessages, badge: badge) else {
            return
        }
        latestAssistantTurn = turn
        let shouldCountUnread = countUnread && !shouldTreatAssistantMessagesAsRead
        if shouldCountUnread {
            unreadAssistantTurns.append(turn)
            if unreadAssistantTurns.count > Self.maxUnreadTurnCount {
                unreadAssistantTurns.removeFirst(unreadAssistantTurns.count - Self.maxUnreadTurnCount)
            }
        }
        if shouldCountUnread, isMiniChatExpanded {
            isUnreadTurnBrowserActive = true
            scheduleUnreadTurnReadIfNeeded()
            dismissFloatingNotification()
        } else if shouldCountUnread {
            presentFloatingNotificationIfNeeded(turn: turn, createdAt: turn.latestTimestamp)
        } else {
            dismissFloatingNotification()
        }
    }

    private func trimMessagesIfNeeded() {
        let overflowCount = messages.count - Self.maxLocalMessageCount
        guard overflowCount > 0 else {
            return
        }
        messages.removeFirst(overflowCount)
    }

    private func updateMessage(id: UUID, deliveryState: ChatMessageDeliveryState) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        let message = messages[index]
        messages[index] = ChatMessage(
            id: message.id,
            externalMessageID: message.externalMessageID,
            sender: message.sender,
            text: message.text,
            timestamp: message.timestamp,
            deliveryState: deliveryState
        )
    }

    private static func normalizedRestoredMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.suffix(maxLocalMessageCount).map { message in
            let deliveryState: ChatMessageDeliveryState
            if message.deliveryState.isInFlight {
                deliveryState = .failed(UserFacingCopy.Chat.startupPendingFailure)
            } else {
                deliveryState = message.deliveryState
            }
            return ChatMessage(
                id: message.id,
                externalMessageID: message.externalMessageID,
                sender: message.sender,
                text: message.text,
                timestamp: message.timestamp,
                deliveryState: deliveryState
            )
        }
    }

    private func buildAssistantTurn(
        from messages: [ChatMessage],
        fallbackSummaryText: String? = nil,
        createdAt: Date? = nil,
        badge: AssistantTurnBadge? = nil
    ) -> AssistantTurn? {
        let summaryFragments = messages.compactMap { message -> String? in
            let summary = presentationModel(for: message).summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : summary
        }
        let summaryText = (summaryFragments.isEmpty ? [fallbackSummaryText ?? ""] : summaryFragments)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summaryText.isEmpty else {
            return nil
        }
        let latestTimestamp = messages.last?.timestamp ?? createdAt ?? Date()
        let messageIDs = messages.compactMap(\.externalMessageID)
        return AssistantTurn(
            messageIDs: messageIDs,
            summaryText: summaryText,
            latestTimestamp: latestTimestamp,
            badge: badge
        )
    }

    private static func restoreLatestAssistantTurn(
        from messages: [ChatMessage],
        targetChatID: String?
    ) -> AssistantTurn? {
        let trailingAssistantMessages = messages.reversed().prefix { $0.sender == .assistant }.reversed()
        let fragments = trailingAssistantMessages.compactMap { message -> String? in
            let summary = MessagePresentationParser.parse(
                rawText: message.text,
                targetChatID: targetChatID
            ).summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : summary
        }
        guard !fragments.isEmpty else {
            return nil
        }
        return AssistantTurn(
            messageIDs: trailingAssistantMessages.compactMap(\.externalMessageID),
            summaryText: fragments.joined(separator: "\n"),
            latestTimestamp: trailingAssistantMessages.last?.timestamp ?? Date(),
            badge: nil
        )
    }

    private static func recoveryState(
        for snapshot: FeishuConnectionSnapshot,
        missingItems: [SetupChecklistItem],
        recoveryIssue: RecoveryIssue?
    ) -> RecoveryStateProjection {
        let configurationMissingItems = missingItems.filter { $0.group != .automatic }

        if !configurationMissingItems.isEmpty {
            return RecoveryStateProjection(
                kind: .configurationRequired,
                title: UserFacingCopy.Recovery.configurationRequiredTitle,
                detail: UserFacingCopy.Recovery.configurationRequired(missingTitles: configurationMissingItems.map(\.title)),
                primaryAction: RecoveryActionDescriptor(
                    kind: .openSettings,
                    title: UserFacingCopy.Recovery.openSettingsAction
                ),
                secondaryAction: nil,
                blocksSending: true
            )
        }

        if let recoveryIssue {
            switch recoveryIssue.kind {
            case .configurationRequired:
                return RecoveryStateProjection(
                    kind: .configurationRequired,
                    title: UserFacingCopy.Recovery.configurationRequiredTitle,
                    detail: recoveryIssue.message,
                    primaryAction: RecoveryActionDescriptor(
                        kind: .openSettings,
                        title: UserFacingCopy.Recovery.openSettingsAction
                    ),
                    secondaryAction: nil,
                    blocksSending: true
                )
            case .authorizationRequired:
                return RecoveryStateProjection(
                    kind: .authorizationRequired,
                    title: UserFacingCopy.Recovery.authorizationRequiredTitle,
                    detail: recoveryIssue.message,
                    primaryAction: RecoveryActionDescriptor(
                        kind: .startAuthorization,
                        title: UserFacingCopy.Recovery.startAuthorizationAction
                    ),
                    secondaryAction: RecoveryActionDescriptor(
                        kind: .openSettings,
                        title: UserFacingCopy.Recovery.openSettingsAction
                    ),
                    blocksSending: true
                )
            case .authorizationExpired:
                return RecoveryStateProjection(
                    kind: .authorizationExpired,
                    title: UserFacingCopy.Recovery.authorizationExpiredTitle,
                    detail: recoveryIssue.message,
                    primaryAction: RecoveryActionDescriptor(
                        kind: .reauthorize,
                        title: UserFacingCopy.Recovery.reauthorizeAction
                    ),
                    secondaryAction: RecoveryActionDescriptor(
                        kind: .openSettings,
                        title: UserFacingCopy.Recovery.openSettingsAction
                    ),
                    blocksSending: true
                )
            case .agentOffline:
                return RecoveryStateProjection(
                    kind: .agentOffline,
                    title: UserFacingCopy.Recovery.agentOfflineTitle,
                    detail: recoveryIssue.message,
                    primaryAction: RecoveryActionDescriptor(
                        kind: .reconnect,
                        title: UserFacingCopy.Recovery.reconnectAction
                    ),
                    secondaryAction: RecoveryActionDescriptor(
                        kind: .openSettings,
                        title: UserFacingCopy.Recovery.openSettingsAction
                    ),
                    blocksSending: true
                )
            case .invalidChat:
                return RecoveryStateProjection(
                    kind: .invalidChat,
                    title: UserFacingCopy.Recovery.invalidChatTitle,
                    detail: recoveryIssue.message,
                    primaryAction: RecoveryActionDescriptor(
                        kind: .openSettings,
                        title: UserFacingCopy.Recovery.openSettingsAction
                    ),
                    secondaryAction: nil,
                    blocksSending: true
                )
            case .ready:
                break
            }
        }

        if snapshot.hasValidUserAccessToken || snapshot.hasRefreshToken {
            return RecoveryStateProjection(
                kind: .ready,
                title: UserFacingCopy.Recovery.readyTitle,
                detail: snapshot.hasValidUserAccessToken
                    ? UserFacingCopy.Configuration.authorized
                    : UserFacingCopy.Recovery.authorizationRefreshableDetail,
                primaryAction: nil,
                secondaryAction: nil,
                blocksSending: false
            )
        }

        return RecoveryStateProjection(
            kind: snapshot.hasUserAccessToken ? .authorizationExpired : .authorizationRequired,
            title: snapshot.hasUserAccessToken
                ? UserFacingCopy.Recovery.authorizationExpiredTitle
                : UserFacingCopy.Recovery.authorizationRequiredTitle,
            detail: snapshot.hasUserAccessToken
                ? UserFacingCopy.Recovery.authorizationExpired(UserFacingCopy.Configuration.expiredNeedsAuthorization)
                : UserFacingCopy.Recovery.authorizationRequiredDetail,
            primaryAction: RecoveryActionDescriptor(
                kind: snapshot.hasUserAccessToken ? .reauthorize : .startAuthorization,
                title: snapshot.hasUserAccessToken
                    ? UserFacingCopy.Recovery.reauthorizeAction
                    : UserFacingCopy.Recovery.startAuthorizationAction
            ),
            secondaryAction: RecoveryActionDescriptor(
                kind: .openSettings,
                title: UserFacingCopy.Recovery.openSettingsAction
            ),
            blocksSending: true
        )
    }

    private static func recoveryIssue(for error: Error) -> RecoveryIssue? {
        switch error {
        case FeishuOAuthError.missingRefreshToken:
            return RecoveryIssue(
                kind: .authorizationExpired,
                message: UserFacingCopy.Recovery.authorizationExpired(error.localizedDescription)
            )
        case FeishuOAuthError.reauthorizationRequired(let message):
            return RecoveryIssue(
                kind: .authorizationExpired,
                message: UserFacingCopy.Recovery.authorizationExpired(message)
            )
        case FeishuMessageError.missingConfiguration:
            return RecoveryIssue(
                kind: .configurationRequired,
                message: error.localizedDescription
            )
        case FeishuMessageError.missingUserAccessToken:
            return RecoveryIssue(
                kind: .authorizationRequired,
                message: UserFacingCopy.Recovery.authorizationRequiredDetail
            )
        case FeishuMessageError.apiError(_, let message):
            if isInvalidChatMessage(message) {
                return RecoveryIssue(kind: .invalidChat, message: UserFacingCopy.Recovery.invalidChat(message))
            }
            return RecoveryIssue(kind: .agentOffline, message: UserFacingCopy.Recovery.agentOffline(message))
        default:
            let message = error.localizedDescription
            if isInvalidChatMessage(message) {
                return RecoveryIssue(kind: .invalidChat, message: UserFacingCopy.Recovery.invalidChat(message))
            }
            if isAuthorizationMessage(message) {
                return RecoveryIssue(kind: .authorizationExpired, message: UserFacingCopy.Recovery.authorizationExpired(message))
            }
            return RecoveryIssue(kind: .agentOffline, message: UserFacingCopy.Recovery.agentOffline(message))
        }
    }

    private static func isInvalidChatMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("chat_id")
            || normalized.contains("chat id")
            || normalized.contains("receive_id")
            || normalized.contains("chat not found")
            || normalized.contains("conversation")
            || normalized.contains("会话")
    }

    private static func isAuthorizationMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("refresh_token")
            || normalized.contains("access_token")
            || normalized.contains("重新授权")
            || normalized.contains("登录态")
            || normalized.contains("token")
    }
}
