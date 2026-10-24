import Foundation
import Network

/// Wake-on-LAN magic packets. Best effort: iOS only allows broadcast with a special entitlement, so we
/// also send straight to the TV's last known address, which works while the TV still answers ARP.
enum WakeOnLAN {
    static func wake(mac: String, host: String) {
        guard let packet = magicPacket(mac: mac) else { return }
        for target in [host, "255.255.255.255"] {
            send(packet, to: target)
        }
    }

    private static func magicPacket(mac: String) -> Data? {
        let hex = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        var data = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { data.append(contentsOf: bytes) }
        return data
    }

    private static func send(_ packet: Data, to host: String) {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 9, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                for _ in 0..<3 {
                    connection.send(content: packet, completion: .contentProcessed { _ in })
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { connection.cancel() }
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
    }
}
