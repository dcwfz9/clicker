import Foundation

/// Key codes understood by Samsung Tizen TVs (the `DataOfCmd` of a `SendRemoteKey` message).
enum RemoteKey: String, CaseIterable, Sendable {
    case power = "KEY_POWER"

    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case enter = "KEY_ENTER"

    case back = "KEY_RETURN"
    case home = "KEY_HOME"
    case menu = "KEY_MENU"
    case exit = "KEY_EXIT"

    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"

    case channelUp = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case previousChannel = "KEY_PRECH"
    case channelList = "KEY_CH_LIST"

    case play = "KEY_PLAY"
    case pause = "KEY_PAUSE"
    case stop = "KEY_STOP"
    case rewind = "KEY_REWIND"
    case fastForward = "KEY_FF"

    case source = "KEY_SOURCE"
    case guide = "KEY_GUIDE"
    case info = "KEY_INFO"
    case tools = "KEY_TOOLS"
    case more = "KEY_MORE"

    case red = "KEY_RED"
    case green = "KEY_GREEN"
    case yellow = "KEY_YELLOW"
    case blue = "KEY_BLUE"

    case num0 = "KEY_0"
    case num1 = "KEY_1"
    case num2 = "KEY_2"
    case num3 = "KEY_3"
    case num4 = "KEY_4"
    case num5 = "KEY_5"
    case num6 = "KEY_6"
    case num7 = "KEY_7"
    case num8 = "KEY_8"
    case num9 = "KEY_9"

    static func digit(_ n: Int) -> RemoteKey? {
        RemoteKey(rawValue: "KEY_\(n)")
    }

    /// Keys that make sense to auto-repeat while the button is held.
    var repeats: Bool {
        switch self {
        case .up, .down, .left, .right, .volumeUp, .volumeDown, .channelUp, .channelDown, .rewind, .fastForward:
            return true
        default:
            return false
        }
    }
}

/// How a key is sent. `click` is a tap; `press` and `release` bracket a hold.
enum KeyAction: String, Sendable {
    case click = "Click"
    case press = "Press"
    case release = "Release"
}
