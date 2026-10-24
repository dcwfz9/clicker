import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("TVs") {
                    ForEach(model.tvs) { tv in
                        NavigationLink {
                            TVDetailView(tv: tv)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name)
                                    Text("\(tv.displayModel) · \(tv.host)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if tv.id == model.selectedID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                    NavigationLink("Add a TV") { AddTVView() }
                }

                Section {
                    HomeAssistantSettings()
                } header: {
                    Text("Home Assistant")
                } footer: {
                    Text("Optional. When the TV cannot be woken directly, Clicker asks Home Assistant to turn this entity on instead.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    Text("Works with Samsung Smart TVs that support network remote control, most models from 2018 on. This device and the TV need to be on the same network.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #if os(macOS)
                    Button("Quit Clicker") { NSApplication.shared.terminate(nil) }
                    #endif
                }
            }
            .navigationTitle("Settings")
            .inlineTitle()
            .groupedForm()
            .doneButton { dismiss() }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

struct TVDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var tv: TV

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $tv.name)
                TextField("IP address", text: $tv.host)
                    .addressEntry()
            } footer: {
                Text("\(tv.displayModel)\(tv.mac.map { " · \($0)" } ?? "")")
            }

            Section {
                if tv.id != model.selectedID {
                    Button("Use this TV") {
                        model.update(tv)
                        model.select(tv.id)
                        dismiss()
                    }
                }
                Button(model.hasPairing(tv) ? "Pair again" : "Pair") {
                    model.update(tv)
                    model.forgetPairing(tv)
                    model.select(tv.id)
                    model.pair()
                    dismiss()
                }
                Button("Remove TV", role: .destructive) {
                    model.remove(tv)
                    dismiss()
                }
            } footer: {
                Text(model.hasPairing(tv)
                     ? "Paired. The TV remembers Clicker until you pair again or reset the TV."
                     : "Not paired yet. The TV shows a prompt the first time Clicker connects.")
            }
        }
        .navigationTitle(tv.name)
        .inlineTitle()
        .onDisappear { model.update(tv) }
    }
}

struct AddTVView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                if model.discovery.found.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for TVs on this Wi‑Fi…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.discovery.found) { tv in
                    Button {
                        model.add(tv)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tv.name).foregroundStyle(.primary)
                            Text("\(tv.displayModel) · \(tv.host)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Found")
            } footer: {
                Text("A TV that is fully asleep does not show up. Turn it on once, or add it by address.")
            }

            Section("By address") {
                TextField("IP address", text: $host)
                    .addressEntry()
                    .onSubmit { Task { await addManually() } }
                Button(checking ? "Checking…" : "Add") {
                    Task { await addManually() }
                }
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Add anyway") {
                        let address = host.trimmingCharacters(in: .whitespaces)
                        model.add(TV(id: address, name: "Samsung TV", model: nil, host: address, mac: nil))
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Add a TV")
        .inlineTitle()
        .onAppear { model.discovery.start() }
        .onDisappear { model.discovery.stop() }
    }

    private func addManually() async {
        let address = host.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        checking = true
        problem = nil
        defer { checking = false }
        if let tv = await TVDiscovery.lookup(host: address) {
            model.add(tv)
            dismiss()
        } else {
            problem = "Nothing answered at \(address). Is the TV on and on this Wi‑Fi?"
        }
    }
}

struct HomeAssistantSettings: View {
    @Environment(AppModel.self) private var model

    @State private var token = Keychain.string(for: HomeAssistantConfig.tokenAccount) ?? ""
    @State private var result: String?

    var body: some View {
        @Bindable var model = model

        Toggle("Use for power", isOn: $model.homeAssistant.enabled)
        if model.homeAssistant.enabled {
            TextField("URL, e.g. http://homeassistant.local:8123", text: $model.homeAssistant.url)
                .urlEntry()
            SecureField("Long-lived access token", text: $token)
                .onChange(of: token) { _, value in
                    Keychain.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: HomeAssistantConfig.tokenAccount)
                }
            NavigationLink {
                HAEntityPicker()
            } label: {
                LabeledContent("Entity", value: model.homeAssistant.entityID.isEmpty ? "Choose" : model.homeAssistant.entityID)
            }
            Button("Test connection") {
                Task {
                    do {
                        result = try await HomeAssistant.check(model.homeAssistant)
                    } catch {
                        result = error.localizedDescription
                    }
                }
            }
            if let result {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HAEntityPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var entities: [HAEntity] = []
    @State private var problem: String?
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if let problem {
                Text(problem).foregroundStyle(.secondary)
            }
            ForEach(Dictionary(grouping: entities, by: \.domain).keys.sorted(), id: \.self) { domain in
                Section(domain.replacingOccurrences(of: "_", with: " ")) {
                    ForEach(entities.filter { $0.domain == domain }) { entity in
                        Button {
                            model.homeAssistant.entityID = entity.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entity.name).foregroundStyle(.primary)
                                    Text(entity.id).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if entity.id == model.homeAssistant.entityID {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Entity")
        .inlineTitle()
        .task {
            do {
                entities = try await HomeAssistant.entities(model.homeAssistant)
                if entities.isEmpty { problem = "No media players, remotes, switches or scripts found." }
            } catch {
                problem = error.localizedDescription
            }
            loading = false
        }
    }
}
