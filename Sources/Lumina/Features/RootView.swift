import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Disabled by the offscreen documentation renderer, which supplies a
    /// prepared demo index and must not start a live scan.
    var bootstrapOnAppear: Bool = true
    var settingsInitialTab: SettingsTab = .general

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: Binding(
                get: { model.route },
                set: { model.route = $0 }
            ))
            .navigationSplitViewColumnWidth(min: 212, ideal: 228, max: 264)
        } detail: {
            // GeometryReader keeps the detail column tied to the window
            // viewport. Without it, a tall scrollable screen can report its
            // ideal content height and make the split view — and in manual
            // hosting, the window — grow past the frame the user chose.
            GeometryReader { proxy in
                detail
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Palette.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .tint(settings.accent.color)
        .accentColor(settings.accent.color)
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if let error = model.errorBanner {
                    ErrorBannerView(error: error) {
                        model.dismissError()
                    }
                    .frame(maxWidth: 520)
                }
                if let message = model.infoMessage {
                    InfoBannerView(message: message) {
                        model.infoMessage = nil
                    }
                    .frame(maxWidth: 480)
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 18)
            .animation(.easeOut(duration: 0.18), value: model.errorBanner?.id)
            .animation(.easeOut(duration: 0.18), value: model.infoMessage)
        }
        .sheet(isPresented: $model.showWhyLocal) {
            WhyLocalView()
                .environment(model)
                .environment(settings)
                .tint(settings.accent.color)
                .accentColor(settings.accent.color)
        }
        .task {
            if bootstrapOnAppear {
                await model.bootstrap()
            }
            applyWindowAppearance()
        }
        .task(id: model.infoMessage) {
            guard let message = model.infoMessage else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, model.infoMessage == message else { return }
            model.infoMessage = nil
        }
        .onChange(of: settings.appearance) { _, _ in
            applyWindowAppearance()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.route {
        case .home:
            HomeView()
        case .search:
            SearchView()
        case .chat:
            ChatView()
        case .library:
            LibraryView()
        case .timeline:
            TimelineView()
        case .settings:
            SettingsView(initialTab: settingsInitialTab)
        }
    }

    private func applyWindowAppearance() {
        switch settings.appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.windows.forEach { $0.appearance = NSApp.appearance }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Binding var selection: AppRoute

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                LuminaWordmark()
                Text("Illuminate your local knowledge")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 14)

            List(selection: Binding<AppRoute?>(
                get: { selection },
                set: { if let value = $0 { selection = value } }
            )) {
                Section {
                    ForEach(AppRoute.allCases) { route in
                        sidebarRow(route)
                            .tag(route)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
            sidebarFooter
        }
        .background(Palette.sidebar)
        .safeAreaPadding(.top, 10)
    }

    private func sidebarRow(_ route: AppRoute) -> some View {
        HStack(spacing: 8) {
            Image(systemName: route.systemImage)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 18)
                .foregroundStyle(selection == route ? Color.accentColor : Palette.secondary)
            Text(route.title)
                .font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 4)
            if route == .library, model.stats.fileCount > 0 {
                Text("\(model.stats.fileCount)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()

            Button {
                selection = model.isFullyConfigured ? .settings : .home
            } label: {
                HStack(spacing: 7) {
                    StatusDot(color: statusColor)
                    Text(statusText)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help("Local model status")

            HStack(spacing: 6) {
                Text("Quick Search")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                KeyCap(label: settings.shortcut.display)
            }

            if model.isIndexing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(model.indexingProgress.phase.title)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var statusColor: Color {
        if model.isFullyConfigured { return .green }
        if model.setup.isReachable { return .orange }
        return .secondary
    }

    private var statusText: String {
        if model.isFullyConfigured { return "Local models ready" }
        if model.setup.isReachable { return "Finish model setup" }
        return "Local runtime offline"
    }
}

// MARK: - Why local

struct WhyLocalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                LuminaMark(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private by architecture, not by promise")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.label)
                    Text("Your files, questions, and answers stay on this Mac.")
                        .font(LuminaType.body)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 14) {
                reason(
                    icon: "externaldrive",
                    title: "Files are read only where you point",
                    detail: "Lumina indexes the folders you explicitly choose. It skips hidden files, credentials, keys, and package internals."
                )
                reason(
                    icon: "network.slash",
                    title: "No cloud account, no telemetry",
                    detail: "There is no sign-in, analytics SDK, crash uploader, or background sync. The app works fully offline once models are downloaded."
                )
                reason(
                    icon: "checkmark.shield",
                    title: "Local endpoints are enforced in code",
                    detail: "Lumina refuses model endpoints that are not loopback addresses. Prompts and embeddings can only travel to a server running on this Mac."
                )
                reason(
                    icon: "cylinder.split.1x2",
                    title: "The index is yours",
                    detail: "Files, passages, vectors, notes, and conversations live in a single SQLite database under Application Support. Erase it whenever you want."
                )
            }

            DividerRow()
                .padding(.vertical, 18)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiary)
                    .padding(.top, 1)
                Text("Local does not mean risk-free. Models can still make mistakes, and indexed text is stored unencrypted in Lumina's database. Use FileVault and only index folders you are comfortable keeping on this Mac.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Open Data Folder") {
                    model.openDataFolder()
                }
                .buttonStyle(.secondaryAction)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.primaryAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 22)
        }
        .padding(26)
        .frame(width: 590)
        .background(Palette.canvas)
    }

    private func reason(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            IconTile(systemImage: icon, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LuminaType.bodyEmphasis)
                    .foregroundStyle(Palette.label)
                Text(detail)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Startup failure

struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            LuminaMark(size: 54, showBackground: true)
            Text("Lumina couldn't start")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Palette.label)
            Text(message)
                .font(LuminaType.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 430)

            InlineNotice(
                text: "If this keeps happening, move ~/Library/Application Support/Lumina aside and relaunch. Lumina never deletes that folder automatically.",
                tone: .warning
            )
            .frame(maxWidth: 460)

            HStack(spacing: 10) {
                Button("Reveal Data Folder") {
                    let support = FileManager.default.urls(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask
                    )[0].appendingPathComponent("Lumina", isDirectory: true)
                    NSWorkspace.shared.open(support)
                }
                .buttonStyle(.secondaryAction)

                Button("Quit Lumina") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.primaryAction)
            }
            .padding(.top, 4)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}

// MARK: - Button style aliases

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
}

extension ButtonStyle where Self == SecondaryActionButtonStyle {
    static var secondaryAction: SecondaryActionButtonStyle { SecondaryActionButtonStyle() }
}

extension ButtonStyle where Self == QuietActionButtonStyle {
    static var quietAction: QuietActionButtonStyle { QuietActionButtonStyle() }
}
