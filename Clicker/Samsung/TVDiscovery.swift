import Foundation
import Network
import Observation

/// Finds Samsung TVs on the local network.
///
/// Samsung TVs from 2018 on advertise AirPlay (`_airplay._tcp`), which iOS lets us browse without any
/// special entitlement. Every AirPlay device we see is then asked for `http://<ip>:8001/api/v2/`;
/// only Samsung TVs answer that. Discovery misses TVs that are fully asleep; those can be added by IP.
@MainActor
@Observable
final class TVDiscovery {
    private(set) var found: [TV] = []
    private(set) var isScanning = false

    private var browser: NWBrowser?
    private var probed: Set<String> = []

    func start() {
        stop()
        found = []
        probed = []
        isScanning = true

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: "_airplay._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for result in results {
                    self.probe(result.endpoint)
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .failed = state { self?.isScanning = false }
            }
        }
        self.browser = browser
        browser.start(queue: .global(qos: .utility))
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    /// Validates a host typed by hand. Returns nil when nothing Samsung-like answers.
    static func lookup(host: String) async -> TV? {
        guard let info = try? await TVDeviceInfo.fetch(host: host), info.looksLikeSamsungTV else { return nil }
        return TV(id: info.stableID, name: info.cleanName, model: info.device.modelName,
                  host: info.device.ip ?? host, mac: info.device.wifiMac)
    }

    private func probe(_ endpoint: NWEndpoint) {
        let key = "\(endpoint)"
        guard !probed.contains(key) else { return }
        probed.insert(key)

        // Resolve the Bonjour name to an IPv4 address by opening a connection to it and reading the
        // remote endpoint. Cheap, and it needs no deprecated API.
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if case .hostPort(let host, _)? = connection.currentPath?.remoteEndpoint {
                    let address = Self.string(for: host)
                    connection.cancel()
                    Task { @MainActor [weak self] in await self?.check(address) }
                } else {
                    connection.cancel()
                }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
    }

    private func check(_ address: String) async {
        guard !address.isEmpty, !found.contains(where: { $0.host == address }) else { return }
        guard let tv = await Self.lookup(host: address) else { return }
        if !found.contains(where: { $0.id == tv.id }) {
            found.append(tv)
            found.sort { $0.name < $1.name }
        }
    }

    nonisolated private static func string(for host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        case .name(let name, _):
            return name
        @unknown default:
            return ""
        }
    }
}
