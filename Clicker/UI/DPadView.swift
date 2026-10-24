import SwiftUI

/// The directional pad: one round surface, four wedges and a centre button, driven by a single
/// touch so a thumb can land anywhere in a wedge.
struct DPadView: View {
    @Environment(AppModel.self) private var model

    let size: CGFloat

    @State private var active: Zone?
    @State private var repeater: Task<Void, Never>?

    enum Zone: Hashable {
        case up, down, left, right, center

        var key: RemoteKey {
            switch self {
            case .up: return .up
            case .down: return .down
            case .left: return .left
            case .right: return .right
            case .center: return .enter
            }
        }

        /// Wedge centre angle, degrees clockwise from +x (SwiftUI's y points down).
        var angle: Double {
            switch self {
            case .right: return 0
            case .down: return 90
            case .left: return 180
            case .up: return 270
            case .center: return 0
            }
        }
    }

    private var centerDiameter: CGFloat { size * 0.38 }
    private var arrowOffset: CGFloat { size * 0.355 }

    var body: some View {
        ZStack {
            Circle().fill(Theme.surface)

            if let active, active != .center {
                wedge(active)
                    .fill(Color.primary.opacity(0.08))
            }

            arrow("chevron.up", x: 0, y: -arrowOffset)
            arrow("chevron.down", x: 0, y: arrowOffset)
            arrow("chevron.left", x: -arrowOffset, y: 0)
            arrow("chevron.right", x: arrowOffset, y: 0)

            Circle()
                .fill(active == .center ? Color.primary.opacity(0.16) : Theme.surfaceRaised)
                .frame(width: centerDiameter, height: centerDiameter)
                .overlay {
                    Text("OK")
                        .font(.system(size: size * 0.085, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if active == nil { begin(zone(at: value.startLocation)) }
                }
                .onEnded { _ in end() }
        )
        .animation(.easeOut(duration: 0.1), value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Direction pad")
        .accessibilityActions {
            Button("Up") { model.press(.up) }
            Button("Down") { model.press(.down) }
            Button("Left") { model.press(.left) }
            Button("Right") { model.press(.right) }
            Button("OK") { model.press(.enter) }
        }
    }

    private func arrow(_ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.095, weight: .semibold))
            .foregroundStyle(.primary)
            .offset(x: x, y: y)
    }

    private func wedge(_ zone: Zone) -> Path {
        let center = CGPoint(x: size / 2, y: size / 2)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: size / 2,
                    startAngle: .degrees(zone.angle - 45), endAngle: .degrees(zone.angle + 45), clockwise: false)
        path.closeSubpath()
        return path
    }

    private func zone(at point: CGPoint) -> Zone {
        let dx = point.x - size / 2
        let dy = point.y - size / 2
        if hypot(dx, dy) < centerDiameter / 2 { return .center }
        let degrees = atan2(dy, dx) * 180 / .pi
        switch degrees {
        case -45..<45: return .right
        case 45..<135: return .down
        case -135 ..< -45: return .up
        default: return .left
        }
    }

    private func begin(_ zone: Zone) {
        active = zone
        Haptics.tap()
        model.press(zone.key)
        guard zone != .center else { return }
        repeater = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            var fired = 0
            while !Task.isCancelled, fired < 60 {
                model.press(zone.key)
                fired += 1
                try? await Task.sleep(for: .milliseconds(140))
            }
        }
    }

    private func end() {
        active = nil
        repeater?.cancel()
        repeater = nil
    }
}

/// Vertical rocker for volume or channel.
struct RockerView: View {
    @Environment(AppModel.self) private var model

    let title: String
    let upKey: RemoteKey
    let downKey: RemoteKey
    var upSymbol = "plus"
    var downSymbol = "minus"
    var width: CGFloat = 64
    var height: CGFloat = 156

    var body: some View {
        VStack(spacing: 0) {
            half(upKey, upSymbol, "\(title) up")
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.secondary)
            half(downKey, downSymbol, "\(title) down")
        }
        .frame(width: width, height: height)
        .background(Theme.surface, in: Capsule())
    }

    private func half(_ key: RemoteKey, _ symbol: String, _ label: String) -> some View {
        HoldButton(repeats: true, onPress: { model.press(key) }) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(label)
    }
}
