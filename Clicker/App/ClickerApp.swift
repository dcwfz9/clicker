import SwiftUI

@main
struct ClickerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RemoteView()
                .environment(model)
        }
    }
}
