import Foundation

enum GarminError: LocalizedError {
    case http(Int, String)
    case rateLimited(retryAfter: TimeInterval?, body: String)
    case badToken

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            let hint = code == 401 || code == 403 ? " (API key invalid, expired or revoked?)" : ""
            return "HTTP \(code)\(hint) \(body.prefix(160))"
        case .rateLimited(_, let body): return "Garmin rate limit reached. \(body.prefix(140))"
        case .badToken: return "Token endpoint returned an unexpected response"
        }
    }
}

/// Garmin Connect Personal API: exchange the personal API key for a 24h bearer JWT, then GET data.
actor GarminClient {
    static let base = URL(string: "https://personal.connectapi.garmin.com")!
    private let apiKey: String
    private var token: (value: String, exp: Date)?

    init(apiKey: String) { self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func bearer(force: Bool = false) async throws -> String {
        if !force, let t = token, t.exp.timeIntervalSinceNow > 300 { return t.value }
        var req = URLRequest(url: Self.base.appendingPathComponent("personalapitoken-service/personal-api/personal-api-key/token"))
        req.httpMethod = "POST"
        req.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Self.failure(code, data, resp) }
        var text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Be tolerant if the body is JSON like {"access_token": "..."}
        if text.hasPrefix("{"),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let t = (obj["access_token"] ?? obj["token"]) as? String { text = t }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard !text.isEmpty else { throw GarminError.badToken }
        token = (text, Self.expiry(of: text) ?? Date().addingTimeInterval(3600 * 12))
        return text
    }

    /// Garmin answers with HTTP 439 (and sometimes 429) plus a `rateLimitMetaData` body when the request quota is used up.
    private static func failure(_ code: Int, _ data: Data, _ resp: URLResponse?) -> GarminError {
        let body = String(data: data, encoding: .utf8) ?? ""
        if code == 429 || code == 439 || body.range(of: "ratelimit", options: .caseInsensitive) != nil {
            let ra = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            return .rateLimited(retryAfter: ra, body: body)
        }
        return .http(code, body)
    }

    private static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let d = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        for attempt in 0..<2 {
            let t = try await bearer(force: attempt == 1)
            var comps = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
            comps.path = path
            if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 45
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 && attempt == 0 { continue }
            guard (200..<300).contains(code) else { throw Self.failure(code, data, resp) }
            return data
        }
        throw GarminError.badToken
    }

    /// Verifies the key by requesting a token.
    func verify() async throws { _ = try await bearer(force: true) }
}
