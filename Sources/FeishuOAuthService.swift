import AppKit
import CryptoKit
import Darwin
import Foundation

enum FeishuOAuthError: LocalizedError {
    case invalidRedirectURI
    case unsupportedRedirectHost(String)
    case invalidCallbackRequest
    case callbackError(String)
    case callbackTimeout
    case callbackServerFailed(String)
    case missingAppSecret
    case missingAuthorizationCode
    case tokenExchangeFailed(String)
    case missingAccessToken
    case missingRefreshToken
    case tokenRefreshFailed(String)
    case reauthorizationRequired(String)
    case callbackCancelled
    case missingPendingAuthorization
    case invalidManualAuthorizationInput

    var errorDescription: String? {
        switch self {
        case .invalidRedirectURI:
            "回调地址无效，请使用 http://127.0.0.1:<port>/<path>。"
        case .unsupportedRedirectHost(let host):
            "回调地址 host 必须是 127.0.0.1，不支持 localhost 或其他 host；当前 host：\(host)。"
        case .invalidCallbackRequest:
            "飞书授权回调请求无法解析。"
        case .callbackError(let message):
            "飞书授权回调失败：\(message)"
        case .callbackTimeout:
            "等待飞书授权回调超时，请重新授权。"
        case .callbackServerFailed(let message):
            "本地回调服务启动失败：\(message)"
        case .missingAppSecret:
            "请先保存飞书 app_secret。"
        case .missingAuthorizationCode:
            "飞书授权回调没有返回 code。"
        case .tokenExchangeFailed(let message):
            "获取 user_access_token 失败：\(message)"
        case .missingAccessToken:
            "飞书响应中没有 user_access_token。"
        case .missingRefreshToken:
            "当前授权未返回可用的 refresh_token，请确认 scope 包含 offline_access 并重新授权。"
        case .tokenRefreshFailed(let message):
            "自动刷新 user_access_token 失败：\(message)"
        case .reauthorizationRequired(let message):
            message
        case .callbackCancelled:
            UserFacingCopy.Authorization.cancelled
        case .missingPendingAuthorization:
            "当前没有可继续的授权会话，请先点击“开始授权”，再粘贴浏览器返回的 code。"
        case .invalidManualAuthorizationInput:
            "请输入浏览器返回的授权码 code，或粘贴包含 code 参数的回调地址。"
        }
    }
}

struct FeishuOAuthTokenResponse: Decodable {
    let code: Int
    let msg: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case code
        case msg
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct FeishuPKCEPair: Equatable {
    let codeVerifier: String
    let codeChallenge: String
}

struct PendingFeishuAuthorizationAttempt: Equatable {
    let authorizationURL: URL
    let redirectURL: URL
    let state: String
}

private struct PendingFeishuAuthorizationContext: Equatable {
    let appID: String
    let redirectURI: String
    let codeVerifier: String
}

final class FeishuOAuthService: @unchecked Sendable {
    private let configurationStore: FeishuConfigurationStore
    private let keychainStore: KeychainStore
    private let session: URLSession
    private let pendingAuthorizationLock = NSLock()
    private var pendingAuthorizationContext: PendingFeishuAuthorizationContext?

    init(
        configurationStore: FeishuConfigurationStore = FeishuConfigurationStore(),
        keychainStore: KeychainStore = KeychainStore(),
        session: URLSession = .shared
    ) {
        self.configurationStore = configurationStore
        self.keychainStore = keychainStore
        self.session = session
    }

    func loadSnapshot() -> FeishuConnectionSnapshot {
        let credentialMetadata = configurationStore.loadCredentialMetadata()
        return FeishuConnectionSnapshot(
            configuration: configurationStore.load(),
            hasAppSecret: credentialMetadata.hasAppSecret,
            hasUserAccessToken: credentialMetadata.hasUserAccessToken,
            hasRefreshToken: credentialMetadata.hasRefreshToken
        )
    }

    func saveConfiguration(
        appID: String,
        appSecret: String?,
        redirectURI: String,
        targetChatID: String,
        aiSenderID: String,
        aiSenderType: String,
        scopes: String
    ) throws {
        let previousConfiguration = configurationStore.load()
        let trimmedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScopes = scopes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = appSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSecret.isEmpty {
            try keychainStore.save(trimmedSecret, account: .appSecret)
            try configurationStore.updateCredentialMetadata(hasAppSecret: true)
        }

        let authorizationConfigChanged = previousConfiguration.appID != trimmedAppID
            || previousConfiguration.redirectURI != trimmedRedirectURI
            || previousConfiguration.scopes != trimmedScopes
        if authorizationConfigChanged {
            clearPendingAuthorizationAttempt()
            try keychainStore.delete(account: .userAccessToken)
            try keychainStore.delete(account: .refreshToken)
            try configurationStore.clearAuthorizationMetadata()
        }

        let configuration = FeishuStoredConfiguration(
            appID: trimmedAppID,
            redirectURI: trimmedRedirectURI,
            targetChatID: targetChatID.trimmingCharacters(in: .whitespacesAndNewlines),
            aiSenderID: aiSenderID.trimmingCharacters(in: .whitespacesAndNewlines),
            aiSenderType: aiSenderType.trimmingCharacters(in: .whitespacesAndNewlines),
            scopes: trimmedScopes,
            tokenExpiresAt: authorizationConfigChanged ? nil : previousConfiguration.tokenExpiresAt
        )
        try configurationStore.save(configuration)
    }

    var hasPendingAuthorizationCodeExchange: Bool {
        pendingAuthorizationLock.withLock { pendingAuthorizationContext != nil }
    }

    func beginAuthorizationAttempt() throws -> PendingFeishuAuthorizationAttempt {
        let configuration = configurationStore.load()
        let appSecret: String?
        do {
            appSecret = try keychainStore.read(account: .appSecret)
        } catch let error as KeychainStoreError where error.isAuthenticationFailure {
            try configurationStore.updateCredentialMetadata(hasAppSecret: false)
            throw FeishuOAuthError.missingAppSecret
        }
        guard let appSecret, !appSecret.isEmpty else {
            try configurationStore.updateCredentialMetadata(hasAppSecret: false)
            throw FeishuOAuthError.missingAppSecret
        }
        try configurationStore.updateCredentialMetadata(hasAppSecret: true)

        let redirectURL = try validatedRedirectURL(configuration.redirectURI)
        let state = UUID().uuidString
        let pkcePair = Self.makePKCEPair()
        let authorizationURL = try Self.makeAuthorizationURL(
            configuration: configuration,
            state: state,
            codeChallenge: pkcePair.codeChallenge
        )
        pendingAuthorizationLock.withLock {
            pendingAuthorizationContext = PendingFeishuAuthorizationContext(
                appID: configuration.appID,
                redirectURI: configuration.redirectURI,
                codeVerifier: pkcePair.codeVerifier
            )
        }
        return PendingFeishuAuthorizationAttempt(
            authorizationURL: authorizationURL,
            redirectURL: redirectURL,
            state: state
        )
    }

    func authorize(timeout: TimeInterval = 120) async throws -> FeishuConnectionSnapshot {
        let attempt = try beginAuthorizationAttempt()
        let receiver = OAuthLoopbackReceiver(redirectURL: attempt.redirectURL, expectedState: attempt.state)

        return try await withTaskCancellationHandler {
            defer { receiver.cancel() }

            async let code = receiver.waitForAuthorizationCode(timeout: timeout)
            NSWorkspace.shared.open(attempt.authorizationURL)

            let authorizationCode = try await code
            return try await exchangePendingAuthorizationCode(authorizationCode)
        } onCancel: {
            receiver.cancel()
        }
    }

    func exchangePendingAuthorizationCode(_ rawInput: String) async throws -> FeishuConnectionSnapshot {
        let authorizationCode = try Self.extractAuthorizationCode(from: rawInput)
        let context = pendingAuthorizationLock.withLock { pendingAuthorizationContext }
        guard let context else {
            throw FeishuOAuthError.missingPendingAuthorization
        }
        guard let appSecret = try keychainStore.read(account: .appSecret), !appSecret.isEmpty else {
            try configurationStore.updateCredentialMetadata(hasAppSecret: false)
            throw FeishuOAuthError.missingAppSecret
        }
        try configurationStore.updateCredentialMetadata(hasAppSecret: true)

        let tokenResponse = try await exchangeAuthorizationCode(
            authorizationCode,
            appID: context.appID,
            appSecret: appSecret,
            redirectURI: context.redirectURI,
            codeVerifier: context.codeVerifier
        )
        try persistTokenResponse(tokenResponse, basedOn: configurationStore.load())
        clearPendingAuthorizationAttempt()
        return loadSnapshot()
    }

    func refreshUserAccessTokenIfNeeded(force: Bool = false) async throws -> FeishuConnectionSnapshot {
        let snapshot = loadSnapshot()
        if !snapshot.isConfigured {
            return snapshot
        }
        if !force, snapshot.hasValidUserAccessToken {
            return snapshot
        }

        guard let appSecret = try keychainStore.read(account: .appSecret), !appSecret.isEmpty else {
            try configurationStore.updateCredentialMetadata(hasAppSecret: false)
            throw FeishuOAuthError.missingAppSecret
        }
        try configurationStore.updateCredentialMetadata(hasAppSecret: true)

        guard let refreshToken = try keychainStore.read(account: .refreshToken), !refreshToken.isEmpty else {
            try clearExpiredAccessToken()
            throw FeishuOAuthError.missingRefreshToken
        }

        let configuration = configurationStore.load()
        do {
            let tokenResponse = try await refreshAccessToken(
                refreshToken,
                appID: configuration.appID,
                appSecret: appSecret,
                scopes: configuration.scopes
            )
            try persistTokenResponse(tokenResponse, basedOn: configuration)
            return loadSnapshot()
        } catch let error as FeishuOAuthError {
            switch error {
            case .reauthorizationRequired:
                _ = try clearAuthorization()
            case .tokenRefreshFailed:
                try clearExpiredAccessToken()
            default:
                break
            }
            throw error
        } catch {
            try clearExpiredAccessToken()
            throw FeishuOAuthError.tokenRefreshFailed(error.localizedDescription)
        }
    }

    func clearAuthorization() throws -> FeishuConnectionSnapshot {
        clearPendingAuthorizationAttempt()
        try keychainStore.delete(account: .userAccessToken)
        try keychainStore.delete(account: .refreshToken)
        try configurationStore.clearAuthorizationMetadata()
        return loadSnapshot()
    }

    static func makeAuthorizationURL(
        configuration: FeishuStoredConfiguration,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.feishu.cn/open-apis/authen/v1/authorize")
        let trimmedScopes = configuration.scopes.trimmingCharacters(in: .whitespacesAndNewlines)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.appID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: trimmedScopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else {
            throw FeishuOAuthError.invalidRedirectURI
        }
        return url
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        appID: String,
        appSecret: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> FeishuOAuthTokenResponse {
        guard let url = URL(string: "https://open.feishu.cn/open-apis/authen/v2/oauth/token") else {
            throw FeishuOAuthError.tokenExchangeFailed("token URL 无效")
        }

        let tokenResponse = try await performTokenRequest(
            url: url,
            body: Self.makeAuthorizationCodeExchangeBody(
                code: code,
                appID: appID,
                appSecret: appSecret,
                redirectURI: redirectURI,
                codeVerifier: codeVerifier
            ),
            failureWrapper: { FeishuOAuthError.tokenExchangeFailed($0) }
        )
        guard tokenResponse.code == 0 else {
            throw FeishuOAuthError.tokenExchangeFailed(tokenResponse.msg ?? "错误码 \(tokenResponse.code)")
        }
        return tokenResponse
    }

    static func makeAuthorizationCodeExchangeBody(
        code: String,
        appID: String,
        appSecret: String,
        redirectURI: String,
        codeVerifier: String
    ) -> [String: Any] {
        [
            "grant_type": "authorization_code",
            "client_id": appID,
            "client_secret": appSecret,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ]
    }

    static func extractAuthorizationCode(from rawInput: String) throws -> String {
        let trimmedInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw FeishuOAuthError.invalidManualAuthorizationInput
        }
        if let url = URL(string: trimmedInput) {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let code = queryItems.first(where: { $0.name == "code" })?.value,
               !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return code.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmedInput
    }

    private func refreshAccessToken(
        _ refreshToken: String,
        appID: String,
        appSecret: String,
        scopes: String
    ) async throws -> FeishuOAuthTokenResponse {
        guard let url = URL(string: "https://open.feishu.cn/open-apis/authen/v2/oauth/token") else {
            throw FeishuOAuthError.tokenRefreshFailed("token URL 无效")
        }

        var body: [String: Any] = [
            "grant_type": "refresh_token",
            "client_id": appID,
            "client_secret": appSecret,
            "refresh_token": refreshToken
        ]
        let trimmedScopes = scopes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedScopes.isEmpty {
            body["scope"] = trimmedScopes
        }

        let tokenResponse = try await performTokenRequest(
            url: url,
            body: body,
            failureWrapper: { FeishuOAuthError.tokenRefreshFailed($0) }
        )
        guard tokenResponse.code == 0 else {
            throw FeishuOAuthError.reauthorizationRequired(
                "飞书 token 刷新被拒绝：\(tokenResponse.msg ?? "错误码 \(tokenResponse.code)")。已清理本地旧授权，请重新授权。"
            )
        }
        guard tokenResponse.accessToken != nil, !(tokenResponse.accessToken ?? "").isEmpty else {
            throw FeishuOAuthError.reauthorizationRequired("飞书刷新响应缺少新的 user_access_token。已清理本地旧授权，请重新授权。")
        }
        return tokenResponse
    }

    private func performTokenRequest(
        url: URL,
        body: [String: Any],
        failureWrapper: (String) -> FeishuOAuthError
    ) async throws -> FeishuOAuthTokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw failureWrapper(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw failureWrapper("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(FeishuOAuthTokenResponse.self, from: data)
    }

    private func persistTokenResponse(
        _ tokenResponse: FeishuOAuthTokenResponse,
        basedOn configuration: FeishuStoredConfiguration
    ) throws {
        guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
            throw FeishuOAuthError.missingAccessToken
        }

        try keychainStore.save(accessToken, account: .userAccessToken)
        try configurationStore.updateCredentialMetadata(hasUserAccessToken: true)

        if let refreshToken = tokenResponse.refreshToken, !refreshToken.isEmpty {
            try keychainStore.save(refreshToken, account: .refreshToken)
            try configurationStore.updateCredentialMetadata(hasRefreshToken: true)
        } else {
            try keychainStore.delete(account: .refreshToken)
            try configurationStore.updateCredentialMetadata(hasRefreshToken: false)
        }

        var updatedConfiguration = configuration
        if let expiresIn = tokenResponse.expiresIn {
            updatedConfiguration.tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            updatedConfiguration.tokenExpiresAt = nil
        }
        try configurationStore.save(updatedConfiguration)
    }

    private func clearExpiredAccessToken() throws {
        try keychainStore.delete(account: .userAccessToken)
        try configurationStore.clearTokenMetadata()
        try configurationStore.updateCredentialMetadata(hasUserAccessToken: false)
    }

    private func clearPendingAuthorizationAttempt() {
        pendingAuthorizationLock.withLock {
            pendingAuthorizationContext = nil
        }
    }

    private func validatedRedirectURL(_ rawValue: String) throws -> URL {
        guard
            let url = URL(string: rawValue),
            url.scheme == "http",
            url.port != nil,
            let host = url.host(percentEncoded: false)
        else {
            throw FeishuOAuthError.invalidRedirectURI
        }

        guard host == "127.0.0.1" else {
            throw FeishuOAuthError.unsupportedRedirectHost(host)
        }
        guard !url.path.isEmpty, url.path != "/" else {
            throw FeishuOAuthError.invalidRedirectURI
        }
        return url
    }

    static func makePKCEPair() -> FeishuPKCEPair {
        let allowedCharacters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        let verifier = String(
            (0..<64).map { _ in
                allowedCharacters[Int.random(in: 0..<allowedCharacters.count, using: &generator)]
            }
        )
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return FeishuPKCEPair(codeVerifier: verifier, codeChallenge: challenge)
    }
}

private final class OAuthLoopbackReceiver: @unchecked Sendable {
    private let redirectURL: URL
    private let expectedState: String
    private let stateLock = NSLock()
    private var listeningSocketFD: Int32?
    private var clientSocketFD: Int32?
    private var isCancelled = false

    init(redirectURL: URL, expectedState: String) {
        self.redirectURL = redirectURL
        self.expectedState = expectedState
    }

    func cancel() {
        let sockets = stateLock.withLock { () -> [Int32] in
            guard !isCancelled else {
                return []
            }
            isCancelled = true
            let trackedSockets = [listeningSocketFD, clientSocketFD].compactMap { $0 }
            listeningSocketFD = nil
            clientSocketFD = nil
            return trackedSockets
        }

        for socketFD in sockets {
            _ = Darwin.shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
        }
    }

    func waitForAuthorizationCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let code = try self.blockingWaitForCode(timeout: timeout)
                    continuation.resume(returning: code)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func blockingWaitForCode(timeout: TimeInterval) throws -> String {
        if cancellationRequested {
            throw FeishuOAuthError.callbackCancelled
        }
        guard let port = redirectURL.port else {
            throw FeishuOAuthError.invalidRedirectURI
        }

        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw FeishuOAuthError.callbackServerFailed(String(cString: strerror(errno)))
        }
        try registerListeningSocket(socketFD)
        defer { closeTrackedListeningSocket(socketFD) }

        var reuse = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindStatus = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            if cancellationRequested {
                throw FeishuOAuthError.callbackCancelled
            }
            throw FeishuOAuthError.callbackServerFailed(String(cString: strerror(errno)))
        }

        guard listen(socketFD, 1) == 0 else {
            if cancellationRequested {
                throw FeishuOAuthError.callbackCancelled
            }
            throw FeishuOAuthError.callbackServerFailed(String(cString: strerror(errno)))
        }

        try waitForIncomingConnection(socketFD: socketFD, timeout: timeout)

        let clientFD = accept(socketFD, nil, nil)
        guard clientFD >= 0 else {
            if cancellationRequested {
                throw FeishuOAuthError.callbackCancelled
            }
            throw FeishuOAuthError.callbackServerFailed(String(cString: strerror(errno)))
        }
        try registerClientSocket(clientFD)
        defer { closeTrackedClientSocket(clientFD) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = read(clientFD, &buffer, buffer.count - 1)
        guard count > 0 else {
            if cancellationRequested {
                throw FeishuOAuthError.callbackCancelled
            }
            writeHTTPResponse(to: clientFD, status: "400 Bad Request", body: "Invalid OAuth callback request.")
            throw FeishuOAuthError.invalidCallbackRequest
        }

        let requestText = String(decoding: buffer.prefix(count), as: UTF8.self)
        let callbackResult = evaluateCallbackRequest(requestText)
        writeHTTPResponse(to: clientFD, status: callbackResult.status, body: callbackResult.body)
        if let error = callbackResult.error {
            throw error
        }
        return callbackResult.code
    }

    private func parseCode(from requestText: String) throws -> String {
        guard
            let requestLine = requestText.split(separator: "\r\n").first,
            let pathAndQuery = requestLine.split(separator: " ").dropFirst().first,
            let callbackURL = URL(string: "http://127.0.0.1\(pathAndQuery)")
        else {
            throw FeishuOAuthError.invalidCallbackRequest
        }

        let expectedPath = redirectURL.path.isEmpty ? "/" : redirectURL.path
        guard callbackURL.path == expectedPath else {
            throw FeishuOAuthError.invalidCallbackRequest
        }

        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let errorDescription = queryItems.first(where: { $0.name == "error_description" })?.value
            let message = [error, errorDescription].compactMap { value in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }.joined(separator: " - ")
            throw FeishuOAuthError.callbackError(message.isEmpty ? error : message)
        }

        guard queryItems.first(where: { $0.name == "state" })?.value == expectedState else {
            throw FeishuOAuthError.callbackError("state 校验失败，请重新发起授权。")
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw FeishuOAuthError.missingAuthorizationCode
        }
        return code
    }

    private func writeHTTPResponse(to clientFD: Int32, status: String, body: String) {
        let data = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r

        """
        _ = header.withCString { write(clientFD, $0, strlen($0)) }
        _ = data.withUnsafeBytes { rawBuffer in
            write(clientFD, rawBuffer.baseAddress, data.count)
        }
    }

    private var cancellationRequested: Bool {
        stateLock.withLock { isCancelled }
    }

    private func registerListeningSocket(_ socketFD: Int32) throws {
        let wasCancelled = stateLock.withLock {
            if isCancelled {
                return true
            }
            listeningSocketFD = socketFD
            return false
        }
        if wasCancelled {
            _ = Darwin.shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
            throw FeishuOAuthError.callbackCancelled
        }
    }

    private func registerClientSocket(_ socketFD: Int32) throws {
        let wasCancelled = stateLock.withLock {
            if isCancelled {
                return true
            }
            clientSocketFD = socketFD
            return false
        }
        if wasCancelled {
            _ = Darwin.shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
            throw FeishuOAuthError.callbackCancelled
        }
    }

    private func closeTrackedListeningSocket(_ socketFD: Int32) {
        let shouldClose = stateLock.withLock { () -> Bool in
            guard listeningSocketFD == socketFD else {
                return false
            }
            listeningSocketFD = nil
            return true
        }
        guard shouldClose else {
            return
        }
        _ = Darwin.shutdown(socketFD, SHUT_RDWR)
        close(socketFD)
    }

    private func closeTrackedClientSocket(_ socketFD: Int32) {
        let shouldClose = stateLock.withLock { () -> Bool in
            guard clientSocketFD == socketFD else {
                return false
            }
            clientSocketFD = nil
            return true
        }
        guard shouldClose else {
            return
        }
        _ = Darwin.shutdown(socketFD, SHUT_RDWR)
        close(socketFD)
    }

    private func waitForIncomingConnection(socketFD: Int32, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var descriptor = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)

        while true {
            if cancellationRequested {
                throw FeishuOAuthError.callbackCancelled
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                throw FeishuOAuthError.callbackTimeout
            }

            descriptor.revents = 0
            let waitMilliseconds = Int32(min(200, max(1, Int(ceil(remaining * 1_000)))))
            let pollStatus = Darwin.poll(&descriptor, 1, waitMilliseconds)
            if pollStatus > 0 {
                return
            }
            if pollStatus == 0 || errno == EINTR {
                continue
            }
            if cancellationRequested {
                throw FeishuOAuthError.callbackCancelled
            }
            throw FeishuOAuthError.callbackServerFailed(String(cString: strerror(errno)))
        }
    }

    private func evaluateCallbackRequest(_ requestText: String) -> CallbackEvaluation {
        do {
            let code = try parseCode(from: requestText)
            return CallbackEvaluation(
                status: "200 OK",
                body: "OAuth authorization completed. You can close this tab.",
                code: code,
                error: nil
            )
        } catch let error as FeishuOAuthError {
            return CallbackEvaluation(
                status: "400 Bad Request",
                body: error.localizedDescription,
                code: "",
                error: error
            )
        } catch {
            let wrappedError = FeishuOAuthError.invalidCallbackRequest
            return CallbackEvaluation(
                status: "400 Bad Request",
                body: wrappedError.localizedDescription,
                code: "",
                error: wrappedError
            )
        }
    }
}

private struct CallbackEvaluation {
    let status: String
    let body: String
    let code: String
    let error: FeishuOAuthError?
}
