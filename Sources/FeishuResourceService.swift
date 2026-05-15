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
    case resourceUnavailable
    case permissionDenied
    case downloadFailed(String)
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "缺少飞书 app_id 配置。"
        case .missingAppSecret:
            "缺少飞书 app_secret，无法下载消息图片。"
        case .tenantTokenFailed(let message):
            "获取 tenant_access_token 失败：\(message)"
        case .resourceUnavailable:
            "图片资源已失效或无法通过开放接口下载。建议让 AI 重新以 Markdown 文本/表格回复。"
        case .permissionDenied:
            "当前飞书应用暂无权限下载这张图片，请检查机器人是否在会话中，以及消息资源权限是否已开通。"
        case .downloadFailed(let message):
            "下载飞书图片失败：\(message)"
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
    private var failedPrefetchKeys = Set<String>()

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
        if let cached = cachedImage(messageID: messageID, imageKey: imageKey) {
            return cached
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

        let downloaded: FeishuResourceImage
        do {
            downloaded = try await performImageRequest(request)
        } catch {
            downloaded = try await downloadUploadedImageFallback(imageKey: imageKey, token: token)
        }

        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        try? downloaded.data.write(to: cacheURL, options: .atomic)
        return downloaded
    }

    func cachedImage(messageID: String, imageKey: String) -> FeishuResourceImage? {
        let cacheURL = cacheURL(messageID: messageID, imageKey: imageKey)
        guard let cached = try? Data(contentsOf: cacheURL), !cached.isEmpty else {
            return nil
        }
        return FeishuResourceImage(data: cached, contentType: contentType(for: cached))
    }

    func prefetchImage(messageID: String, imageKey: String) async {
        let key = cacheKey(messageID: messageID, imageKey: imageKey)
        guard cachedImage(messageID: messageID, imageKey: imageKey) == nil else {
            return
        }
        guard !failedPrefetchKeys.contains(key) else {
            return
        }

        do {
            _ = try await image(messageID: messageID, imageKey: imageKey)
        } catch {
            failedPrefetchKeys.insert(key)
        }
    }

    func prefetchImages(_ images: [MessageRemoteImageReference]) async {
        for image in images {
            guard !Task.isCancelled else {
                return
            }
            await prefetchImage(messageID: image.messageID, imageKey: image.imageKey)
        }
    }

    private func downloadUploadedImageFallback(
        imageKey: String,
        token: String
    ) async throws -> FeishuResourceImage {
        guard
            let encodedImageKey = imageKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://open.feishu.cn/open-apis/im/v1/images/\(encodedImageKey)")
        else {
            throw FeishuResourceError.invalidImageData
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await performImageRequest(request)
    }

    private func performImageRequest(_ request: URLRequest) async throws -> FeishuResourceImage {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeishuResourceError.invalidImageData
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw mappedDownloadError(statusCode: httpResponse.statusCode, data: data)
        }
        guard !data.isEmpty else {
            throw FeishuResourceError.invalidImageData
        }
        return FeishuResourceImage(
            data: data,
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? contentType(for: data)
        )
    }

    private func mappedDownloadError(statusCode: Int, data: Data) -> FeishuResourceError {
        let errorBody = (try? JSONDecoder().decode(FeishuAPIErrorBody.self, from: data))
            ?? FeishuAPIErrorBody(code: nil, msg: nil, error: nil)
        let code = errorBody.code ?? errorBody.error?.code
        let message = errorBody.msg ?? errorBody.error?.message
        switch code {
        case 14005, 234005:
            return .resourceUnavailable
        case 234002, 234004, 234007, 234008, 234009:
            return .permissionDenied
        default:
            let readableMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let readableMessage, !readableMessage.isEmpty {
                return .downloadFailed("HTTP \(statusCode)，\(readableMessage)")
            }
            return .downloadFailed("HTTP \(statusCode)")
        }
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
        cacheDirectory.appendingPathComponent("\(cacheKey(messageID: messageID, imageKey: imageKey)).image")
    }

    private func cacheKey(messageID: String, imageKey: String) -> String {
        SHA256.hash(data: Data("\(messageID)|\(imageKey)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
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

private struct FeishuAPIErrorBody: Decodable {
    let code: Int?
    let msg: String?
    let error: FeishuAPIErrorDetail?
}

private struct FeishuAPIErrorDetail: Decodable {
    let code: Int?
    let message: String?
}
