import Foundation

struct FeishuStoredConfiguration: Codable, Equatable {
    var appID: String
    var redirectURI: String
    var targetChatID: String
    var aiSenderID: String
    var aiSenderType: String
    var scopes: String
    var tokenExpiresAt: Date?

    static let empty = FeishuStoredConfiguration(
        appID: "",
        redirectURI: "http://127.0.0.1:18765/callback",
        targetChatID: "",
        aiSenderID: "",
        aiSenderType: "",
        scopes: "im:message im:message.send_as_user im:message.p2p_msg:get_as_user im:message.group_msg:get_as_user",
        tokenExpiresAt: nil
    )

    private enum CodingKeys: String, CodingKey {
        case appID
        case redirectURI
        case targetChatID
        case aiSenderID
        case aiSenderType
        case legacyOpenClawSenderID = "openClawSenderID"
        case legacyOpenClawSenderType = "openClawSenderType"
        case scopes
        case tokenExpiresAt
    }

    init(
        appID: String,
        redirectURI: String,
        targetChatID: String,
        aiSenderID: String,
        aiSenderType: String,
        scopes: String,
        tokenExpiresAt: Date?
    ) {
        self.appID = appID
        self.redirectURI = redirectURI
        self.targetChatID = targetChatID
        self.aiSenderID = aiSenderID
        self.aiSenderType = aiSenderType
        self.scopes = scopes
        self.tokenExpiresAt = tokenExpiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appID = try container.decode(String.self, forKey: .appID)
        redirectURI = try container.decode(String.self, forKey: .redirectURI)
        targetChatID = try container.decode(String.self, forKey: .targetChatID)
        aiSenderID = try container.decodeIfPresent(String.self, forKey: .aiSenderID)
            ?? container.decodeIfPresent(String.self, forKey: .legacyOpenClawSenderID)
            ?? ""
        aiSenderType = try container.decodeIfPresent(String.self, forKey: .aiSenderType)
            ?? container.decodeIfPresent(String.self, forKey: .legacyOpenClawSenderType)
            ?? ""
        scopes = try container.decode(String.self, forKey: .scopes)
        tokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .tokenExpiresAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appID, forKey: .appID)
        try container.encode(redirectURI, forKey: .redirectURI)
        try container.encode(targetChatID, forKey: .targetChatID)
        try container.encode(aiSenderID, forKey: .aiSenderID)
        try container.encode(aiSenderType, forKey: .aiSenderType)
        try container.encode(scopes, forKey: .scopes)
        try container.encodeIfPresent(tokenExpiresAt, forKey: .tokenExpiresAt)
    }

    var isReadyForAuthorization: Bool {
        !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !redirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasTargetChat: Bool {
        !targetChatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAISenderFilter: Bool {
        !aiSenderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !aiSenderType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct FeishuConnectionSnapshot: Equatable {
    var configuration: FeishuStoredConfiguration
    var hasAppSecret: Bool
    var hasUserAccessToken: Bool
    var hasRefreshToken: Bool

    var isConfigured: Bool {
        configuration.isReadyForAuthorization
            && configuration.hasTargetChat
            && configuration.hasAISenderFilter
            && hasAppSecret
    }

    var hasValidUserAccessToken: Bool {
        guard hasUserAccessToken, let tokenExpiresAt = configuration.tokenExpiresAt else {
            return false
        }
        return tokenExpiresAt > Date().addingTimeInterval(60)
    }
}

struct FeishuCredentialMetadata: Codable, Equatable {
    var hasAppSecret: Bool
    var hasUserAccessToken: Bool
    var hasRefreshToken: Bool

    static let empty = FeishuCredentialMetadata(
        hasAppSecret: false,
        hasUserAccessToken: false,
        hasRefreshToken: false
    )
}

final class FeishuConfigurationStore {
    private enum Keys {
        static let configuration = "feishu.oauth.configuration"
        static let credentialMetadata = "feishu.oauth.credential_metadata"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> FeishuStoredConfiguration {
        guard
            let data = userDefaults.data(forKey: Keys.configuration),
            let configuration = try? JSONDecoder().decode(FeishuStoredConfiguration.self, from: data)
        else {
            return .empty
        }
        return configuration
    }

    func save(_ configuration: FeishuStoredConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        userDefaults.set(data, forKey: Keys.configuration)
    }

    func loadCredentialMetadata() -> FeishuCredentialMetadata {
        guard
            let data = userDefaults.data(forKey: Keys.credentialMetadata),
            let metadata = try? JSONDecoder().decode(FeishuCredentialMetadata.self, from: data)
        else {
            return .empty
        }
        return metadata
    }

    func saveCredentialMetadata(_ metadata: FeishuCredentialMetadata) throws {
        let data = try JSONEncoder().encode(metadata)
        userDefaults.set(data, forKey: Keys.credentialMetadata)
    }

    func updateCredentialMetadata(
        hasAppSecret: Bool? = nil,
        hasUserAccessToken: Bool? = nil,
        hasRefreshToken: Bool? = nil
    ) throws {
        var metadata = loadCredentialMetadata()
        if let hasAppSecret {
            metadata.hasAppSecret = hasAppSecret
        }
        if let hasUserAccessToken {
            metadata.hasUserAccessToken = hasUserAccessToken
        }
        if let hasRefreshToken {
            metadata.hasRefreshToken = hasRefreshToken
        }
        try saveCredentialMetadata(metadata)
    }

    func clearTokenMetadata() throws {
        var configuration = load()
        configuration.tokenExpiresAt = nil
        try save(configuration)
    }

    func clearAuthorizationMetadata() throws {
        try clearTokenMetadata()
        try updateCredentialMetadata(hasUserAccessToken: false, hasRefreshToken: false)
    }
}
