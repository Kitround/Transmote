// swiftlint:disable all
import Foundation

// MARK: - Errors

enum RPCError: LocalizedError {
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

struct AnyCodable: Codable, Sendable {
    nonisolated(unsafe) let value: Any

    nonisolated init(_ value: Any) { self.value = value }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool:         try c.encode(v)
        case let v as Int:          try c.encode(v)
        case let v as Double:       try c.encode(v)
        case let v as String:       try c.encode(v)
        case let v as [Int]:        try c.encode(v)
        case let v as [String]:     try c.encode(v)
        case let v as [AnyCodable]: try c.encode(v)
        default:                    try c.encodeNil()
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if      let v = try? c.decode(Bool.self)   { value = v }
        else if let v = try? c.decode(Int.self)    { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else                                       { value = 0 }
    }
}

// MARK: - EmptyArguments

struct EmptyArguments: Codable, Sendable {
    nonisolated init() {}
    nonisolated init(from decoder: Decoder) throws {}
    nonisolated func encode(to encoder: Encoder) throws {}
}

// MARK: - RPCRequest

struct RPCRequest: Encodable, Sendable {
    let method: String
    let arguments: [String: AnyCodable]?
    let tag: Int?

    nonisolated init(method: String, arguments: [String: AnyCodable]? = nil, tag: Int? = nil) {
        self.method = method; self.arguments = arguments; self.tag = tag
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(method, forKey: .method)
        try c.encodeIfPresent(arguments, forKey: .arguments)
        try c.encodeIfPresent(tag, forKey: .tag)
    }

    enum CodingKeys: String, CodingKey { case method, arguments, tag }
}

// MARK: - RPCResponse

struct RPCResponse<T: Decodable>: Decodable, Sendable where T: Sendable {
    let result: String
    let arguments: T?
    let tag: Int?
    nonisolated var isSuccess: Bool { result == "success" }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result    = try c.decode(String.self, forKey: .result)
        arguments = try c.decodeIfPresent(T.self, forKey: .arguments)
        tag       = try c.decodeIfPresent(Int.self, forKey: .tag)
    }

    enum CodingKeys: String, CodingKey { case result, arguments, tag }
}

// MARK: - RPCClient

actor RPCClient {
    private let serverConfig: ServerConfig
    private var sessionID: String = ""
    private let urlSession: URLSession

    init(config: ServerConfig) {
        self.serverConfig = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: cfg)
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
            bodyData = try JSONEncoder().encode(RPCRequest(method: method, arguments: arguments))
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
            if let id = http.allHeaderFields["X-Transmission-Session-Id"] as? String {
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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(RPCResponse<T>.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw RPCError.decodingFailed("\(error) — raw: \(raw.prefix(300))")
        }
    }

    func testConnection() async throws {
        let _: RPCResponse<SessionArguments> = try await request(
            method: "session-get", responseType: SessionArguments.self)
    }
}
