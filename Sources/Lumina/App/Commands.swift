import SwiftUI

struct LuminaCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Conversation") {
                navigate(to: .chat) { model in
                    model.newConversation(mode: .answer)
                }
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Quick Search…") {
                NotificationCenter.default.post(name: .luminaShowQuickSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Add Folder…") {
                showMainWindow {
                    $0.chooseFolder()
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Open Data Folder") {
                showMainWindow { $0.openDataFolder() }
            }
        }

        CommandMenu("Go") {
            ForEach(AppRoute.allCases) { route in
                Button(route.title) {
                    navigate(to: route)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(route.keyNumber))), modifiers: .command)
            }
        }

        CommandMenu("Index") {
            Button("Index Now") {
                showMainWindow { $0.startIndexing(force: false) }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Reindex Everything") {
                showMainWindow { $0.reindexAll() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Pause Indexing") {
                showMainWindow { $0.cancelIndexing() }
            }
            .disabled(AppEnvironment.shared.model?.isIndexing != true)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Why Local?") {
                showMainWindow { $0.showWhyLocal = true }
            }
            Button("Check Local Models") {
                Task { @MainActor in
                    guard let model = AppEnvironment.shared.model else { return }
                    NotificationCenter.default.post(name: .luminaOpenMainWindow, object: nil)
                    await model.verifySetup()
                }
            }
        }
    }

    private func navigate(to route: AppRoute, _ action: ((AppModel) -> Void)? = nil) {
        Task { @MainActor in
            guard let model = AppEnvironment.shared.model else { return }
            model.route = route
            action?(model)
            NotificationCenter.default.post(name: .luminaOpenMainWindow, object: nil)
        }
    }

    private func showMainWindow(_ action: @escaping @MainActor (AppModel) -> Void) {
        Task { @MainActor in
            guard let model = AppEnvironment.shared.model else { return }
            NotificationCenter.default.post(name: .luminaOpenMainWindow, object: nil)
            action(model)
        }
    }
}
