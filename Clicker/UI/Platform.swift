import SwiftUI

// Small differences between the iPhone app and the Mac menu bar app live here, so the views stay shared.

extension View {
    /// Inline navigation title on iOS; nothing to do on macOS.
    func inlineTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// A field for an IP address.
    func addressEntry() -> some View {
        #if os(iOS)
        return autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
        #else
        return autocorrectionDisabled()
        #endif
    }

    /// A field for a URL.
    func urlEntry() -> some View {
        #if os(iOS)
        return autocorrectionDisabled()
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
        #else
        return autocorrectionDisabled()
        #endif
    }

    /// Settings-style grouped form on the Mac.
    func groupedForm() -> some View {
        #if os(macOS)
        return formStyle(.grouped)
        #else
        return self
        #endif
    }

    /// A "Done" button in the navigation bar on iOS, where the view is a sheet. On the Mac the view
    /// sits in its own window or panel, which has its own way to close.
    func doneButton(_ action: @escaping () -> Void) -> some View {
        #if os(iOS)
        return toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: action)
            }
        }
        #else
        return self
        #endif
    }

    func closeButton(_ action: @escaping () -> Void) -> some View {
        #if os(iOS)
        return toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: action)
            }
        }
        #else
        return self
        #endif
    }
}

// MARK: Panels (a sheet on iOS, an overlay inside the menu bar popover on macOS)

private struct PanelDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Closes the panel the view is shown in. On iOS `dismiss` does the same job; call both.
    var panelDismiss: () -> Void {
        get { self[PanelDismissKey.self] }
        set { self[PanelDismissKey.self] = newValue }
    }
}

extension View {
    func panel<Item: Identifiable, PanelContent: View>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        @ViewBuilder content: @escaping (Item) -> PanelContent
    ) -> some View {
        modifier(PanelModifier(item: item, title: title, panelContent: content))
    }
}

private struct PanelModifier<Item: Identifiable, PanelContent: View>: ViewModifier {
    @Binding var item: Item?
    let title: (Item) -> String
    let panelContent: (Item) -> PanelContent

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(item: $item) { current in
            panelContent(current)
                .environment(\.panelDismiss, { item = nil })
        }
        #else
        content
            .overlay {
                if let current = item {
                    VStack(spacing: 0) {
                        HStack {
                            Text(title(current))
                                .font(.headline)
                            Spacer()
                            Button("Done") { item = nil }
                                .keyboardShortcut(.cancelAction)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        panelContent(current)
                            .environment(\.panelDismiss, { item = nil })
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .background(Theme.background)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: item == nil)
        #endif
    }
}
