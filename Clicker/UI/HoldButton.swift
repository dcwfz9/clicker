import SwiftUI

/// A button that fires on touch-down (a remote should feel instant) and, for keys that repeat,
/// keeps firing while held.
struct HoldButton<Label: View>: View {
    private let repeats: Bool
    private let haptic: Bool
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let label: () -> Label

    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?

    init(repeats: Bool = false,
         haptic: Bool = true,
         onPress: @escaping () -> Void,
         onRelease: @escaping () -> Void = {},
         @ViewBuilder label: @escaping () -> Label) {
        self.repeats = repeats
        self.haptic = haptic
        self.onPress = onPress
        self.onRelease = onRelease
        self.label = label
    }

    var body: some View {
        label()
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.94 : 1)
            .opacity(pressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { begin() } }
                    .onEnded { _ in end() }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onPress() }
    }

    private func begin() {
        pressed = true
        if haptic { Haptics.tap() }
        onPress()
        guard repeats else { return }
        repeater = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            var fired = 0
            while !Task.isCancelled, fired < 60 {
                onPress()
                fired += 1
                try? await Task.sleep(for: .milliseconds(140))
            }
        }
    }

    private func end() {
        pressed = false
        repeater?.cancel()
        repeater = nil
        onRelease()
    }
}

/// The standard round key.
struct KeyCircle: View {
    @Environment(AppModel.self) private var model

    let key: RemoteKey
    let label: String
    var symbol: String? = nil
    var text: String? = nil
    var size: CGFloat = 56
    var fill: Color = Theme.surface
    var tint: Color = .primary

    var body: some View {
        HoldButton(repeats: key.repeats, onPress: { model.press(key) }) {
            ZStack {
                Circle().fill(fill)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.36, weight: .medium))
                } else if let text {
                    Text(text)
                        .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(tint)
            .frame(width: size, height: size)
        }
        .accessibilityLabel(label)
    }
}

/// A round button that opens something in the app rather than pressing a TV key.
struct UtilityCircle: View {
    let symbol: String
    let label: String
    var size: CGFloat = 48
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(highlighted ? Color.accentColor.opacity(0.22) : Theme.surface)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(highlighted ? Color.accentColor : Theme.secondary)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
