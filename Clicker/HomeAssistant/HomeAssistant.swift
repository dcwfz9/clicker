import Foundation

/// Optional bridge: let Home Assistant handle power when the TV cannot be reached directly
/// (deep sleep, a different network, a smart plug, an IR blaster). Any entity that can be turned on works.
struct HomeAssistantConfig: Codable, Equatable {
    var enabled = false
    var url = ""
    var entityID = ""

    static let tokenAccount = "homeassistant.token"

    var isUsable: Bool {
        enabled && baseURL != nil && !entityID.isEmpty && !(Keychain.string(for: Self.tokenAccount) ?? "").isEmpty
    }

    var baseURL: URL? {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}

struct HAEntity: Identifiable, Hashable {
    let id: String
    let name: String
    let state: String

    var domain: String { String(id.split(separator: ".").first ?? "") }
}

enum HomeAssistant {
    static let powerDomains: Set<String> = ["media_player", "remote", "switch", "script", "button", "scene", "input_boolean"]

    static func turnOn(_ config: HomeAssistantConfig) async throws {
        let domain = String(config.entityID.split(separator: ".").first ?? "")
        let service = domain == "button" ? "press" : "turn_on"
        try await call(config, domain: domain, service: service)
    }

    /// Only entities that have an "off" (a script or button has none).
    static func canTurnOff(_ config: HomeAssistantConfig) -> Bool {
        let domain = String(config.entityID.split(separator: ".").first ?? "")
        return ["media_player", "remote", "switch", "input_boolean"].contains(domain)
    }

    static func turnOff(_ config: HomeAssistantConfig) async throws {
        let domain = String(config.entityID.split(separator: ".").first ?? "")
        try await call(config, domain: domain, service: "turn_off")
    }

    static func entities(_ config: HomeAssistantConfig) async throws -> [HAEntity] {
        guard let base = config.baseURL else { throw URLError(.badURL) }
        let data = try await request(config, url: base.appending(path: "api/states"), body: nil)
        let states = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return states.compactMap { item in
            guard let id = item["entity_id"] as? String else { return nil }
            let domain = String(id.split(separator: ".").first ?? "")
            guard powerDomains.contains(domain) else { return nil }
            let attributes = item["attributes"] as? [String: Any] ?? [:]
            return HAEntity(id: id, name: attributes["friendly_name"] as? String ?? id, state: item["state"] as? String ?? "")
        }
        .sorted { ($0.domain, $0.name) < ($1.domain, $1.name) }
    }

    static func check(_ config: HomeAssistantConfig) async throws -> String {
        guard let base = config.baseURL else { throw URLError(.badURL) }
        let data = try await request(config, url: base.appending(path: "api/"), body: nil)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["message"] as? String ?? "OK"
    }

    private static func call(_ config: HomeAssistantConfig, domain: String, service: String) async throws {
        guard let base = config.baseURL, !domain.isEmpty else { throw URLError(.badURL) }
        let body = try JSONSerialization.data(withJSONObject: ["entity_id": config.entityID])
        _ = try await request(config, url: base.appending(path: "api/services/\(domain)/\(service)"), body: body)
    }

    private static func request(_ config: HomeAssistantConfig, url: URL, body: Data?) async throws -> Data {
        guard let token = Keychain.string(for: HomeAssistantConfig.tokenAccount), !token.isEmpty else {
            throw HomeAssistantError.missingToken
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw HomeAssistantError.unauthorized
        case 404: throw HomeAssistantError.notFound
        default: throw HomeAssistantError.status(http.statusCode)
        }
    }
}

enum HomeAssistantError: LocalizedError {
    case missingToken
    case unauthorized
    case notFound
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Add a Home Assistant token first."
        case .unauthorized: return "Home Assistant rejected the token."
        case .notFound: return "Home Assistant could not find that."
        case .status(let code): return "Home Assistant answered with status \(code)."
        }
    }
}
