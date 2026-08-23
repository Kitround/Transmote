import Foundation

// MARK: - Errors

nonisolated enum RPCError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case serverError(String)
    case decodingFailed(String)
    case networkError(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return String(localized: "Invalid server URL")
        case .authenticationFailed:    return String(localized: "Authentication failed")
        case .serverError(let msg):    return String(localized: "Server error: \(msg)")
        case .decodingFailed(let msg): return String(localized: "Decoding error: \(msg)")
        case .networkError(let msg):   return String(localized: "Network error: \(msg)")
        case .notConnected:            return String(localized: "Not connected to a server")
        }
    }
}

// MARK: - AnyCodable

/// Type-erased RPC argument value. Encode-only: responses are decoded into
/// concrete types, never through this.
nonisolated struct AnyCodable: Encodable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool:         try c.encode(v)
        case let v as Int:          try c.encode(v)
        case let v as Double:       try c.encode(v)
        case let v as String:       try c.encode(v)
        case let v as [Int]:        try c.encode(v)
        case let v as [String]:     try c.encode(v)
        default:                    try c.encodeNil()
        }
    }
}

// MARK: - Empty arguments

/// Response body for calls that return nothing useful. Decodes anything.
nonisolated struct EmptyArguments: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

// MARK: - Request / Response envelopes

nonisolated struct RPCRequest: Encodable, Sendable {
    let method: String
    var arguments: [String: AnyCodable]?
}

nonisolated struct RPCResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let result: String
    let arguments: T?

    var isSuccess: Bool { result == "success" }
}

// MARK: - RPCClient

actor RPCClient {
    private let serverConfig: ServerConfig
    private var sessionID: String = ""
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(config: ServerConfig) {
        self.serverConfig = config
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        cfg.urlCache = nil
        cfg.urlCredentialStorage = nil
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: cfg)
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    // MARK: - Core request

    func request<T: Decodable & Sendable>(
        method: String,
        arguments: [String: AnyCodable]? = nil,
        responseType: T.Type
    ) async throws -> RPCResponse<T> {
        guard let url = serverConfig.rpcURL else { throw RPCError.invalidURL }

        let bodyData: Data
        do {
            bodyData = try encoder.encode(RPCRequest(method: method, arguments: arguments))
        } catch {
            throw RPCError.serverError("Encoding: \(error)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")

        if let user = serverConfig.username, !user.isEmpty,
           let pass = serverConfig.password,
           let encoded = "\(user):\(pass)".data(using: .utf8)?.base64EncodedString() {
            req.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        return try await send(req, responseType: T.self, isRetry: false)
    }

    private func send<T: Decodable & Sendable>(
        _ req: URLRequest,
        responseType: T.Type,
        isRetry: Bool
    ) async throws -> RPCResponse<T> {
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await urlSession.data(for: req)
        } catch {
            throw RPCError.networkError(error.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw RPCError.serverError("Non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            return try decode(data, as: T.self)
        case 401, 403:
            throw RPCError.authenticationFailed
        case 409:
            guard !isRetry else { throw RPCError.serverError("Invalid session ID after retry") }
            if let id = http.value(forHTTPHeaderField: "X-Transmission-Session-Id") {
                sessionID = id
            }
            var retry = req
            retry.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
            return try await send(retry, responseType: T.self, isRetry: true)
        default:
            throw RPCError.serverError("HTTP \(http.statusCode)")
        }
    }

    private func decode<T: Decodable & Sendable>(_ data: Data, as type: T.Type) throws -> RPCResponse<T> {
        do {
            return try decoder.decode(RPCResponse<T>.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw RPCError.decodingFailed("\(error) — raw: \(raw.prefix(300))")
        }
    }

    func testConnection() async throws {
        _ = try await getSession()
    }
}
