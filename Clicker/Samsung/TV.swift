import Foundation

/// A TV the user has added. Stored in UserDefaults; the pairing token lives in the Keychain under `id`.
struct TV: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var model: String?
    var host: String
    var mac: String?

    var displayModel: String {
        model ?? "Samsung TV"
    }
}

/// What the TV reports at `http://<host>:8001/api/v2/`. Answers in standby too, which is how we tell
/// "standby" (wake it over the network) from "unplugged or asleep" (nothing we can do).
struct TVDeviceInfo: Decodable {
    struct Device: Decodable {
        let name: String?
        let modelName: String?
        let type: String?
        let id: String?
        let ip: String?
        let wifiMac: String?
        let networkType: String?
        let TokenAuthSupport: String?
        let PowerState: String?
    }

    let device: Device
    let id: String?

    var isOn: Bool { device.PowerState?.lowercased() == "on" }

    /// Samsung HTML-escapes the name (`65&quot; QLED`).
    var cleanName: String {
        let raw = device.name ?? "Samsung TV"
        return raw
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    var stableID: String {
        if let id = device.id, !id.isEmpty { return id }
        if let id = id, !id.isEmpty { return id }
        return device.ip ?? UUID().uuidString
    }

    var looksLikeSamsungTV: Bool {
        (device.type ?? "").localizedCaseInsensitiveContains("samsung") || device.modelName != nil
    }

    static func fetch(host: String, timeout: TimeInterval = 2.5) async throws -> TVDeviceInfo {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(TVDeviceInfo.self, from: data)
    }
}

/// An app installed on the TV (from `ed.installedApp.get`).
struct TVApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let appType: Int

    /// A few well-known Tizen app ids, used until the TV tells us what it has installed.
    static let common: [TVApp] = [
        TVApp(id: "3201907018807", name: "Netflix", appType: 2),
        TVApp(id: "111299001912", name: "YouTube", appType: 2),
        TVApp(id: "3201910019365", name: "Prime Video", appType: 2),
        TVApp(id: "3201901017640", name: "Disney+", appType: 2),
        TVApp(id: "3201807016597", name: "Apple TV", appType: 2),
        TVApp(id: "3201601007625", name: "Hulu", appType: 2),
        TVApp(id: "3201606009684", name: "Spotify", appType: 2),
        TVApp(id: "3201512006963", name: "Plex", appType: 2),
        TVApp(id: "3201504001965", name: "Tubi", appType: 2),
    ]
}
