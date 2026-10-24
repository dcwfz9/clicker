import SwiftUI

/// The Mac version lives in the menu bar: click the TV icon and the remote drops down.
/// Arrow keys, Return, Escape, M, + and - work while it is open. Settings is the usual Cmd+,.
@main
struct ClickerMacApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        // `open Clicker.app --args -ClickerRenderTo /path.png` writes a picture of the remote and quits,
        // so a build can be looked at without clicking the menu bar.
        if let path = UserDefaults.standard.string(forKey: "ClickerRenderTo") {
            MainActor.assumeIsolated { Self.render(to: path) }
        }
        #endif
        // The popover's view does not exist until the icon is clicked, so start watching the TV here.
        // While the remote is closed the model polls slowly and keeps the connection warm.
        let model = MainActor.assumeIsolated { () -> AppModel in
            let model = AppModel()
            model.setVisible(false)
            model.activate()
            return model
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            RemoteView()
                .environment(model)
                .frame(width: 340, height: 600)
        } label: {
            Image(systemName: "tv")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .frame(width: 460, height: 560)
        }
    }

    #if DEBUG
    @MainActor
    private static func render(to path: String) {
        let model = AppModel()
        for scheme in [ColorScheme.dark, .light] {
            let view = RemoteView()
                .environment(model)
                .frame(width: 340, height: 600)
                .background(Theme.background)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let url = URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: scheme == .dark ? "-dark.png" : "-light.png"))
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
        }
        exit(0)
    }
    #endif
}
