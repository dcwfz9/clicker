import Foundation
import Observation

/// Everything the remote screen needs: the saved TVs, which one is active, whether it is on, and the
/// live remote-control channel to it.
@MainActor
@Observable
final class AppModel {
    enum Power: Equatable {
        case unknown   // no TV selected, or not checked yet
        case off       // nothing answers at the saved address
        case standby   // the TV answers but the screen is off
        case on
        case waking
    }

    private(set) var tvs: [TV] = []
    private(set) var selectedID: String?
    var homeAssistant = HomeAssistantConfig() {
        didSet { if homeAssistant != oldValue { save() } }
    }
    private(set) var power: Power = .unknown
    private(set) var notice: String?

    let remote = SamsungRemote()
    let discovery = TVDiscovery()

    private var monitor: Task<Void, Never>?
    private var unreachableChecks = 0
    private let defaults = UserDefaults.standard

    private enum Key {
        static let tvs = "tvs"
        static let selected = "selectedTV"
        static let homeAssistant = "homeAssistant"
    }

    init() {
        load()
        debugLog("loaded \(tvs.count) TV(s), selected \(selectedID ?? "none"), args \(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
        remote.onToken = { [weak self] token in
            guard let self, let tv = self.selectedTV else { return }
            Keychain.set(token, for: Self.tokenAccount(tv))
        }
    }

    var selectedTV: TV? {
        tvs.first { $0.id == selectedID }
    }

    var isConnected: Bool {
        remote.isConnected && power == .on
    }

    /// One line for the header.
    var statusText: String {
        guard selectedTV != nil else { return "No TV yet" }
        switch remote.state {
        case .pairing:
            return "Allow Clicker on the TV"
        case .denied:
            return "Pairing was declined"
        case .failed(let message):
            if power == .on { return message }
        default:
            break
        }
        switch power {
        case .unknown: return "Looking for the TV"
        case .off: return "Off"
        case .standby: return "Standby"
        case .waking: return "Waking up"
        case .on: return remote.isConnected ? "Connected" : "Connecting"
        }
    }

    // MARK: Lifecycle

    func activate() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let seconds: Int
                if !self.isVisible {
                    seconds = 30
                } else {
                    seconds = self.remote.isConnected ? 10 : 3
                }
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    /// On the Mac the remote lives in a menu bar popover; while it is closed, keep the connection but
    /// check on the TV only now and then.
    private(set) var isVisible = true

    func setVisible(_ visible: Bool) {
        isVisible = visible
        guard visible else { return }
        if monitor == nil {
            activate()
        } else {
            Task { await refresh() }
        }
    }

    func deactivate() {
        monitor?.cancel()
        monitor = nil
        remote.disconnect()
        discovery.stop()
    }

    // MARK: TVs

    func add(_ tv: TV, select: Bool = true) {
        if let index = tvs.firstIndex(where: { $0.id == tv.id }) {
            tvs[index].host = tv.host
            tvs[index].name = tv.name
            tvs[index].model = tv.model ?? tvs[index].model
            tvs[index].mac = tv.mac ?? tvs[index].mac
        } else {
            tvs.append(tv)
        }
        if select { self.select(tv.id) }
        save()
    }

    func select(_ id: String) {
        guard id != selectedID else { return }
        remote.disconnect()
        selectedID = id
        power = .unknown
        notice = nil
        save()
        Task { await refresh() }
    }

    func remove(_ tv: TV) {
        Keychain.set(nil, for: Self.tokenAccount(tv))
        tvs.removeAll { $0.id == tv.id }
        if selectedID == tv.id {
            remote.disconnect()
            selectedID = tvs.first?.id
            power = .unknown
        }
        save()
    }

    func update(_ tv: TV) {
        guard let index = tvs.firstIndex(where: { $0.id == tv.id }) else { return }
        let hostChanged = tvs[index].host != tv.host
        tvs[index] = tv
        save()
        if tv.id == selectedID, hostChanged {
            remote.disconnect()
            power = .unknown
            Task { await refresh() }
        }
    }

    func forgetPairing(_ tv: TV) {
        Keychain.set(nil, for: Self.tokenAccount(tv))
        if tv.id == selectedID { remote.disconnect() }
    }

    func hasPairing(_ tv: TV) -> Bool {
        !(Keychain.string(for: Self.tokenAccount(tv)) ?? "").isEmpty
    }

    /// Re-run pairing (shows the prompt on the TV again).
    func pair() {
        guard let tv = selectedTV else { return }
        notice = nil
        remote.connect(host: tv.host, token: nil)
    }

    // MARK: Keys

    func press(_ key: RemoteKey, action: KeyAction = .click) {
        if key == .power {
            if action == .click { Task { await togglePower() } }
            return
        }
        guard remote.isConnected else {
            if power == .on { connectIfNeeded() }
            return
        }
        remote.send(key, action: action)
    }

    func togglePower() async {
        guard let tv = selectedTV else { return }
        notice = nil
        if power == .on {
            if remote.isConnected {
                remote.send(.power)
                try? await Task.sleep(for: .seconds(2))
                await refresh()
            } else if homeAssistant.isUsable, HomeAssistant.canTurnOff(homeAssistant) {
                do { try await HomeAssistant.turnOff(homeAssistant) } catch { notice = error.localizedDescription }
            } else {
                connectIfNeeded()
            }
            return
        }
        await wake(tv)
    }

    private func wake(_ tv: TV) async {
        power = .waking
        defer { if power == .waking { power = .off } }

        if let mac = tv.mac {
            WakeOnLAN.wake(mac: mac, host: tv.host)
        }

        // Network standby: the TV still runs its remote channel, and a paired client can press power.
        let reachable = (try? await TVDeviceInfo.fetch(host: tv.host)) != nil
        if reachable, let token = Keychain.string(for: Self.tokenAccount(tv)), !token.isEmpty {
            if !remote.isConnected {
                remote.connect(host: tv.host, token: token)
                _ = await waitForConnection(seconds: 5)
            }
            if remote.isConnected { remote.send(.power) }
        }

        if homeAssistant.isUsable {
            do { try await HomeAssistant.turnOn(homeAssistant) } catch { notice = error.localizedDescription }
        } else if !reachable {
            notice = tv.mac == nil
                ? "The TV is not answering. It has to be on once so Clicker can learn its address."
                : "The TV is not answering. If it does not wake, Home Assistant can turn it on (Settings)."
        }

        for _ in 0..<20 {
            try? await Task.sleep(for: .seconds(2))
            if let info = try? await TVDeviceInfo.fetch(host: tv.host), info.isOn {
                power = .on
                notice = nil
                connectIfNeeded()
                return
            }
        }
        power = .off
        await refresh()
    }

    private func waitForConnection(seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if remote.isConnected { return true }
            if case .denied = remote.state { return false }
            if case .failed = remote.state { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return remote.isConnected
    }

    // MARK: Monitoring

    func refresh() async {
        guard let tv = selectedTV else {
            power = .unknown
            return
        }
        guard power != .waking else { return }
        debugLog("refresh: asking \(tv.host)")

        do {
            let info = try await TVDeviceInfo.fetch(host: tv.host)
            unreachableChecks = 0
            absorb(info, into: tv)
            if info.isOn {
                power = .on
                connectIfNeeded()
            } else {
                power = .standby
            }
        } catch {
            debugLog("status fetch failed for \(tv.host): \(error.localizedDescription)")
            power = .off
            if remote.isConnected { remote.disconnect() }
            unreachableChecks += 1
            if unreachableChecks % 5 == 1 { await rediscover(tv) }
        }
    }

    /// The TV reports its own address, MAC and name; keep ours current (DHCP moves TVs around).
    private func absorb(_ info: TVDeviceInfo, into tv: TV) {
        guard let index = tvs.firstIndex(where: { $0.id == tv.id }) else { return }
        var updated = tvs[index]
        if let mac = info.device.wifiMac, !mac.isEmpty { updated.mac = mac }
        if let model = info.device.modelName, !model.isEmpty { updated.model = model }
        updated.name = info.cleanName
        if updated != tvs[index] {
            tvs[index] = updated
            save()
        }
    }

    /// When the saved address stops answering, look for the same TV elsewhere on the network.
    private func rediscover(_ tv: TV) async {
        discovery.start()
        try? await Task.sleep(for: .seconds(4))
        discovery.stop()
        guard let match = discovery.found.first(where: { $0.id == tv.id }), match.host != tv.host else { return }
        var moved = tv
        moved.host = match.host
        update(moved)
        notice = nil
    }

    private func connectIfNeeded() {
        guard let tv = selectedTV else { return }
        switch remote.state {
        case .connected, .connecting, .pairing, .denied:
            return
        case .disconnected, .failed:
            let token = Keychain.string(for: Self.tokenAccount(tv))
            debugLog("connecting to \(tv.host), token: \(token == nil ? "none" : "present")")
            remote.connect(host: tv.host, token: token)
            sendTestKeysWhenConnected()
        }
    }

    /// Debug builds accept `-ClickerTestKeys KEY_INFO,KEY_INFO` as launch arguments (for example from
    /// `xcrun simctl launch`) and press those keys once after connecting, so a build can be checked
    /// against a real TV without touching the screen.
    private func sendTestKeysWhenConnected() {
        #if DEBUG
        guard let list = UserDefaults.standard.string(forKey: "ClickerTestKeys"), !list.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: "ClickerTestKeys")
        Task {
            let connected = await waitForConnection(seconds: 8)
            debugLog("test keys \(list): connection \(connected ? "ready" : "not ready, state \(remote.state)")")
            guard connected else { return }
            for name in list.split(separator: ",") {
                if let key = RemoteKey(rawValue: String(name).trimmingCharacters(in: .whitespaces)) {
                    remote.send(key)
                    debugLog("sent \(key.rawValue)")
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        #endif
    }

    // MARK: Persistence

    private static func tokenAccount(_ tv: TV) -> String {
        "tv.token.\(tv.id)"
    }

    private func load() {
        if let data = defaults.data(forKey: Key.tvs), let saved = try? JSONDecoder().decode([TV].self, from: data) {
            tvs = saved
        }
        selectedID = defaults.string(forKey: Key.selected) ?? tvs.first?.id
        if let data = defaults.data(forKey: Key.homeAssistant),
           let config = try? JSONDecoder().decode(HomeAssistantConfig.self, from: data) {
            homeAssistant = config
        }
        if tvs.isEmpty { seedFromBundle() }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(tvs), forKey: Key.tvs)
        defaults.set(selectedID, forKey: Key.selected)
        defaults.set(try? JSONEncoder().encode(homeAssistant), forKey: Key.homeAssistant)
    }

    /// Development builds can ship with a TV already set up (see Local.xcconfig). App Store builds have none.
    private func seedFromBundle() {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            guard let text = info[key] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let host = value("ClickerSeedHost") {
            let tv = TV(id: value("ClickerSeedID") ?? host,
                        name: value("ClickerSeedName") ?? "Samsung TV",
                        model: value("ClickerSeedModel"),
                        host: host,
                        mac: value("ClickerSeedMAC"))
            tvs = [tv]
            selectedID = tv.id
            if let token = value("ClickerSeedToken") {
                Keychain.set(token, for: Self.tokenAccount(tv))
            }
        }
        if let url = value("ClickerSeedHAURL"), let entity = value("ClickerSeedHAEntity") {
            homeAssistant = HomeAssistantConfig(enabled: true, url: url, entityID: entity)
            if let token = value("ClickerSeedHAToken") {
                Keychain.set(token, for: HomeAssistantConfig.tokenAccount)
            }
        }
        save()
    }
}
