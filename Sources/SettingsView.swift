import SwiftUI

private struct SaveFeedback: Equatable {
    let message: String
    let isSuccess: Bool
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppStateModel
    @State private var appID = ""
    @State private var appSecret = ""
    @State private var redirectURI = ""
    @State private var targetChatID = ""
    @State private var openClawSenderID = ""
    @State private var openClawSenderType = ""
    @State private var scopes = ""
    @State private var manualAuthorizationCode = ""
    @State private var showsManualAuthorizationForm = false
    @State private var saveFeedback: SaveFeedback?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                missingItemsCard
                basicConfigurationCard
                advancedConfigurationCard
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 680)
        .onAppear(perform: loadDraft)
    }

    private var projection: ConfigurationStatusProjection {
        appState.configurationStatusProjection
    }

    private var primaryAuthorizationActionTitle: String {
        appState.hasAnySavedAuthorization ? "重新授权" : "开始授权"
    }

    private func loadDraft() {
        let configuration = appState.feishuConfiguration
        appID = configuration.appID
        redirectURI = configuration.redirectURI
        targetChatID = configuration.targetChatID
        openClawSenderID = configuration.openClawSenderID
        openClawSenderType = configuration.openClawSenderType
        scopes = configuration.scopes
    }

    private var statusCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(projection.title)
                            .font(.title3.weight(.semibold))

                        Text(projection.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        statusBadge(
                            text: appState.connectionState.title,
                            tint: connectionTint
                        )
                        statusBadge(
                            text: "\(projection.missingCount) 项待补齐",
                            tint: projection.missingItems.isEmpty ? .green : .orange
                        )
                    }
                }

                HStack(spacing: 12) {
                    settingsInfoPill(
                        title: "Token 状态",
                        value: appState.tokenStatusText
                    )
                    settingsInfoPill(
                        title: "监听状态",
                        value: appState.pollingUIState.title
                    )
                    settingsInfoPill(
                        title: "默认快捷键",
                        value: FloatingShortcutConfiguration.displayName
                    )
                }

                recoveryActionBar(
                    primaryAction: projection.primaryAction,
                    secondaryAction: projection.secondaryAction
                )
            }
        }
    }

    private var missingItemsCard: some View {
        settingsCard(title: "缺失项折叠区", subtitle: "统一展示待补齐项、推荐项和自动获取项。") {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    checklistGroup(title: "必填项", items: projection.requiredItems)
                    checklistGroup(title: "推荐项", items: projection.recommendedItems)
                    checklistGroup(title: "自动获取项", items: projection.automaticItems)
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Label(
                        projection.missingItems.isEmpty ? "当前没有阻断项" : "当前仍有 \(projection.missingItems.count) 项待补齐",
                        systemImage: projection.missingItems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(projection.missingItems.isEmpty ? .green : .orange)

                    Spacer()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if projection.missingItems.isEmpty {
                                checklistChip(for: SetupChecklistItem(
                                    id: "ready",
                                    title: "可直接授权或发送",
                                    detail: "",
                                    group: .required,
                                    isMissing: false,
                                    isBlocking: false
                                ))
                            } else {
                                ForEach(projection.missingItems) { item in
                                    checklistChip(for: item)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 280)
                }
            }
            .accentColor(.primary)
        }
    }

    private var basicConfigurationCard: some View {
        settingsCard(title: "基础配置区", subtitle: "先完成飞书应用接入、目标会话和 OAuth 授权。") {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    TextField("App ID", text: $appID)
                        .textContentType(.username)

                    SecureField(appState.hasSavedAppSecret ? "App Secret 已保存，留空则不变" : "App Secret", text: $appSecret)

                    TextField("Loopback Redirect URI", text: $redirectURI)
                        .textContentType(.URL)

                    TextField("目标 chat_id", text: $targetChatID)
                }

                Text("仅支持 http://127.0.0.1:<port>/<path>，例如 http://127.0.0.1:8787/oauth/callback；不支持 localhost 或其他 host。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("保存基础配置") {
                        saveConfiguration()
                    }

                    Spacer()

                    Button(primaryAuthorizationActionTitle) {
                        appState.authorizeWithFeishu()
                    }
                    .disabled(!appState.feishuSnapshot.isConfigured || appState.isAuthorizing)

                    if appState.isAuthorizing {
                        Button("取消授权等待") {
                            appState.cancelAuthorization()
                        }
                    }
                }

                Text("授权会打开系统浏览器，本地只监听配置的 127.0.0.1 loopback 回调并用 code 换取 user_access_token。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                saveFeedbackView
            }
        }
    }

    private var advancedConfigurationCard: some View {
        settingsCard(title: "高级配置区", subtitle: "配置 sender 过滤、scope 与手动授权回退。") {
            VStack(alignment: .leading, spacing: 16) {
                TextField("OpenClaw sender id", text: $openClawSenderID)
                TextField("OpenClaw sender type（例如 app）", text: $openClawSenderType)
                TextField("OAuth Scope（空格分隔）", text: $scopes, axis: .vertical)
                    .lineLimit(1...3)

                Text("发送者过滤用于轮询回复时只接受 OpenClaw 的消息；可先用 Python PoC 输出的 sender 字段填入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(showsManualAuthorizationForm ? "收起手动输入授权码" : "手动输入授权码") {
                    showsManualAuthorizationForm.toggle()
                }

                if showsManualAuthorizationForm {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("粘贴浏览器返回的 code 或完整回调地址", text: $manualAuthorizationCode, axis: .vertical)
                            .lineLimit(2...4)

                        HStack {
                            Button("提交授权码") {
                                let submittedCode = manualAuthorizationCode
                                appState.submitManualAuthorizationCode(submittedCode)
                                manualAuthorizationCode = ""
                            }
                            .disabled(!appState.canUseManualAuthorizationCodeFallback || appState.isAuthorizing)

                            if !appState.canUseManualAuthorizationCodeFallback {
                                Text("请先点击“开始授权”，生成当前授权会话后再粘贴 code。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("当浏览器未能自动跳回本地回调，或自动回调超时/失败时，可从浏览器地址栏或页面结果中复制 code，在此手动换取 token，无需重启应用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("保存全部配置") {
                        saveConfiguration()
                    }

                    Spacer()

                    Button("清除本地授权") {
                        appState.clearFeishuAuthorization()
                    }
                    .disabled(!appState.hasAnySavedAuthorization || appState.isAuthorizing)

                    if appState.isAuthorizing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                saveFeedbackView
            }
        }
    }

    private func saveConfiguration() {
        let didSave = appState.saveFeishuConfiguration(
            appID: appID,
            appSecret: appSecret,
            redirectURI: redirectURI,
            targetChatID: targetChatID,
            openClawSenderID: openClawSenderID,
            openClawSenderType: openClawSenderType,
            scopes: scopes
        )
        appSecret = ""
        saveFeedback = SaveFeedback(
            message: appState.configurationStatusMessage,
            isSuccess: didSave
        )
    }

    private var connectionTint: Color {
        switch appState.connectionState {
        case .connected:
            .green
        case .notLoggedIn:
            .yellow
        case .notConfigured:
            .orange
        case .error:
            .red
        }
    }

    private func settingsCard<Content: View>(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func statusBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func settingsInfoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var saveFeedbackView: some View {
        if let saveFeedback {
            Label(
                saveFeedback.message,
                systemImage: saveFeedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(saveFeedback.isSuccess ? .green : .red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (saveFeedback.isSuccess ? Color.green : Color.red).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func recoveryActionBar(
        primaryAction: RecoveryActionDescriptor?,
        secondaryAction: RecoveryActionDescriptor?
    ) -> some View {
        let supportedPrimaryAction = supportedSettingsAction(primaryAction)
        let supportedSecondaryAction = supportedSettingsAction(secondaryAction)
        if supportedPrimaryAction != nil || supportedSecondaryAction != nil {
            HStack(spacing: 10) {
                if let supportedPrimaryAction {
                    Button(supportedPrimaryAction.title) {
                        appState.performRecoveryAction(supportedPrimaryAction.kind)
                    }
                }

                if let supportedSecondaryAction {
                    Button(supportedSecondaryAction.title) {
                        appState.performRecoveryAction(supportedSecondaryAction.kind)
                    }
                }
            }
        }
    }

    private func supportedSettingsAction(_ action: RecoveryActionDescriptor?) -> RecoveryActionDescriptor? {
        guard let action else {
            return nil
        }
        return action.kind == .openSettings ? nil : action
    }

    @ViewBuilder
    private func checklistGroup(title: String, items: [SetupChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.isMissing ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(item.isMissing ? (item.isBlocking ? .red : .orange) : .green)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body.weight(.medium))

                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(item.isMissing ? "缺失" : "已就绪")
                        .font(.caption2)
                        .foregroundStyle(item.isMissing ? (item.isBlocking ? .red : .orange) : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (item.isMissing ? (item.isBlocking ? Color.red : Color.orange) : Color.green)
                                .opacity(0.12),
                            in: Capsule()
                        )
                }
            }
        }
    }

    private func checklistChip(for item: SetupChecklistItem) -> some View {
        Text(item.title)
            .font(.caption)
            .foregroundStyle(item.isBlocking ? .red : .orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (item.isBlocking ? Color.red : Color.orange).opacity(0.12),
                in: Capsule()
            )
    }
}
