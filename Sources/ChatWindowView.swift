import AppKit
import SwiftUI

struct ChatWindowView: View {
    @EnvironmentObject private var appState: AppStateModel
    @State private var draftMessage = ""
    private let onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void = {}) {
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            messageList

            Divider()

            taskStatusStrip

            composer
        }
        .frame(minWidth: 320, minHeight: 520)
        .onAppear {
            appState.chatWindowDidBecomeActive()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            miniOrb

            Spacer()

            Button(action: onOpenSettings) {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .font(ONEsaStyle.Typography.body)
            .help("打开飞书应用配置和 OAuth 授权设置")

            if !appState.messages.isEmpty {
                Button {
                    appState.clearConversationHistory()
                } label: {
                    Label("清空会话", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .font(ONEsaStyle.Typography.body)
                .help(UserFacingCopy.Chat.clearHistoryTooltip)
            }
        }
        .padding(10)
        .onesaSurface(cornerRadius: ONEsaStyle.CornerRadius.card)
        .padding(10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if appState.messages.isEmpty {
                        EmptyHistoryView(recoveryState: appState.recoveryState)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 64)
                    } else {
                        ForEach(appState.messages) { message in
                            MessageBubbleView(
                                message: message,
                                presentation: appState.presentationModel(for: message),
                                onRetry: {
                                    appState.retryMessage(id: message.id)
                                }
                            )
                                .id(message.id)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .onAppear {
                guard let latestMessage = appState.messages.last else { return }
                proxy.scrollTo(latestMessage.id, anchor: .bottom)
            }
            .onChange(of: appState.messages) { _, messages in
                guard let latestMessage = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(latestMessage.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var taskStatusStrip: some View {
        if let foregroundTask = appState.foregroundTaskUIState {
            TimelineView(.periodic(from: foregroundTask.startedAt, by: 1)) { context in
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(foregroundTask.title)
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text(taskStatusDetail(for: foregroundTask, now: context.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if foregroundTask.phase == .waiting {
                        Button("停止等待") {
                            appState.stopCurrentForegroundWait()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.blue.opacity(0.08))
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let blockingMessage = appState.chatSendReadiness.blockingMessage {
                recoveryBanner(
                    title: appState.recoveryState.title,
                    detail: blockingMessage,
                    primaryAction: appState.chatSendReadiness.primaryAction,
                    secondaryAction: appState.chatSendReadiness.secondaryAction
                )
            }

            HStack(alignment: .bottom, spacing: 10) {
                MultilineMessageInput(
                    text: $draftMessage,
                    placeholder: "one sentence anytime",
                    onSend: sendDraftMessage
                )
                .frame(minHeight: 34, maxHeight: 76)

                Button(action: sendDraftMessage) {
                    Label("发送", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .font(ONEsaStyle.Typography.body)
                .disabled(
                    draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || appState.isSendingMessage
                        || !appState.chatSendReadiness.canAttemptSend
                )
            }
        }
        .padding(10)
        .onesaSurface(cornerRadius: ONEsaStyle.CornerRadius.card)
        .padding(10)
    }

    private var miniOrb: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: orbGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.20), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 4)
            .frame(width: 18, height: 18)
    }

    private var orbGradientColors: [Color] {
        switch appState.floatingPrimaryVisualState {
        case .idle:
            return appState.hasUnreadTurnOverlay ? [.purple, .pink] : [.gray, .secondary]
        case .listening:
            return [.cyan, .blue]
        case .thinking:
            return [.indigo, .blue]
        case .outputting:
            return appState.hasUnreadTurnOverlay ? [.purple, .pink] : [.mint, .green]
        case .disconnected:
            return [.orange, .red]
        }
    }

    private func taskStatusDetail(for task: ForegroundTaskUIState, now: Date) -> String {
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(task.startedAt)))
        let elapsedText = "\(elapsedSeconds)s"
        switch task.phase {
        case .sending:
            return "已等待 \(elapsedText)，正在通过飞书发送。"
        case .waiting:
            if elapsedSeconds >= 30 {
                return "已等待 \(elapsedText)，任务可能仍在运行；收起窗口后后台会继续监听。"
            }
            return "已等待 \(elapsedText)，正在轮询 AI 回复。"
        case .timedOut:
            return "后台仍会继续监听该会话中的新消息。"
        }
    }

    private func sendDraftMessage() {
        let message = draftMessage
        let didSend = appState.sendMessage(message)
        if didSend {
            draftMessage = ""
        }
    }

    private func recoveryBanner(
        title: String,
        detail: String,
        primaryAction: RecoveryActionDescriptor?,
        secondaryAction: RecoveryActionDescriptor?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                if let primaryAction {
                    Button(primaryAction.title) {
                        performRecoveryAction(primaryAction)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                if let secondaryAction {
                    Button(secondaryAction.title) {
                        performRecoveryAction(secondaryAction)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }

    private func performRecoveryAction(_ action: RecoveryActionDescriptor) {
        switch action.kind {
        case .openSettings:
            onOpenSettings()
        default:
            appState.performRecoveryAction(action.kind)
        }
    }
}

private struct EmptyHistoryView: View {
    let recoveryState: RecoveryStateProjection

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(24)
    }

    private var iconName: String {
        switch recoveryState.kind {
        case .configurationRequired:
            "gearshape"
        case .keychainAccessRequired:
            "key.fill"
        case .authorizationRequired, .authorizationExpired:
            "person.crop.circle.badge.exclamationmark"
        case .ready:
            "bubble.left.and.bubble.right"
        case .agentOffline, .invalidChat:
            "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch recoveryState.kind {
        case .configurationRequired:
            "尚未完成配置"
        case .keychainAccessRequired:
            recoveryState.title
        case .authorizationRequired, .authorizationExpired:
            recoveryState.title
        case .ready:
            "暂无本地会话历史"
        case .agentOffline, .invalidChat:
            recoveryState.title
        }
    }

    private var detail: String {
        switch recoveryState.kind {
        case .configurationRequired, .keychainAccessRequired, .authorizationRequired, .authorizationExpired, .agentOffline, .invalidChat:
            recoveryState.detail
        case .ready:
            UserFacingCopy.Chat.emptyHistoryConfigured
        }
    }

    private var tint: Color {
        switch recoveryState.kind {
        case .configurationRequired:
            .orange
        case .keychainAccessRequired:
            .yellow
        case .authorizationRequired, .authorizationExpired:
            .yellow
        case .ready:
            .blue
        case .agentOffline, .invalidChat:
            .red
        }
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessage
    let presentation: MessagePresentationModel
    let onRetry: () -> Void

    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer(minLength: 48)
            } else if message.sender == .system {
                Spacer(minLength: 24)
            }

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(message.sender.displayName)
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(message.deliveryState.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                MessagePresentationView(
                    presentation: presentation,
                    baseFont: message.sender == .system ? .caption : .body,
                    foregroundColor: foregroundStyle,
                    secondaryColor: secondaryStyle,
                    linkColor: linkStyle
                )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(
                        color: message.sender == .user ? .clear : ONEsaStyle.Shadow.primary,
                        radius: message.sender == .user ? 0 : ONEsaStyle.Shadow.primaryRadius,
                        x: 0,
                        y: message.sender == .user ? 0 : ONEsaStyle.Shadow.primaryY
                    )
                    .shadow(
                        color: message.sender == .user ? .clear : ONEsaStyle.Shadow.contact,
                        radius: message.sender == .user ? 0 : ONEsaStyle.Shadow.contactRadius,
                        x: 0,
                        y: message.sender == .user ? 0 : ONEsaStyle.Shadow.contactY
                    )
                    .contextMenu {
                        Button("复制消息") {
                            copyMessageToPasteboard()
                        }
                    }

                if canRetry {
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                if let failureMessage {
                    Text(failureMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(message.sender == .user ? .trailing : .leading)
                }
            }

            if message.sender != .user {
                Spacer(minLength: message.sender == .system ? 24 : 48)
            }
        }
    }

    private var foregroundStyle: Color {
        message.sender == .user ? .white : .primary
    }

    private var secondaryStyle: Color {
        message.sender == .user ? .white.opacity(0.78) : .secondary
    }

    private var linkStyle: Color {
        message.sender == .user ? .white : .accentColor
    }

    private var backgroundStyle: AnyShapeStyle {
        switch message.sender {
        case .user:
            AnyShapeStyle(Color.blue.gradient)
        case .assistant:
            AnyShapeStyle(Color(nsColor: .controlBackgroundColor).gradient)
        case .system:
            AnyShapeStyle(Color.secondary.opacity(0.10).gradient)
        }
    }

    private var canRetry: Bool {
        guard message.sender == .user else {
            return false
        }
        if case .failed = message.deliveryState {
            return true
        }
        return false
    }

    private var failureMessage: String? {
        if case .failed(let message) = message.deliveryState {
            return message
        }
        return nil
    }

    private func copyMessageToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(presentation.summaryText.isEmpty ? message.text : presentation.summaryText, forType: .string)
    }
}

struct MultilineMessageInput: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSend: () -> Void
    let onEscape: () -> Void
    let onFocusChange: (Bool) -> Void
    let usesGlassStyle: Bool
    let autoFocus: Bool

    init(
        text: Binding<String>,
        placeholder: String,
        onSend: @escaping () -> Void,
        onEscape: @escaping () -> Void = {},
        onFocusChange: @escaping (Bool) -> Void = { _ in },
        usesGlassStyle: Bool = false,
        autoFocus: Bool = false
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSend = onSend
        self.onEscape = onEscape
        self.onFocusChange = onFocusChange
        self.usesGlassStyle = usesGlassStyle
        self.autoFocus = autoFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = !usesGlassStyle
        scrollView.borderType = usesGlassStyle ? .noBorder : .bezelBorder
        scrollView.backgroundColor = usesGlassStyle ? .clear : .textBackgroundColor
        scrollView.drawsBackground = !usesGlassStyle

        let textView = MessageInputTextView()
        textView.delegate = context.coordinator
        textView.onSend = onSend
        textView.onEscape = onEscape
        textView.onFocusChange = onFocusChange
        textView.placeholder = placeholder
        textView.font = usesGlassStyle ? .systemFont(ofSize: 14, weight: .regular) : .preferredFont(forTextStyle: .body)
        textView.textColor = usesGlassStyle ? .labelColor : .textColor
        textView.insertionPointColor = usesGlassStyle ? .labelColor : .textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.placeholderColor = usesGlassStyle
            ? .secondaryLabelColor
            : .placeholderTextColor

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }
        textView.onSend = onSend
        textView.onEscape = onEscape
        textView.onFocusChange = onFocusChange
        if autoFocus, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        guard textView.string != text else {
            return
        }
        guard !textView.hasMarkedText() else {
            return
        }
        textView.string = text
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        fileprivate weak var textView: MessageInputTextView?

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            guard !textView.hasMarkedText() else {
                return
            }
            text = textView.string
        }
    }
}

enum MessageInputKeyDecision: Equatable {
    case send
    case escape
    case passThrough
}

enum MessageInputKeyHandling {
    static func decision(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        hasMarkedText: Bool
    ) -> MessageInputKeyDecision {
        let isReturn = keyCode == 36 || keyCode == 76
        let wantsNewLine = modifierFlags.contains(.shift)
        if keyCode == 53 && !hasMarkedText {
            return .escape
        }
        if isReturn && !wantsNewLine && !hasMarkedText {
            return .send
        }
        return .passThrough
    }
}

private final class MessageInputTextView: NSTextView {
    var onSend: () -> Void = {}
    var onEscape: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var placeholder = ""
    var placeholderColor: NSColor = .placeholderTextColor

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange(false)
        }
        return didResignFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        let decision = MessageInputKeyHandling.decision(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            hasMarkedText: hasMarkedText()
        )
        if decision == .send {
            onSend()
            return
        }
        if decision == .escape {
            onEscape()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else {
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: placeholderColor,
            .font: font ?? NSFont.preferredFont(forTextStyle: .body)
        ]
        placeholder.draw(
            at: NSPoint(x: textContainerInset.width + 4, y: textContainerInset.height),
            withAttributes: attributes
        )
    }
}
