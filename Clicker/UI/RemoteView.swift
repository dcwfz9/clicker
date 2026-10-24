import SwiftUI

struct RemoteView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #else
    @FocusState private var keyboardFocus: Bool
    #endif

    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case settings, addTV, numbers, keyboard, apps

        var id: String { rawValue }

        var title: String {
            switch self {
            case .settings: return "Settings"
            case .addTV: return "Add a TV"
            case .numbers: return "Numbers"
            case .keyboard: return "Keyboard"
            case .apps: return "Apps"
            }
        }
    }

    #if os(macOS)
    private static let sidePadding: CGFloat = 20
    #else
    private static let sidePadding: CGFloat = 24
    #endif

    var body: some View {
        GeometryReader { geometry in
            let pad = min(250, geometry.size.width * 0.62, geometry.size.height * 0.31)
            let rocker = min(160, geometry.size.height * 0.19)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                topRow
                Spacer(minLength: 20)
                DPadView(size: pad)
                Spacer(minLength: 20)
                navRow
                Spacer(minLength: 20)
                bottomRow(rockerHeight: rocker)
                #if os(macOS)
                Spacer(minLength: 10)
                Text("Arrows · Return · Esc · M · + −  ·  ⌘, settings  ·  ⌘Q quit")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary.opacity(0.8))
                #endif
                Spacer(minLength: 8)
            }
            .padding(.horizontal, Self.sidePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .panel(item: $sheet, title: \Sheet.title) { sheet in
            panelContent(sheet)
        }
        .onAppear {
            if model.tvs.isEmpty { sheet = .addTV }
        }
        #if os(iOS)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.activate()
            case .background: model.deactivate()
            default: break
            }
        }
        #else
        .onAppear {
            model.setVisible(true)
            keyboardFocus = true
        }
        .onDisappear { model.setVisible(false) }
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocus)
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press)
        }
        #endif
    }

    @ViewBuilder
    private func panelContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .addTV:
            NavigationStack { AddTVView() }
        case .numbers:
            NumberPadSheet()
            #if os(iOS)
                .presentationDetents([.height(380)])
                .presentationBackground(Theme.background)
            #endif
        case .keyboard:
            KeyboardSheet()
            #if os(iOS)
                .presentationDetents([.height(190)])
                .presentationBackground(Theme.background)
            #endif
        case .apps:
            AppsSheet()
            #if os(iOS)
                .presentationDetents([.medium, .large])
            #endif
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedTV?.name ?? "Clicker")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(model.statusText)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if model.remote.state == .denied {
                    Button("Pair") { model.pair() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                #if os(macOS)
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                #else
                Button {
                    sheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Settings")
                #endif
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private var statusColor: Color {
        switch model.remote.state {
        case .pairing: return .accentColor
        case .denied: return .orange
        default: break
        }
        switch model.power {
        case .on: return model.remote.isConnected ? .green : .accentColor
        case .standby: return .orange
        case .waking: return .accentColor
        case .off, .unknown: return Theme.secondary.opacity(0.6)
        }
    }

    // MARK: Rows

    private var topRow: some View {
        HStack(spacing: 12) {
            powerButton
            Spacer()
            UtilityCircle(symbol: "number", label: "Numbers") { sheet = .numbers }
            UtilityCircle(symbol: "keyboard", label: "Keyboard", highlighted: model.remote.tvWantsText) { sheet = .keyboard }
            UtilityCircle(symbol: "square.grid.2x2", label: "Apps") { sheet = .apps }
            KeyCircle(key: .source, label: "Source", symbol: "rectangle.on.rectangle", size: 48, tint: Theme.secondary)
        }
    }

    private var powerButton: some View {
        HoldButton(haptic: false, onPress: {
            Haptics.firm()
            model.press(.power)
        }) {
            ZStack {
                Circle().fill(Theme.surface)
                if model.power == .waking {
                    ProgressView()
                        .tint(.primary)
                        .controlSize(.small)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(model.power == .on ? Color.primary : Color.accentColor)
                }
            }
            .frame(width: 56, height: 56)
        }
        .accessibilityLabel("Power")
    }

    private var navRow: some View {
        HStack(spacing: 0) {
            Spacer()
            KeyCircle(key: .back, label: "Back", symbol: "arrow.uturn.backward")
            Spacer()
            KeyCircle(key: .home, label: "Home", symbol: "house")
            Spacer()
            KeyCircle(key: .menu, label: "Menu", symbol: "line.3.horizontal")
            Spacer()
        }
    }

    private func bottomRow(rockerHeight: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 0) {
            RockerView(title: "VOL", upKey: .volumeUp, downKey: .volumeDown, height: rockerHeight)
            Spacer()
            VStack(spacing: 10) {
                KeyCircle(key: .mute, label: "Mute", symbol: "speaker.slash", size: 46)
                KeyCircle(key: .play, label: "Play", symbol: "play.fill", size: 46)
                KeyCircle(key: .pause, label: "Pause", symbol: "pause.fill", size: 46)
            }
            Spacer()
            RockerView(title: "CH", upKey: .channelUp, downKey: .channelDown,
                       upSymbol: "chevron.up", downSymbol: "chevron.down", height: rockerHeight)
        }
    }

    // MARK: Keyboard (macOS)

    #if os(macOS)
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard sheet == nil else { return .ignored }
        let key: RemoteKey?
        switch press.key {
        case .upArrow: key = .up
        case .downArrow: key = .down
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .return: key = .enter
        case .escape, .delete: key = .back
        default:
            switch press.characters.lowercased() {
            case "h": key = .home
            case "m": key = .mute
            case "=", "+": key = .volumeUp
            case "-", "_": key = .volumeDown
            case "]": key = .channelUp
            case "[": key = .channelDown
            default: key = Int(press.characters).flatMap(RemoteKey.digit)
            }
        }
        guard let key else { return .ignored }
        if press.phase == .repeat, !key.repeats { return .handled }
        model.press(key)
        return .handled
    }
    #endif
}
