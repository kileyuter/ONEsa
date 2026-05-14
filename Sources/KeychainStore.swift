import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var status: OSStatus? {
        if case .unexpectedStatus(let status) = self {
            return status
        }
        return nil
    }

    var isAuthenticationFailure: Bool {
        status == errSecAuthFailed
    }

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if status == errSecAuthFailed {
                return "Keychain 拒绝访问已保存的凭证。请重新保存 app_secret 后再授权。"
            }
            return "Keychain 操作失败，状态码：\(status)"
        case .invalidData:
            return "Keychain 中的数据无法解析。"
        }
    }
}

final class KeychainStore {
    enum Account: String {
        case appSecret = "feishu.app_secret"
        case userAccessToken = "feishu.user_access_token"
        case refreshToken = "feishu.refresh_token"
    }

    private let service: String

    init(service: String = "ONEsa.v0.1.FeishuOAuth") {
        self.service = service
    }

    func save(_ value: String, account: Account) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    func read(account: Account) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }

        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainStoreError.invalidData
        }
        return value
    }

    func delete(account: Account) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
    }
}
