import Foundation

final class ChatHistoryStore {
    private enum Keys {
        static let messages = "onesa.chat.history.messages"
    }

    private let userDefaults: UserDefaults
    private let maxMessageCount: Int

    init(userDefaults: UserDefaults = .standard, maxMessageCount: Int = 80) {
        self.userDefaults = userDefaults
        self.maxMessageCount = maxMessageCount
    }

    func load() -> [ChatMessage] {
        guard
            let data = userDefaults.data(forKey: Keys.messages),
            let messages = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else {
            return []
        }
        return Array(messages.suffix(maxMessageCount))
    }

    func save(_ messages: [ChatMessage]) {
        let recentMessages = Array(messages.suffix(maxMessageCount))
        guard let data = try? JSONEncoder().encode(recentMessages) else {
            return
        }
        userDefaults.set(data, forKey: Keys.messages)
    }
}
