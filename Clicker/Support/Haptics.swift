import Foundation
#if canImport(UIKit)
import UIKit

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    static func tap() {
        light.impactOccurred(intensity: 0.8)
    }

    static func firm() {
        medium.impactOccurred()
    }
}
#else
/// No haptics on the Mac; the menu bar remote is driven by mouse and keyboard.
enum Haptics {
    static func tap() {}
    static func firm() {}
}
#endif

/// Debug-only trace to stdout (visible when the binary is run from a shell).
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    FileHandle.standardError.write(Data("[clicker] \(message())\n".utf8))
    #endif
}
