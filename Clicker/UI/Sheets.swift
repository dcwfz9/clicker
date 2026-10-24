import SwiftUI

struct NumberPadSheet: View {
    @Environment(AppModel.self) private var model

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...9, id: \.self) { digit in
                    pad(RemoteKey.digit(digit) ?? .num0, text: "\(digit)")
                }
                pad(.previousChannel, text: "PRE-CH", small: true)
                pad(.num0, text: "0")
                pad(.enter, symbol: "return")
            }
        }
        .padding(24)
        .padding(.top, 8)
    }

    private func pad(_ key: RemoteKey, text: String? = nil, symbol: String? = nil, small: Bool = false) -> some View {
        HoldButton(onPress: { model.press(key) }) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface)
                if let text {
                    Text(text)
                        .font(.system(size: small ? 15 : 26, weight: .medium, design: .rounded))
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                }
            }
            .foregroundStyle(.primary)
            .frame(height: 64)
        }
        .accessibilityLabel(text ?? "Enter")
    }
}

struct KeyboardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.panelDismiss) private var panelDismiss

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type on the TV")
                .font(.headline)
            HStack(spacing: 10) {
                TextField("Text", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button("Send", action: send)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
            }
            Text(model.remote.tvWantsText
                 ? "The TV has a text field open."
                 : "Open a search or text field on the TV first.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .padding(24)
        .onAppear { focused = true }
    }

    private func send() {
        guard !text.isEmpty else { return }
        model.remote.sendText(text)
        text = ""
        panelDismiss()
        dismiss()
    }
}

struct AppsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.panelDismiss) private var panelDismiss

    @State private var apps: [TVApp] = []
    @State private var loading = true
    @State private var fromTV = false

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Asking the TV…").foregroundStyle(.secondary)
                    }
                }
                ForEach(apps) { app in
                    Button {
                        Haptics.tap()
                        model.remote.launch(app)
                        panelDismiss()
                        dismiss()
                    } label: {
                        Text(app.name).foregroundStyle(.primary)
                    }
                }
                if !loading, !fromTV {
                    Text(model.isConnected
                         ? "The TV did not share its app list, so these are the usual ones."
                         : "Connect to the TV to see its apps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Apps")
            .inlineTitle()
            .closeButton { dismiss() }
        }
        .task {
            do {
                let list = try await model.remote.installedApps()
                apps = list.filter { !$0.name.isEmpty }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                fromTV = !apps.isEmpty
            } catch {
                apps = TVApp.common
            }
            loading = false
        }
    }
}
