import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingWindowController: FloatingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = FloatingWindowController(appState: AppStateModel.shared)
        floatingWindowController = controller
        controller.showFloatingBubble()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        floatingWindowController?.showOrFocusChatWindow()
        return false
    }
}

@MainActor
final class FloatingWindowController: NSObject {
    private enum BubbleDefaults {
        static let anchorY = "openclaw.floatingBubble.anchorY"
        static let edge = "openclaw.floatingBubble.edge"
        static let displayID = "openclaw.floatingBubble.displayID"
        static let edgeInset: CGFloat = 8
    }

    private enum CommandInputDefaults {
        static let originX = "openclaw.commandInput.originX"
        static let originY = "openclaw.commandInput.originY"
        static let displayID = "openclaw.commandInput.displayID"
    }

    private let appState: AppStateModel
    private var cancellables = Set<AnyCancellable>()
    private var floatingEdge: FloatingPanelEdge = .trailing
    private var anchorCenterY: CGFloat?
    private var dragStartFrame: NSRect?
    private var hoverMonitorTimer: Timer?
    private lazy var bubblePanel = makeBubblePanel()
    private var chatPanel: NSPanel?
    private var settingsPanel: NSPanel?
    private var commandInputPanel: NSPanel?
    private var localKeyMonitor: Any?
    private var shortcutMonitor: FloatingShortcutMonitor?

    init(appState: AppStateModel) {
        self.appState = appState
        super.init()
        bindAppState()
        installFullscreenObservers()
        installInteractionMonitors()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func showFloatingBubble() {
        updateFloatingPanelLayout(animated: false)
        updateFloatingVisibilityForFullscreen()
    }

    func showOrFocusChatWindow() {
        let panel = chatPanel ?? makeChatPanel()
        chatPanel = panel

        if !panel.isVisible {
            placeChatPanelNearBubble(panel)
        }

        appState.setExpandedConversationPresented(true)
        bubblePanel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.chatWindowDidBecomeActive()
    }

    func toggleChatWindow() {
        guard let panel = chatPanel, panel.isVisible, panel.isKeyWindow || NSApp.isActive else {
            showOrFocusChatWindow()
            return
        }
        closeChatWindow(panel)
    }

    func showOrFocusSettingsWindow() {
        let panel = settingsPanel ?? makeSettingsPanel()
        settingsPanel = panel

        if !panel.isVisible {
            placeChatPanelNearBubble(panel)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeBubblePanel() -> NSPanel {
        let visibleFrame = restoredBubbleScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        restoreFloatingPlacement(from: visibleFrame)

        let panel = FloatingInteractionPanel(
            contentRect: NSRect(origin: initialFloatingOrigin(in: visibleFrame), size: collapsedPanelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        installBubbleContent(in: panel)

        return panel
    }

    private func makeChatPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "OpenClaw"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: ChatWindowView { [weak self] in
                self?.showOrFocusSettingsWindow()
            }
                .environmentObject(appState)
        )

        return panel
    }

    private func makeSettingsPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "OpenClaw 设置"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(appState)
        )

        return panel
    }

    private func makeCommandInputPanel() -> NSPanel {
        let panel = FloatingInteractionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 86),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: CommandInputPanelView(
                onOpenSettings: { [weak self] in
                    self?.showOrFocusSettingsWindow()
                },
                onDismiss: { [weak self] in
                    self?.appState.dismissCommandInput(preserveDraft: true)
                }
            )
            .environmentObject(appState)
        )
        return panel
    }

    private func installBubbleContent(in panel: NSPanel) {
        let bubbleView = FloatingCompactPanelView(
            side: floatingEdge,
            onOpenConversation: { [weak self] in
                self?.showOrFocusChatWindow()
            },
            onOpenSettings: { [weak self] in
                self?.showOrFocusSettingsWindow()
            },
            onDragStart: { [weak self] in
                self?.beginFloatingPanelDrag()
            },
            onDragChange: { [weak self] startPoint, currentPoint in
                self?.updateFloatingPanelDrag(from: startPoint, to: currentPoint)
            },
            onDragEnd: { [weak self] in
                self?.endFloatingPanelDrag()
            },
            onDoubleTap: { [weak self] in
                self?.performInteractionCommand(.doubleClickCommand)
            },
            onSecondaryTap: { [weak self] event in
                self?.showContextMenu(with: event)
            }
        )
        .environmentObject(appState)

        let hostingView = NSHostingView(rootView: bubbleView)
        hostingView.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = hostingView
    }

    private func placeChatPanelNearBubble(_ panel: NSPanel) {
        let visibleFrame = bubblePanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let panelSize = panel.frame.size
        let anchorY = resolvedAnchorCenterY(in: visibleFrame)

        var origin = NSPoint(x: 0, y: anchorY - panelSize.height / 2)
        origin.x = floatingEdge == .leading
            ? visibleFrame.minX + FloatingPanelMetrics.chatGap
            : visibleFrame.maxX - panelSize.width - FloatingPanelMetrics.chatGap

        origin.x = min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - panelSize.width - 12)
        origin.y = min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - panelSize.height - 12)

        panel.setFrameOrigin(origin)
    }

    private func bindAppState() {
        appState.$isMiniChatExpanded
            .sink { [weak self] _ in
                self?.updateFloatingPanelLayout()
                self?.refreshHoverMonitor()
            }
            .store(in: &cancellables)
        appState.$floatingNotification
            .sink { [weak self] _ in
                self?.updateFloatingPanelLayout()
            }
            .store(in: &cancellables)
        appState.$displayedAssistantTurn
            .sink { [weak self] _ in
                self?.updateFloatingPanelLayout()
            }
            .store(in: &cancellables)
        appState.$isExpandedConversationPresented
            .sink { [weak self] _ in
                self?.updateFloatingPanelLayout()
                self?.refreshHoverMonitor()
            }
            .store(in: &cancellables)
        appState.$messages
            .sink { [weak self] _ in
                self?.updateFloatingPanelLayout()
            }
            .store(in: &cancellables)
        appState.$feishuSnapshot
            .sink { [weak self] _ in
                self?.updateFloatingPanelLayout()
            }
            .store(in: &cancellables)
        appState.$recoveryIssue
            .sink { [weak self] _ in
                self?.updateFloatingPanelLayout()
            }
            .store(in: &cancellables)
        appState.$isFloatingHiddenForFullscreen
            .sink { [weak self] _ in
                self?.updateFloatingVisibilityForFullscreen()
            }
            .store(in: &cancellables)
        appState.$isCommandInputPresented
            .sink { [weak self] _ in
                self?.syncCommandInputPanel()
            }
            .store(in: &cancellables)
    }

    private var interactionSnapshot: FloatingInteractionSnapshot {
        FloatingInteractionSnapshot(
            isMiniChatExpanded: appState.isMiniChatExpanded,
            isCommandInputPresented: appState.isCommandInputPresented,
            hasUnreadTurns: appState.unreadAssistantTurnCount > 0,
            isUnreadBrowserActive: appState.isUnreadTurnBrowserActive,
            isConversationVisible: chatPanel?.isVisible == true,
            isSettingsVisible: settingsPanel?.isVisible == true
        )
    }

    private func installInteractionMonitors() {
        shortcutMonitor = FloatingShortcutMonitor(
            keyCode: FloatingShortcutConfiguration.keyCode,
            modifiers: FloatingShortcutConfiguration.modifiers
        ) { [weak self] in
            self?.performInteractionCommand(.revealCommand)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            guard event.keyCode == UInt16(kVK_Escape) else {
                return event
            }
            guard FloatingInteractionPolicy.escapeCommand(for: self.interactionSnapshot) != nil else {
                return event
            }
            self.performInteractionCommand(.dismissCommand)
            return nil
        }
    }

    private func performInteractionCommand(_ source: InteractionCommandSource) {
        let resolvedCommand: FloatingInteractionCommand
        switch source {
        case .revealCommand:
            resolvedCommand = FloatingInteractionPolicy.revealCommand(for: interactionSnapshot)
        case .doubleClickCommand:
            resolvedCommand = FloatingInteractionPolicy.doubleClickCommand(for: interactionSnapshot)
        case .dismissCommand:
            guard let dismissCommand = FloatingInteractionPolicy.escapeCommand(for: interactionSnapshot) else {
                return
            }
            resolvedCommand = dismissCommand
        case .contextMenu(let action):
            resolvedCommand = contextMenuCommand(for: action)
        }
        executeInteractionCommand(resolvedCommand)
    }

    private func executeInteractionCommand(_ command: FloatingInteractionCommand) {
        switch command {
        case .revealCommandInput:
            revealCommandInput()
        case .revealUnreadBrowser:
            revealUnreadBrowser()
        case .focusConversation:
            showOrFocusChatWindow()
        case .focusSettings:
            showOrFocusSettingsWindow()
        case .dismissLightweightEntry:
            appState.dismissMiniChatForExplicitUserAction()
            bubblePanel.orderFrontRegardless()
        case .dismissCommandInput:
            appState.dismissCommandInput(preserveDraft: true)
            bubblePanel.orderFrontRegardless()
        }
    }

    private func revealCommandInput() {
        appState.presentCommandInput()
        showOrFocusCommandInputPanel()
        bubblePanel.orderFrontRegardless()
    }

    private func revealUnreadBrowser() {
        bubblePanel.orderFrontRegardless()
        if !appState.isCommandInputPresented {
            bubblePanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        appState.presentUnreadBrowserFromEdge()
    }

    private func contextMenuCommand(for action: FloatingContextMenuAction) -> FloatingInteractionCommand {
        switch action {
        case .revealCommandInput:
            return .revealCommandInput
        case .revealUnreadBrowser:
            return .revealUnreadBrowser
        case .dismissLightweightEntry:
            return .dismissLightweightEntry
        case .dismissCommandInput:
            return .dismissCommandInput
        case .openConversation:
            return .focusConversation
        case .openSettings:
            return .focusSettings
        case .quitApplication:
            return .revealCommandInput
        }
    }

    private func showContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        let actions = FloatingInteractionPolicy.contextMenuActions(for: interactionSnapshot)

        for (index, action) in actions.enumerated() {
            if action == .quitApplication, index > 0 {
                menu.addItem(.separator())
            }

            let item = NSMenuItem(
                title: title(for: action),
                action: #selector(handleContextMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
        }

        guard let contentView = bubblePanel.contentView else {
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    private func title(for action: FloatingContextMenuAction) -> String {
        switch action {
        case .revealCommandInput:
            return "打开中央输入"
        case .revealUnreadBrowser:
            return "浏览未读"
        case .dismissLightweightEntry:
            return "收起未读浏览"
        case .dismissCommandInput:
            return "关闭中央输入"
        case .openConversation:
            return "打开完整聊天"
        case .openSettings:
            return "打开设置"
        case .quitApplication:
            return "退出 OpenClaw"
        }
    }

    @objc
    private func handleContextMenuItem(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let action = FloatingContextMenuAction(rawValue: rawValue)
        else {
            return
        }
        if action == .quitApplication {
            NSApp.terminate(nil)
            return
        }
        performInteractionCommand(.contextMenu(action))
    }

    private var collapsedPanelSize: NSSize {
        NSSize(
            width: FloatingPanelMetrics.statusSurfaceWidth,
            height: FloatingPanelMetrics.stripHeight
        )
    }

    private var anchorPanelSize: NSSize {
        if appState.showsCircularFloatingAnchor {
            return NSSize(width: FloatingPanelMetrics.orbDiameter, height: FloatingPanelMetrics.orbDiameter)
        }
        return collapsedPanelSize
    }

    private func desiredFloatingPanelSize() -> NSSize {
        if appState.isMiniChatExpanded {
            let previewHeight = measuredTextHeight(
                appState.latestAssistantPreviewText,
                width: FloatingPanelMetrics.miniPreviewTextWidth,
                font: .preferredFont(forTextStyle: .body),
                minHeight: 0,
                maxHeight: nil
            )
            let badgeHeight: CGFloat = appState.currentAssistantTurnBadgeTitle == nil ? 0 : 28
            let browserHeight: CGFloat = appState.unreadTurnBrowserStatusText == nil ? 0 : 34
            let cardHeight = FloatingPanelMetrics.miniBaseHeight + previewHeight + badgeHeight + browserHeight
            return NSSize(
                width: anchorPanelSize.width + FloatingPanelMetrics.interItemSpacing + FloatingPanelMetrics.miniCardWidth,
                height: max(anchorPanelSize.height, cardHeight)
            )
        }
        if appState.isExpandedConversationPresented {
            return anchorPanelSize
        }
        if !appState.recoveryState.isReady {
            return NSSize(
                width: anchorPanelSize.width + FloatingPanelMetrics.interItemSpacing + FloatingPanelMetrics.recoveryCardWidth,
                height: max(anchorPanelSize.height, FloatingPanelMetrics.recoveryCardHeight)
            )
        }
        if let notification = appState.floatingNotification {
            let notificationFont = NSFont.preferredFont(forTextStyle: .callout)
            let textHeight = measuredTextHeight(
                notification.text,
                width: FloatingPanelMetrics.notificationTextWidth,
                font: notificationFont,
                minHeight: 0,
                maxHeight: maxTextHeight(for: notificationFont, lineLimit: 2)
            )
            let cardHeight = FloatingPanelMetrics.notificationBaseHeight + textHeight
            return NSSize(
                width: anchorPanelSize.width + FloatingPanelMetrics.interItemSpacing + FloatingPanelMetrics.notificationCardWidth,
                height: max(anchorPanelSize.height, cardHeight)
            )
        }
        return collapsedPanelSize
    }

    private func updateFloatingPanelLayout(animated: Bool = true) {
        guard bubblePanel.contentView != nil else {
            return
        }
        guard dragStartFrame == nil else {
            return
        }
        if appState.isFloatingHiddenForFullscreen {
            return
        }
        let visibleFrame = bubblePanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = desiredFloatingPanelSize()
        let origin = constrainedFloatingOrigin(
            origin: NSPoint(
                x: floatingEdge == .leading
                    ? visibleFrame.minX + BubbleDefaults.edgeInset
                    : visibleFrame.maxX - size.width - BubbleDefaults.edgeInset,
                y: resolvedAnchorCenterY(in: visibleFrame) - size.height / 2
            ),
            size: size,
            visibleFrame: visibleFrame
        )
        bubblePanel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        persistFloatingPlacement(for: bubblePanel.frame, visibleFrame: visibleFrame, screen: bubblePanel.screen)
    }

    private func initialFloatingOrigin(in visibleFrame: NSRect) -> NSPoint {
        constrainedFloatingOrigin(
            origin: NSPoint(
                x: floatingEdge == .leading
                    ? visibleFrame.minX + BubbleDefaults.edgeInset
                    : visibleFrame.maxX - collapsedPanelSize.width - BubbleDefaults.edgeInset,
                y: resolvedAnchorCenterY(in: visibleFrame) - collapsedPanelSize.height / 2
            ),
            size: collapsedPanelSize,
            visibleFrame: visibleFrame
        )
    }

    private func restoreFloatingPlacement(from visibleFrame: NSRect) {
        if let rawEdge = UserDefaults.standard.string(forKey: BubbleDefaults.edge),
           let edge = FloatingPanelEdge(rawValue: rawEdge) {
            floatingEdge = edge
        } else {
            floatingEdge = .trailing
        }
        if let storedAnchorY = UserDefaults.standard.object(forKey: BubbleDefaults.anchorY) as? Double {
            anchorCenterY = CGFloat(storedAnchorY)
        } else {
            anchorCenterY = visibleFrame.midY
        }
    }

    private func persistFloatingPlacement(for frame: NSRect, visibleFrame: NSRect, screen: NSScreen?) {
        anchorCenterY = min(max(frame.midY, visibleFrame.minY + frame.height / 2), visibleFrame.maxY - frame.height / 2)
        UserDefaults.standard.set(anchorCenterY, forKey: BubbleDefaults.anchorY)
        UserDefaults.standard.set(floatingEdge.rawValue, forKey: BubbleDefaults.edge)
        if let displayID = screen.flatMap(displayID(for:)) {
            UserDefaults.standard.set(Int(displayID), forKey: BubbleDefaults.displayID)
        }
    }

    private func restoredBubbleScreen() -> NSScreen? {
        guard let storedID = UserDefaults.standard.object(forKey: BubbleDefaults.displayID) as? Int else {
            return nil
        }
        return screen(forDisplayID: UInt32(storedID))
    }

    private func restoredCommandInputScreen() -> NSScreen? {
        guard let storedID = UserDefaults.standard.object(forKey: CommandInputDefaults.displayID) as? Int else {
            return nil
        }
        return screen(forDisplayID: UInt32(storedID))
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { UInt32($0.uintValue) }
    }

    private func screen(forDisplayID displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first { screen in
            self.displayID(for: screen) == displayID
        }
    }

    private func unionVisibleFrame() -> NSRect {
        let unioned = NSScreen.screens.reduce(into: NSRect.null) { result, screen in
            result = result.union(screen.visibleFrame)
        }
        return unioned.isNull ? (NSScreen.main?.visibleFrame ?? .zero) : unioned
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func resolvedAnchorCenterY(in visibleFrame: NSRect) -> CGFloat {
        let fallback = visibleFrame.midY
        let centerY = anchorCenterY ?? fallback
        let halfHeight = desiredFloatingPanelSize().height / 2
        return min(max(centerY, visibleFrame.minY + halfHeight), visibleFrame.maxY - halfHeight)
    }

    private func constrainedFloatingOrigin(origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        constrainedWindowOrigin(origin, size: size, visibleFrame: visibleFrame, inset: BubbleDefaults.edgeInset)
    }

    private func constrainedWindowOrigin(
        _ origin: NSPoint,
        size: NSSize,
        visibleFrame: NSRect,
        inset: CGFloat = 16
    ) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX + inset), visibleFrame.maxX - size.width - inset),
            y: min(max(origin.y, visibleFrame.minY + inset), visibleFrame.maxY - size.height - inset)
        )
    }

    private func closeChatWindow(_ panel: NSPanel) {
        panel.orderOut(nil)
        appState.chatWindowDidResignActive()
        appState.setExpandedConversationPresented(false)
    }

    private func syncCommandInputPanel() {
        if appState.isCommandInputPresented {
            showOrFocusCommandInputPanel()
        } else {
            commandInputPanel?.orderOut(nil)
        }
    }

    private func showOrFocusCommandInputPanel() {
        let panel = commandInputPanel ?? makeCommandInputPanel()
        commandInputPanel = panel
        if !panel.isVisible {
            placeCommandInputPanel(panel)
        }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func placeCommandInputPanel(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? bubblePanel.screen
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }
        let size = panel.frame.size
        if let storedOrigin = restoredCommandInputOrigin(size: size) {
            panel.setFrameOrigin(storedOrigin)
            return
        }
        let center = NSPoint(
            x: visibleFrame.midX,
            y: visibleFrame.minY + visibleFrame.height * 0.38
        )
        let origin = NSPoint(
            x: min(max(center.x - size.width / 2, visibleFrame.minX + 16), visibleFrame.maxX - size.width - 16),
            y: min(max(center.y - size.height / 2, visibleFrame.minY + 16), visibleFrame.maxY - size.height - 16)
        )
        panel.setFrameOrigin(origin)
    }

    private func restoredCommandInputOrigin(size: NSSize) -> NSPoint? {
        guard
            let storedX = UserDefaults.standard.object(forKey: CommandInputDefaults.originX) as? Double,
            let storedY = UserDefaults.standard.object(forKey: CommandInputDefaults.originY) as? Double
        else {
            return nil
        }
        let visibleFrame = restoredCommandInputScreen()?.visibleFrame ?? unionVisibleFrame()
        return constrainedWindowOrigin(
            NSPoint(x: CGFloat(storedX), y: CGFloat(storedY)),
            size: size,
            visibleFrame: visibleFrame
        )
    }

    private func persistCommandInputPlacement(for frame: NSRect) {
        UserDefaults.standard.set(frame.origin.x, forKey: CommandInputDefaults.originX)
        UserDefaults.standard.set(frame.origin.y, forKey: CommandInputDefaults.originY)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = screenContaining(center) ?? commandInputPanel?.screen
        if let displayID = screen.flatMap(displayID(for:)) {
            UserDefaults.standard.set(Int(displayID), forKey: CommandInputDefaults.displayID)
        }
    }

    private func beginFloatingPanelDrag() {
        if dragStartFrame == nil {
            dragStartFrame = bubblePanel.frame
        }
        appState.floatingDragChanged(true)
    }

    private func updateFloatingPanelDrag(from startPoint: NSPoint, to currentPoint: NSPoint) {
        if dragStartFrame == nil {
            dragStartFrame = bubblePanel.frame
        }
        guard let dragStartFrame else {
            return
        }
        let deltaX = currentPoint.x - startPoint.x
        let deltaY = currentPoint.y - startPoint.y
        let visibleFrame = unionVisibleFrame()
        let origin = constrainedFloatingOrigin(
            origin: NSPoint(
                x: dragStartFrame.origin.x + deltaX,
                y: dragStartFrame.origin.y + deltaY
            ),
            size: bubblePanel.frame.size,
            visibleFrame: visibleFrame
        )
        bubblePanel.setFrameOrigin(origin)
        anchorCenterY = bubblePanel.frame.midY
    }

    private func endFloatingPanelDrag() {
        defer {
            dragStartFrame = nil
            appState.floatingDragChanged(false)
        }
        guard bubblePanel.contentView != nil else {
            return
        }
        let center = NSPoint(x: bubblePanel.frame.midX, y: bubblePanel.frame.midY)
        let targetScreen = screenContaining(center) ?? bubblePanel.screen ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let nextEdge: FloatingPanelEdge = bubblePanel.frame.midX <= visibleFrame.midX ? .leading : .trailing
        if nextEdge != floatingEdge {
            floatingEdge = nextEdge
            installBubbleContent(in: bubblePanel)
        }
        if let displayID = targetScreen.flatMap(displayID(for:)) {
            UserDefaults.standard.set(Int(displayID), forKey: BubbleDefaults.displayID)
        }
        updateFloatingPanelLayout()
    }

    private func measuredTextHeight(
        _ text: String?,
        width: CGFloat,
        font: NSFont,
        minHeight: CGFloat,
        maxHeight: CGFloat?
    ) -> CGFloat {
        guard let text, !text.isEmpty else {
            return minHeight
        }
        let rect = NSString(string: text).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let measuredHeight = max(ceil(rect.height), minHeight)
        guard let maxHeight else {
            return measuredHeight
        }
        return min(measuredHeight, maxHeight)
    }

    private func maxTextHeight(for font: NSFont, lineLimit: Int) -> CGFloat {
        ceil(font.boundingRectForFont.height * CGFloat(lineLimit))
    }

    private func refreshHoverMonitor() {
        hoverMonitorTimer?.invalidate()
        hoverMonitorTimer = nil

        guard appState.isMiniChatExpanded, !appState.isExpandedConversationPresented, !appState.isFloatingHiddenForFullscreen else {
            return
        }

        hoverMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isMouseInsideFloatingInteractiveArea() {
                    self.appState.floatingHoverChanged(false)
                }
                if !self.appState.isMiniChatExpanded || self.appState.isExpandedConversationPresented {
                    self.hoverMonitorTimer?.invalidate()
                    self.hoverMonitorTimer = nil
                }
            }
        }
    }

    private func isMouseInsideFloatingInteractiveArea() -> Bool {
        let frame = bubblePanel.frame
        let mouse = NSEvent.mouseLocation
        guard frame.contains(mouse) else {
            return false
        }

        let localPoint = NSPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let anchorWidth = anchorPanelSize.width
        let anchorHeight = anchorPanelSize.height
        let anchorY = max(0, (frame.height - anchorHeight) / 2)
        let anchorX: CGFloat = floatingEdge == .leading ? 0 : frame.width - anchorWidth
        let anchorRect = NSRect(
            x: anchorX,
            y: anchorY,
            width: anchorWidth,
            height: anchorHeight
        ).insetBy(dx: -6, dy: -6)

        let accessoryX: CGFloat = floatingEdge == .leading
            ? anchorWidth + FloatingPanelMetrics.interItemSpacing
            : 0
        let accessoryRect = NSRect(
            x: accessoryX,
            y: 0,
            width: FloatingPanelMetrics.miniCardWidth,
            height: frame.height
        ).insetBy(dx: -4, dy: -4)

        return anchorRect.contains(localPoint) || accessoryRect.contains(localPoint)
    }

    private func installFullscreenObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceFullscreenChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceFullscreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        updateFloatingVisibilityForFullscreen()
    }

    @objc
    private func handleWorkspaceFullscreenChange() {
        updateFloatingVisibilityForFullscreen()
    }

    private func updateFloatingVisibilityForFullscreen() {
        let shouldHide = isAnyScreenLikelyInFullscreen()
        appState.setFloatingHiddenForFullscreen(shouldHide)
        if shouldHide {
            bubblePanel.orderOut(nil)
            return
        }
        updateFloatingPanelLayout(animated: false)
        bubblePanel.orderFrontRegardless()
    }

    private func isAnyScreenLikelyInFullscreen() -> Bool {
        NSScreen.screens.contains { screen in
            abs(screen.frame.width - screen.visibleFrame.width) < 1
                && abs(screen.frame.height - screen.visibleFrame.height) < 1
        }
    }
}

extension FloatingWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSPanel === chatPanel {
            appState.chatWindowDidBecomeActive()
            appState.setExpandedConversationPresented(true)
            return
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSPanel === chatPanel {
            appState.chatWindowDidResignActive()
        }
    }

    func windowDidMove(_ notification: Notification) {
        if let panel = notification.object as? NSPanel, panel === commandInputPanel {
            persistCommandInputPlacement(for: panel.frame)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSPanel === chatPanel {
            appState.chatWindowDidResignActive()
            appState.setExpandedConversationPresented(false)
        }
    }
}

private final class FloatingInteractionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private enum FloatingPanelEdge: String {
    case leading
    case trailing
}

private enum FloatingPanelMetrics {
    static let stripWidth: CGFloat = 6
    static let statusSurfaceWidth: CGFloat = 34
    static let stripHeight: CGFloat = 96
    static let stripCornerRadius: CGFloat = 3
    static let orbDiameter: CGFloat = 56
    static let orbBadgeOffsetX: CGFloat = 16
    static let orbBadgeOffsetY: CGFloat = -16
    static let interItemSpacing: CGFloat = 10
    static let miniCardWidth: CGFloat = 316
    static let miniPreviewTextWidth: CGFloat = 284
    static let miniBaseHeight: CGFloat = 172
    static let notificationCardWidth: CGFloat = 236
    static let notificationTextWidth: CGFloat = 204
    static let notificationBaseHeight: CGFloat = 58
    static let recoveryCardWidth: CGFloat = 248
    static let recoveryCardHeight: CGFloat = 146
    static let chatGap: CGFloat = 14
}

private enum InteractionCommandSource {
    case revealCommand
    case doubleClickCommand
    case dismissCommand
    case contextMenu(FloatingContextMenuAction)
}

private struct FloatingAnchorDragHandle: NSViewRepresentable {
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onDragChange: (NSPoint, NSPoint) -> Void
    let onDragEnd: () -> Void
    let onDoubleTap: () -> Void
    let onSecondaryTap: (NSEvent) -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> AnchorDragView {
        let view = AnchorDragView()
        view.onTap = onTap
        view.onDragStart = onDragStart
        view.onDragChange = onDragChange
        view.onDragEnd = onDragEnd
        view.onDoubleTap = onDoubleTap
        view.onSecondaryTap = onSecondaryTap
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: AnchorDragView, context: Context) {
        nsView.onTap = onTap
        nsView.onDragStart = onDragStart
        nsView.onDragChange = onDragChange
        nsView.onDragEnd = onDragEnd
        nsView.onDoubleTap = onDoubleTap
        nsView.onSecondaryTap = onSecondaryTap
        nsView.onHover = onHover
    }

    final class AnchorDragView: NSView {
        var onTap: () -> Void = {}
        var onDragStart: () -> Void = {}
        var onDragChange: (NSPoint, NSPoint) -> Void = { _, _ in }
        var onDragEnd: () -> Void = {}
        var onDoubleTap: () -> Void = {}
        var onSecondaryTap: (NSEvent) -> Void = { _ in }
        var onHover: (Bool) -> Void = { _ in }

        private let dragThreshold: CGFloat = 4
        private var startScreenPoint: NSPoint?
        private var didDrag = false
        private var trackingArea: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                onSecondaryTap(event)
                return
            }
            startScreenPoint = screenPoint(for: event)
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startScreenPoint else {
                return
            }
            let currentPoint = screenPoint(for: event)
            if !didDrag, hypot(currentPoint.x - startScreenPoint.x, currentPoint.y - startScreenPoint.y) >= dragThreshold {
                didDrag = true
                onDragStart()
            }
            if didDrag {
                onDragChange(startScreenPoint, currentPoint)
            }
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                startScreenPoint = nil
                didDrag = false
            }
            if didDrag {
                onDragEnd()
            } else if event.clickCount >= 2 {
                onDoubleTap()
            } else {
                onTap()
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onSecondaryTap(event)
        }

        private func screenPoint(for event: NSEvent) -> NSPoint {
            guard let window else {
                return .zero
            }
            return window.convertPoint(toScreen: event.locationInWindow)
        }
    }
}

private struct ReliableHoverReporter: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.onHover = onHover
    }

    final class HoverTrackingView: NSView {
        var onHover: (Bool) -> Void = { _ in }
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover(false)
        }
    }
}

private struct FloatingCompactPanelView: View {
    @EnvironmentObject private var appState: AppStateModel
    let side: FloatingPanelEdge
    let onOpenConversation: () -> Void
    let onOpenSettings: () -> Void
    let onDragStart: () -> Void
    let onDragChange: (NSPoint, NSPoint) -> Void
    let onDragEnd: () -> Void
    let onDoubleTap: () -> Void
    let onSecondaryTap: (NSEvent) -> Void

    var body: some View {
        HStack(spacing: FloatingPanelMetrics.interItemSpacing) {
            if side == .leading {
                stripView
                accessoryContent
            } else {
                accessoryContent
                stripView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .leading ? .leading : .trailing)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: appState.isMiniChatExpanded)
        .animation(.easeOut(duration: 0.32), value: appState.floatingNotification != nil)
    }

    @ViewBuilder
    private var accessoryContent: some View {
        if appState.isMiniChatExpanded {
            miniChatCard
                .transition(accessoryTransition)
        } else if appState.isExpandedConversationPresented {
            EmptyView()
        } else if !appState.recoveryState.isReady {
            recoveryCard(appState.recoveryState)
                .transition(accessoryTransition)
        } else if let notification = appState.floatingNotification {
            notificationCard(notification)
                .transition(accessoryTransition)
        }
    }

    private var accessoryTransition: AnyTransition {
        let dx: CGFloat = side == .leading ? -10 : 10
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: dx, y: 0)),
            removal: .opacity.combined(with: .offset(x: dx * 0.6, y: 0))
        )
    }

    private var stripView: some View {
        Group {
            if appState.showsCircularFloatingAnchor {
                orbAnchorView
            } else {
                collapsedStripView
            }
        }
        .overlay {
            FloatingAnchorDragHandle(
                onTap: handleAnchorTap,
                onDragStart: onDragStart,
                onDragChange: onDragChange,
                onDragEnd: onDragEnd,
                onDoubleTap: onDoubleTap,
                onSecondaryTap: onSecondaryTap,
                onHover: { isHovered in
                    appState.floatingHoverChanged(isHovered)
                }
            )
        }
    }

    private var collapsedStripView: some View {
        ZStack(alignment: side == .leading ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: FloatingPanelMetrics.stripCornerRadius, style: .continuous)
                .fill(stripGradient)
                .frame(width: FloatingPanelMetrics.stripWidth, height: FloatingPanelMetrics.stripHeight)

            VStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                if appState.unreadAssistantTurnCount > 0 {
                    Text(unreadBadgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .offset(x: side == .leading ? 12 : -12)
                } else {
                    Image(systemName: primaryGlyphName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .offset(x: side == .leading ? 10 : -10)
                }
            }
        }
        .frame(
            width: FloatingPanelMetrics.statusSurfaceWidth,
            height: FloatingPanelMetrics.stripHeight,
            alignment: side == .leading ? .leading : .trailing
        )
    }

    private var orbAnchorView: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(stripGradient)
                .shadow(color: OpenClawStyle.Shadow.primary.opacity(0.5), radius: 8, x: 0, y: 4)
                .shadow(color: OpenClawStyle.Shadow.contact.opacity(0.5), radius: 3, x: 0, y: 2)
                .frame(width: FloatingPanelMetrics.orbDiameter, height: FloatingPanelMetrics.orbDiameter)

            Image(systemName: primaryGlyphName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
                .offset(x: side == .leading ? -14 : 14, y: 14)

            if appState.unreadAssistantTurnCount > 0 {
                Text(unreadBadgeText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
                    .offset(
                        x: side == .leading
                            ? -FloatingPanelMetrics.orbBadgeOffsetX
                            : FloatingPanelMetrics.orbBadgeOffsetX,
                        y: FloatingPanelMetrics.orbBadgeOffsetY
                    )
            }
        }
        .frame(width: FloatingPanelMetrics.orbDiameter, height: FloatingPanelMetrics.orbDiameter)
    }

    private var miniChatCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let badgeTitle = appState.currentAssistantTurnBadgeTitle {
                Text(badgeTitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }

            if let preview = appState.latestAssistantPreviewText, !preview.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.unreadTurnBrowserStatusText == nil ? "最近回复" : "当前 Turn")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)

                    Text(preview)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .lineSpacing(2)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .openClawSurface(cornerRadius: 15)
            }

            if let browserStatus = appState.unreadTurnBrowserStatusText {
                HStack(spacing: 8) {
                    Text(browserStatus)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(appState.unreadTurnBrowserActionTitle) {
                        appState.advanceUnreadTurn()
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
                    .keyboardShortcut(.space, modifiers: [])
                }
                .padding(.horizontal, 8)
            }

            Button {
                appState.presentCommandInput()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "command")
                        .font(.system(size: 11, weight: .semibold))
                    Text("+")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "space")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(
                Capsule()
                    .fill(.thinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(OpenClawStyle.Stroke.light, lineWidth: 1)
                    )
            )

            if let blockingMessage = appState.chatSendReadiness.blockingMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.recoveryState.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text(blockingMessage)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        if let primaryAction = appState.chatSendReadiness.primaryAction {
                            miniActionButton(primaryAction)
                        }
                        if let secondaryAction = appState.chatSendReadiness.secondaryAction {
                            miniActionButton(secondaryAction)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: FloatingPanelMetrics.miniCardWidth, alignment: .leading)
        .background(ReliableHoverReporter { isHovered in
            appState.floatingHoverChanged(isHovered)
        })
    }

    private func recoveryCard(_ recoveryState: RecoveryStateProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recoveryState.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Text(recoveryState.detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let primaryAction = recoveryState.primaryAction {
                    miniActionButton(primaryAction)
                }
                if let secondaryAction = recoveryState.secondaryAction {
                    miniActionButton(secondaryAction)
                }
            }
        }
        .padding(14)
        .frame(width: FloatingPanelMetrics.recoveryCardWidth, height: FloatingPanelMetrics.recoveryCardHeight, alignment: .leading)
        .openClawSurface(cornerRadius: 18)
        .background(ReliableHoverReporter { isHovered in
            appState.floatingHoverChanged(isHovered)
        })
    }

    private func notificationCard(_ notification: FloatingNotificationState) -> some View {
        Button {
            appState.presentUnreadBrowserFromEdge()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("OpenClaw 新回复")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let badgeTitle = notification.turn.badge?.title {
                        Text(badgeTitle)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                    }
                }

                Text(notification.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(14)
            .frame(width: FloatingPanelMetrics.notificationCardWidth, alignment: .leading)
            .openClawSurface(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .background(ReliableHoverReporter { isHovered in
            appState.floatingHoverChanged(isHovered)
        })
    }

    private var stripGradient: LinearGradient {
        LinearGradient(
            colors: primaryGradientColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var unreadBadgeText: String {
        appState.unreadAssistantTurnCount > 99 ? "99+" : "\(appState.unreadAssistantTurnCount)"
    }

    private var miniStatusText: String {
        if let browserStatus = appState.unreadTurnBrowserStatusText {
            return browserStatus
        }
        if let timestamp = appState.latestAssistantPreviewTimestamp {
            return "最近回复 \(timestamp.formatted(date: .omitted, time: .shortened))"
        }
        return appState.connectionState.detail
    }

    private func handleAnchorTap() {
        if appState.recoveryState.primaryAction?.kind == .openSettings {
            onOpenSettings()
            return
        }
        if appState.isExpandedConversationPresented {
            onOpenConversation()
        } else if appState.unreadAssistantTurnCount > 0 {
            appState.presentUnreadBrowserFromEdge()
        }
    }

    private func miniActionButton(_ action: RecoveryActionDescriptor) -> some View {
        Button(action.title) {
            performRecoveryAction(action)
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(action.kind == .openSettings ? Color.secondary : Color.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(action.kind == .openSettings ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.accentColor))
        )
    }

    private func performRecoveryAction(_ action: RecoveryActionDescriptor) {
        switch action.kind {
        case .openSettings:
            onOpenSettings()
        default:
            appState.performRecoveryAction(action.kind)
        }
    }

    private var statusColor: Color {
        switch appState.floatingPrimaryVisualState {
        case .idle:
            return .gray
        case .listening:
            return .cyan
        case .thinking:
            return .blue
        case .outputting:
            return .green
        case .disconnected:
            return .orange
        }
    }

    private var primaryGradientColors: [Color] {
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

    private var primaryGlyphName: String {
        switch appState.floatingPrimaryVisualState {
        case .idle:
            return "moon.stars.fill"
        case .listening:
            return "waveform"
        case .thinking:
            return "ellipsis.bubble.fill"
        case .outputting:
            return "bubble.left.and.text.bubble.right.fill"
        case .disconnected:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct CommandInputPanelView: View {
    @EnvironmentObject private var appState: AppStateModel
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            MultilineMessageInput(
                text: Binding(
                    get: { appState.commandInputState.draft },
                    set: { appState.updateCommandInputDraft($0) }
                ),
                placeholder: "one sentence anytime",
                onSend: {
                    appState.submitCommandInputDraft()
                },
                onEscape: onDismiss,
                usesGlassStyle: true,
                autoFocus: true
            )
            .frame(height: 34)

            Spacer(minLength: 0)

            if appState.commandInputState.isSending {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
            }

            Button {
                appState.submitCommandInputDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .openClawChatSurface(cornerRadius: 18, includeShadow: true)
        .padding(8)
    }

    private var canSubmit: Bool {
        !appState.commandInputState.isSending
            && !appState.commandInputState.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
