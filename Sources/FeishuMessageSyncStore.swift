import Foundation

struct FeishuMessageSyncState: Codable, Equatable {
    var chatID: String
    var lastSuccessfulSyncAt: Date?
    var recentMessageIDs: [String]

    init(
        chatID: String,
        lastSuccessfulSyncAt: Date? = nil,
        recentMessageIDs: [String] = []
    ) {
        self.chatID = chatID
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.recentMessageIDs = recentMessageIDs
    }
}

final class FeishuMessageSyncStore {
    private enum Keys {
        static let state = "openclaw.feishu.message.sync.state"
    }

    private let userDefaults: UserDefaults
    private let maxRecentMessageIDs: Int

    init(userDefaults: UserDefaults = .standard, maxRecentMessageIDs: Int = 200) {
        self.userDefaults = userDefaults
        self.maxRecentMessageIDs = maxRecentMessageIDs
    }

    func loadState(for chatID: String) -> FeishuMessageSyncState {
        guard
            let data = userDefaults.data(forKey: Keys.state),
            let state = try? JSONDecoder().decode(FeishuMessageSyncState.self, from: data),
            state.chatID == chatID
        else {
            return FeishuMessageSyncState(chatID: chatID)
        }
        return state
    }

    func saveState(_ state: FeishuMessageSyncState) {
        guard let data = try? JSONEncoder().encode(trimmedState(state)) else {
            return
        }
        userDefaults.set(data, forKey: Keys.state)
    }

    func reset() {
        userDefaults.removeObject(forKey: Keys.state)
    }

    private func trimmedState(_ state: FeishuMessageSyncState) -> FeishuMessageSyncState {
        var state = state
        if state.recentMessageIDs.count > maxRecentMessageIDs {
            state.recentMessageIDs = Array(state.recentMessageIDs.suffix(maxRecentMessageIDs))
        }
        return state
    }
}
