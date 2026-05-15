import CryptoKit
import Foundation

struct FeishuResourceImage: Equatable {
    let data: Data
    let contentType: String?
}

enum FeishuResourceError: LocalizedError {
    case missingConfiguration
    case missingAppSecret
    case tenantTokenFailed(String)
    case downloadFailed(Int, String)
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "缺少飞书 app_id 配置。"
        case .missingAppSecret:
            "缺少飞书 app_secret，无法下载消息图片。"
        case .tenantTokenFailed(let message):
            "获取 tenant_access_token 失败：\(message)"
        case .downloadFailed(let statusCode, let message):
            "下载飞书图片失败：HTTP \(statusCode) \(message)"
        case .invalidImageData:
            "飞书返回的图片数据无效。"
        }
    }
}

actor FeishuResourceService {
    static let shared = FeishuResourceService()

    private let configurationStore: FeishuConfigurationStore
    private let keychainStore: KeychainStore
    private let session: URLSession
    private let cacheDirectory: URL
    private var cachedTenantToken: (token: String, expiresAt: Date)?

    init(
        configurationStore: FeishuConfigurationStore = FeishuConfigurationStore(),
        keychainStore: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.configurationStore = configurationStore
        self.keychainStore = keychainStore
        self.session = session

        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = baseDirectory
            .appendingPathComponent("ONEsa", isDirectory: true)
            .appendingPathComponent("ResourceCache", isDirectory: true)
    }

    func image(messageID: String, imageKey: String) async throws -> FeishuResourceImage {
        let cacheURL = cacheURL(messageID: messageID, imageKey: imageKey)
        if let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty {
            return FeishuResourceImage(data: cached, contentType: contentType(for: cached))
        }

        let token = try await tenantAccessToken()
        guard
            let encodedMessageID = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedImageKey = imageKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(
                string: "https://open.feishu.cn/open-apis/im/v1/messages/\(encodedMessageID)/resources/\(encodedImageKey)?type=image"
            )
        else {
            throw FeishuResourceError.invalidImageData
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeishuResourceError.invalidImageData
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FeishuResourceError.downloadFailed(httpResponse.statusCode, body)
        }
        guard !data.isEmpty else {
            throw FeishuResourceError.invalidImageData
        }

        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
        return FeishuResourceImage(
            data: data,
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? contentType(for: data)
        )
    }

    private func tenantAccessToken() async throws -> String {
        if let cachedTenantToken, cachedTenantToken.expiresAt > Date().addingTimeInterval(60) {
            return cachedTenantToken.token
        }

        let configuration = configurationStore.load()
        let appID = configuration.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appID.isEmpty else {
            throw FeishuResourceError.missingConfiguration
        }
        guard
            let appSecret = try keychainStore.read(account: .appSecret)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !appSecret.isEmpty
        else {
            throw FeishuResourceError.missingAppSecret
        }

        var request = URLRequest(url: URL(string: "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "app_id": appID,
            "app_secret": appSecret
        ])

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw FeishuResourceError.tenantTokenFailed("HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(FeishuTenantTokenResponse.self, from: data)
        guard decoded.code == 0, let token = decoded.tenantAccessToken, !token.isEmpty else {
            throw FeishuResourceError.tenantTokenFailed(decoded.msg ?? "错误码 \(decoded.code)")
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(max(60, decoded.expire ?? 7200)))
        cachedTenantToken = (token: token, expiresAt: expiresAt)
        return token
    }

    private func cacheURL(messageID: String, imageKey: String) -> URL {
        let digest = SHA256.hash(data: Data("\(messageID)|\(imageKey)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent("\(digest).image")
    }

    private func contentType(for data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.starts(with: [0xFF, 0xD8]) {
            return "image/jpeg"
        }
        if data.starts(with: Array("GIF".utf8)) {
            return "image/gif"
        }
        if data.count >= 12,
           data.starts(with: Array("RIFF".utf8)),
           Array(data[8..<12]) == Array("WEBP".utf8) {
            return "image/webp"
        }
        return nil
    }
}

private struct FeishuTenantTokenResponse: Decodable {
    let code: Int
    let msg: String?
    let tenantAccessToken: String?
    let expire: Int?

    private enum CodingKeys: String, CodingKey {
        case code
        case msg
        case tenantAccessToken = "tenant_access_token"
        case expire
    }
}
