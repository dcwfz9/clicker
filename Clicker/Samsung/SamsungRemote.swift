import Foundation
import Observation

/// The remote-control WebSocket channel of a Samsung Tizen TV
/// (`wss://<host>:8002/api/v2/channels/samsung.remote.control`).
///
/// First connection without a token makes the TV show an "Allow <name>?" prompt; the answer comes back
/// as `ms.channel.connect` with a token we keep for every later connection.
@MainActor
@Observable
final class SamsungRemote {
    enum State: Equatable {
        case disconnected
        case connecting
        case pairing          // no token yet, waiting for the prompt on the TV
        case connected
        case denied           // the prompt was declined (or timed out)
        case failed(String)
    }

    private(set) var state: State = .disconnected
    private(set) var host: String?
    /// True between `ms.remote.imeStart` and `ms.remote.imeEnd`: the TV has a text field focused.
    private(set) var tvWantsText = false

    /// Called with a fresh token when the TV hands one out.
    var onToken: ((String) -> Void)?

    private let clientName: String
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var proxy: DelegateProxy?
    private var appsContinuation: CheckedContinuation<[TVApp], Error>?

    init(clientName: String = "Clicker") {
        self.clientName = clientName
    }

    var isConnected: Bool { state == .connected }

    // MARK: Connection

    func connect(host: String, token: String?) {
        disconnect()
        self.host = host

        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var items = [URLQueryItem(name: "name", value: Data(clientName.utf8).base64EncodedString())]
        if let token, !token.isEmpty {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items
        guard let url = components.url else {
            state = .failed("Bad address")
            return
        }

        let proxy = DelegateProxy(owner: self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: proxy, delegateQueue: nil)
        let task = session.webSocketTask(with: url)

        self.proxy = proxy
        self.session = session
        self.task = task
        state = token == nil ? .pairing : .connecting
        task.resume()
        receive(on: task)
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
        proxy = nil
        tvWantsText = false
        appsContinuation?.resume(throwing: CancellationError())
        appsContinuation = nil
        if state != .denied { state = .disconnected }
    }

    // MARK: Sending

    func send(_ key: RemoteKey, action: KeyAction = .click) {
        send(json: [
            "method": "ms.remote.control",
            "params": [
                "Cmd": action.rawValue,
                "DataOfCmd": key.rawValue,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ])
    }

    /// Types into whatever text field the TV has focused, then closes the keyboard.
    func sendText(_ text: String) {
        send(json: [
            "method": "ms.remote.control",
            "params": [
                "Cmd": Data(text.utf8).base64EncodedString(),
                "DataOfCmd": "base64",
                "TypeOfRemote": "SendInputString",
            ],
        ])
        send(json: [
            "method": "ms.remote.control",
            "params": ["TypeOfRemote": "SendInputEnd"],
        ])
    }

    func launch(_ app: TVApp) {
        send(json: [
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": [
                    "action_type": app.appType == 2 ? "DEEP_LINK" : "NATIVE_LAUNCH",
                    "appId": app.id,
                    "metaTag": "",
                ],
            ],
        ])
    }

    /// Asks the TV for its installed apps. Times out after a few seconds.
    func installedApps() async throws -> [TVApp] {
        guard isConnected else { throw URLError(.notConnectedToInternet) }
        appsContinuation?.resume(throwing: CancellationError())
        appsContinuation = nil
        send(json: [
            "method": "ms.channel.emit",
            "params": ["event": "ed.installedApp.get", "to": "host"],
        ])
        return try await withCheckedThrowingContinuation { continuation in
            appsContinuation = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard let self, self.appsContinuation != nil else { return }
                self.appsContinuation?.resume(throwing: URLError(.timedOut))
                self.appsContinuation = nil
            }
        }
    }

    private func send(json: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in self?.fail(error) }
        }
    }

    // MARK: Receiving

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.task === task else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handle(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handle(text) }
                    @unknown default:
                        break
                    }
                    self.receive(on: task)
                case .failure(let error):
                    self.fail(error)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return }
        let payload = object["data"] as? [String: Any] ?? [:]

        switch event {
        case "ms.channel.connect":
            if let token = payload["token"] {
                let string = "\(token)"
                if !string.isEmpty { onToken?(string) }
            }
            state = .connected

        case "ms.channel.unauthorized":
            state = .denied
            task?.cancel(with: .normalClosure, reason: nil)

        case "ms.channel.timeOut":
            state = .denied
            task?.cancel(with: .normalClosure, reason: nil)

        case "ms.remote.imeStart":
            tvWantsText = true

        case "ms.remote.imeEnd", "ms.remote.imeDone":
            tvWantsText = false

        case "ed.installedApp.get":
            let list = (payload["data"] as? [[String: Any]] ?? []).compactMap { item -> TVApp? in
                guard let id = item["appId"] as? String, let name = item["name"] as? String else { return nil }
                return TVApp(id: id, name: name, appType: item["app_type"] as? Int ?? 2)
            }
            appsContinuation?.resume(returning: list)
            appsContinuation = nil

        case "ms.error":
            let message = payload["message"] as? String ?? "TV reported an error"
            state = .failed(message)

        default:
            break
        }
    }

    fileprivate func fail(_ error: Error) {
        guard state != .denied else { return }
        let code = (error as? URLError)?.code
        if code == .cancelled {
            if state == .connected || state == .connecting || state == .pairing { state = .disconnected }
        } else {
            state = .failed(error.localizedDescription)
        }
        task = nil
        tvWantsText = false
        appsContinuation?.resume(throwing: error)
        appsContinuation = nil
    }

    fileprivate func closed() {
        if state == .connected || state == .connecting { state = .disconnected }
        if state == .pairing { state = .denied }
        task = nil
        tvWantsText = false
    }

    // MARK: URLSession delegate (the TV uses a self-signed certificate)

    private final class DelegateProxy: NSObject, URLSessionWebSocketDelegate {
        weak var owner: SamsungRemote?

        init(owner: SamsungRemote) {
            self.owner = owner
        }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            Task { @MainActor [weak owner] in owner?.closed() }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            Task { @MainActor [weak owner] in owner?.fail(error) }
        }
    }
}
