import Foundation

enum FloatingInteractionCommand: Equatable {
    case revealCommandInput
    case revealUnreadBrowser
    case focusConversation
    case focusSettings
    case dismissLightweightEntry
    case dismissCommandInput
}

enum FloatingContextMenuAction: String, Equatable {
    case revealCommandInput
    case revealUnreadBrowser
    case dismissLightweightEntry
    case dismissCommandInput
    case openConversation
    case openSettings
    case quitApplication
}

struct FloatingInteractionSnapshot: Equatable {
    var isMiniChatExpanded: Bool
    var isCommandInputPresented: Bool
    var hasUnreadTurns: Bool
    var isUnreadBrowserActive: Bool
    var isConversationVisible: Bool
    var isSettingsVisible: Bool
}

enum FloatingInteractionPolicy {
    static func revealCommand(for snapshot: FloatingInteractionSnapshot) -> FloatingInteractionCommand {
        .revealCommandInput
    }

    static func escapeCommand(for snapshot: FloatingInteractionSnapshot) -> FloatingInteractionCommand? {
        if snapshot.isCommandInputPresented {
            return .dismissCommandInput
        }
        if snapshot.isMiniChatExpanded, snapshot.isUnreadBrowserActive, !snapshot.isConversationVisible {
            return .dismissLightweightEntry
        }
        return nil
    }

    static func doubleClickCommand(for snapshot: FloatingInteractionSnapshot) -> FloatingInteractionCommand {
        snapshot.hasUnreadTurns ? .revealUnreadBrowser : .focusConversation
    }

    static func contextMenuActions(for snapshot: FloatingInteractionSnapshot) -> [FloatingContextMenuAction] {
        var actions: [FloatingContextMenuAction] = [
            .openConversation,
            .openSettings,
            .quitApplication
        ]
        if snapshot.hasUnreadTurns {
            actions.insert(snapshot.isUnreadBrowserActive ? .dismissLightweightEntry : .revealUnreadBrowser, at: 0)
        }
        actions.insert(snapshot.isCommandInputPresented ? .dismissCommandInput : .revealCommandInput, at: 0)

        if snapshot.isConversationVisible {
            actions.removeAll { $0 == .openConversation }
        }
        if snapshot.isSettingsVisible {
            actions.removeAll { $0 == .openSettings }
        }
        return actions
    }
}
