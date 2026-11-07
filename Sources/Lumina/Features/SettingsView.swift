import AppKit
import SwiftUI

/// Preferences for the local runtime, indexing behavior, and data ownership.
/// Every value writes through to `AppSettings` immediately; there is no Apply
/// button and no separate settings database.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var isStandaloneWindow: Bool = false

    @State private var tab: SettingsTab = .general
    @State private var endpointDraft = ""
    @State private var showResetConfirmation = false
    @State private var showEraseConfirmation = false

    var body: some View {
        ScreenScroll(maxWidth: 810) {
            header
            tabPicker

            switch tab {
            case .general:
                generalTab
            case .models:
                modelsTab
            case .indexing:
                indexingTab
            case .privacy:
                privacyTab
            case .about:
                aboutTab
            }
        }
        .background(Palette.canvas)
        .tint(settings.accent.color)
        .accentColor(settings.accent.color)
        .task {
            endpointDraft = settings.endpoint
        }
        .onChange(of: settings.endpoint) { _, newValue in
            if endpointDraft != newValue {
                endpointDraft = newValue
            }
        }
        .alert("Reset the search index?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Index", role: .destructive) {
                Task { await model.resetIndex() }
            }
        } message: {
            Text("Every extracted passage, vector, note, conversation, and thumbnail will be removed from Lumina's database. Your folders stay selected and your original files are not touched.")
        }
        .alert("Erase all Lumina data?", isPresented: $showEraseConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Erase Everything", role: .destructive) {
                Task { await model.eraseAllData() }
            }
        } message: {
            Text("This removes the index, vectors, notes, conversations, saved folders, and preferences from this Mac. It cannot be undone. Original files are never deleted.")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if isStandaloneWindow {
            HStack(alignment: .center, spacing: 12) {
                LuminaMark(size: 38, showBackground: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumina Settings")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.label)
                    Text("Everything here runs on this Mac.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                settingsStatus
            }
        } else {
            PageHeader(
                eyebrow: "Preferences",
                title: "Settings",
                subtitle: "Tune the local runtime, choose what gets indexed, and control the data Lumina keeps."
            ) {
                settingsStatus
            }
        }
    }

    private var settingsStatus: some View {
        StatusPill(
            text: model.isFullyConfigured ? "Local models ready" : "Setup needed",
            tone: model.isFullyConfigured ? .green : .orange
        )
    }

    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 11, weight: .medium))
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? Color.accentColor : Palette.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tab == item ? Color.accentColor.opacity(0.1) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.separator.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.4), lineWidth: 0.6)
        )
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: "Appearance",
                subtitle: "Lumina follows the system by default and uses one restrained accent color."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsRow(title: "Theme", detail: "Applies to every Lumina window.") {
                        Picker("Theme", selection: Binding(
                            get: { settings.appearance },
                            set: { settings.appearance = $0 }
                        )) {
                            ForEach(AppearanceChoice.allCases) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }

                    DividerRow()

                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accent")
                                .font(LuminaType.bodyEmphasis)
                                .foregroundStyle(Palette.label)
                            Text("Used for selection, focus, and grounding cues.")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 10)
                        HStack(spacing: 9) {
                            ForEach(AccentChoice.allCases) { choice in
                                accentSwatch(choice)
                            }
                        }
                    }
                }
            }

            SettingsCard(
                title: "Quick Search",
                subtitle: "Open a command palette over any app. Search never leaves this Mac."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(
                        title: "Global shortcut",
                        detail: "If macOS or another app already uses a shortcut, Lumina will tell you when it tries to register it."
                    ) {
                        Picker("Global shortcut", selection: Binding(
                            get: { settings.shortcut },
                            set: { settings.shortcut = $0 }
                        )) {
                            ForEach(shortcutChoices, id: \.self) { shortcut in
                                Text(shortcut.display).tag(shortcut)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    HStack(spacing: 9) {
                        Button("Open Quick Search") {
                            NotificationCenter.default.post(name: .luminaShowQuickSearch, object: nil)
                        }
                        .buttonStyle(.secondaryAction)

                        Text("The in-app palette is also available with ⌘K.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }

            SettingsCard(
                title: "Background indexing",
                subtitle: "Automatic scans look for changed files only. They never touch the network."
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    ToggleSettingRow(
                        title: "Keep the index current",
                        detail: "Scan enabled folders shortly after launch and periodically while Lumina is open.",
                        isOn: Binding(
                            get: { settings.autoIndexEnabled },
                            set: { settings.autoIndexEnabled = $0 }
                        )
                    )

                    DividerRow()

                    SettingsRow(
                        title: "Scan interval",
                        detail: "A shorter interval uses more disk and CPU. Five minutes is the minimum."
                    ) {
                        Stepper(value: Binding(
                            get: { settings.autoScanMinutes },
                            set: { settings.autoScanMinutes = $0 }
                        ), in: 5...120, step: 5) {
                            Text("\(settings.autoScanMinutes) min")
                                .font(LuminaType.mono)
                                .foregroundStyle(Palette.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        .disabled(!settings.autoIndexEnabled)
                    }
                }
            }
        }
    }

    private var shortcutChoices: [GlobalShortcut] {
        var choices = GlobalShortcut.presets
        if !choices.contains(settings.shortcut) {
            choices.insert(settings.shortcut, at: 0)
        }
        return choices
    }

    private func accentSwatch(_ choice: AccentChoice) -> some View {
        let selected = settings.accent == choice
        return Button {
            settings.accent = choice
        } label: {
            ZStack {
                Circle()
                    .fill(choice.color)
                    .frame(width: 20, height: 20)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 27, height: 27)
            .background(
                Circle()
                    .fill(selected ? choice.color.opacity(0.16) : .clear)
            )
            .overlay(
                Circle()
                    .strokeBorder(selected ? choice.color.opacity(0.55) : Palette.separator.opacity(0.45),
                                  lineWidth: selected ? 1 : 0.6)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
    }

    // MARK: - Models

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            runtimeCard
            modelCard
            verificationCard
        }
    }

    private var runtimeCard: some View {
        SettingsCard(
            title: "Local runtime",
            subtitle: "Lumina only talks to loopback addresses. Remote hosts are rejected before a request is made."
        ) {
            VStack(alignment: .leading, spacing: 13) {
                SettingsRow(
                    title: "Runtime",
                    detail: settings.runtimeKind == .ollama
                        ? "Ollama serves both the chat and embedding models."
                        : "Any server exposing OpenAI-compatible /v1 endpoints."
                ) {
                    Picker("Runtime", selection: Binding(
                        get: { settings.runtimeKind },
                        set: { updateRuntime($0) }
                    )) {
                        ForEach(RuntimeKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 268)
                }

                DividerRow()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Endpoint")
                        .font(LuminaType.bodyEmphasis)
                        .foregroundStyle(Palette.label)
                    HStack(spacing: 8) {
                        TextField("http://127.0.0.1:11434", text: $endpointDraft)
                            .textFieldStyle(.plain)
                            .font(LuminaType.mono)
                            .padding(.horizontal, 9)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Palette.raised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(endpointIsLoopback
                                        ? Palette.separator.opacity(0.55)
                                        : Color.orange.opacity(0.65),
                                        lineWidth: 0.7)
                            )
                            .onSubmit { applyEndpoint() }

                        Button("Apply") { applyEndpoint() }
                            .buttonStyle(.secondaryAction)
                            .disabled(endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines) == settings.endpoint)

                        Button {
                            Task { await model.refreshSetup() }
                        } label: {
                            Label("Check", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.secondaryAction)
                        .disabled(model.isRefreshingSetup)
                    }

                    if endpointIsLoopback {
                        Text("Accepted hosts: localhost, 127.0.0.1, and ::1.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    } else {
                        InlineNotice(
                            text: "This address is not loopback. Lumina refuses remote inference endpoints to keep prompts and embeddings on this Mac.",
                            tone: .warning
                        )
                    }

                    if let error = model.setup.error {
                        InlineNotice(text: error, tone: .warning)
                    }
                }

                DividerRow()

                HStack(spacing: 14) {
                    runtimeStatus(
                        title: "Runtime",
                        ok: model.setup.isReachable,
                        detail: model.setup.isReachable
                            ? "Connected\(model.setup.installation.version.map { " · \($0)" } ?? "")"
                            : "Offline"
                    )
                    runtimeStatus(
                        title: "Embedding model",
                        ok: model.isEmbeddingModelInstalled,
                        detail: model.isEmbeddingModelInstalled ? "Installed" : "Missing"
                    )
                    runtimeStatus(
                        title: "Chat model",
                        ok: model.isChatModelInstalled,
                        detail: model.isChatModelInstalled ? "Installed" : "Missing"
                    )
                    Spacer()
                    Button {
                        model.route = .home
                    } label: {
                        Label("Setup Guide", systemImage: "list.number")
                    }
                    .buttonStyle(.quietAction)
                }
            }
        }
    }

    private var modelCard: some View {
        SettingsCard(
            title: "Models",
            subtitle: "The embedding model powers semantic search. The chat model writes answers from retrieved passages."
        ) {
            VStack(alignment: .leading, spacing: 15) {
                InlineNotice(
                    text: "This Mac has \(settings.recommendation.memoryDescription) of unified memory. Lumina recommends \(settings.recommendation.chatModel) with \(settings.recommendation.embeddingModel).",
                    tone: .neutral
                )

                modelField(
                    role: "Embedding model",
                    detail: "Converts passages and questions into vectors. Changing it requires re-embedding the index.",
                    text: Binding(
                        get: { settings.embeddingModel },
                        set: { settings.embeddingModel = $0 }
                    ),
                    installed: installedEmbeddingModels
                )

                modelField(
                    role: "Chat model",
                    detail: "Used for grounded answers, summaries, extraction, and optional image captions.",
                    text: Binding(
                        get: { settings.chatModel },
                        set: { settings.chatModel = $0 }
                    ),
                    installed: installedChatModels
                )

                HStack(spacing: 9) {
                    Button {
                        settings.applyRecommendedModels()
                        model.infoMessage = "Recommended models selected. Install them if they are missing."
                        Task { await model.refreshSetup() }
                    } label: {
                        Label("Use Recommended", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.secondaryAction)

                    if settings.runtimeKind == .ollama {
                        Button {
                            model.pullRecommendedModels()
                        } label: {
                            Label("Download Recommended", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.primaryAction)
                        .disabled(model.isPullingModels || !model.setup.isReachable)
                    }

                    Text("Models are stored by the runtime, not by Lumina.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                }

                if model.isPullingModels {
                    pullProgress
                }

                if let error = model.setupError, model.setup.isReachable {
                    InlineNotice(text: error, tone: .warning)
                }
            }
        }
    }

    private func modelField(
        role: String,
        detail: String,
        text: Binding<String>,
        installed: [LocalModel]
    ) -> some View {
        SettingsModelField(
            role: role,
            detail: detail,
            text: text,
            installed: installed
        )
    }

    private var installedEmbeddingModels: [LocalModel] {
        model.setup.models.filter(\.isEmbedding)
    }

    private var installedChatModels: [LocalModel] {
        model.setup.models.filter { !$0.isEmbedding }
    }

    private var pullProgress: some View {
        Group {
            if let progress = model.pullProgress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text(progress.model)
                            .font(LuminaType.monoSmall)
                            .foregroundStyle(Palette.label)
                        Spacer()
                        Text(progress.status.capitalized)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                    }
                    ThinProgressBar(
                        value: progress.phase == .complete ? 1 : progress.fraction,
                        tint: .accentColor
                    )
                    HStack {
                        if progress.totalBytes > 0 {
                            Text("\(progress.completedBytes.luminaByteSize) of \(progress.totalBytes.luminaByteSize)")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }
                        Spacer()
                        Button("Stop Download") { model.cancelModelPull() }
                            .buttonStyle(.quietAction)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.05))
                )
            } else {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text("Preparing download…")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                    Spacer()
                    Button("Stop") { model.cancelModelPull() }
                        .buttonStyle(.quietAction)
                }
            }
        }
    }

    private var verificationCard: some View {
        SettingsCard(
            title: "Verify the pipeline",
            subtitle: "Sends one short sentence to the embedding model and confirms a vector comes back."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                switch model.verificationState {
                case .idle:
                    Text("Verification adds a small test embedding to memory only. Nothing is written to the index.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                case .testing:
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("Asking the local embedding model…")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                    }
                case .success(let message):
                    InlineNotice(text: message, tone: .success)
                case .failure(let message):
                    InlineNotice(text: message, tone: .warning)
                }

                HStack(spacing: 9) {
                    Button {
                        Task { await model.verifySetup() }
                    } label: {
                        Label("Verify Models", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.secondaryAction)
                    .disabled(!model.isFullyConfigured || model.verificationState == .testing)

                    if !model.isFullyConfigured {
                        Text("Install the runtime and both models to enable this check.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
        }
    }

    private func runtimeStatus(title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 7) {
            StatusDot(color: ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(LuminaType.captionEmphasis)
                    .foregroundStyle(Palette.label)
                Text(detail)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
            }
        }
    }

    // MARK: - Indexing

    private var indexingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: "What to read",
                subtitle: "Extraction is local. Turning features off reduces index size and CPU use; it never changes your original files."
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    ToggleSettingRow(
                        title: "OCR images and scanned PDFs",
                        detail: "Uses Apple Vision to extract printed text. Useful for screenshots, scans, and whiteboards.",
                        isOn: Binding(
                            get: { settings.ocrEnabled },
                            set: { settings.ocrEnabled = $0 }
                        )
                    )
                    DividerRow()
                    ToggleSettingRow(
                        title: "Describe images with the chat model",
                        detail: "Sends downscaled images to the local chat model for captions. Slower, but makes photos searchable by meaning.",
                        isOn: Binding(
                            get: { settings.visionCaptionsEnabled },
                            set: { settings.visionCaptionsEnabled = $0 }
                        )
                    )
                    DividerRow()
                    ToggleSettingRow(
                        title: "Transcribe audio and video",
                        detail: "Uses Apple's on-device Speech framework. Audio never leaves this Mac. Disabled by default because it is CPU-intensive.",
                        isOn: Binding(
                            get: { settings.transcriptionEnabled },
                            set: { settings.transcriptionEnabled = $0 }
                        )
                    )
                    DividerRow()
                    ToggleSettingRow(
                        title: "Index source code",
                        detail: "Reads text-based code and configuration files. Dependencies, build output, and package internals are skipped.",
                        isOn: Binding(
                            get: { settings.indexCodeEnabled },
                            set: { settings.indexCodeEnabled = $0 }
                        )
                    )
                    DividerRow()
                    ToggleSettingRow(
                        title: "Skip sensitive files",
                        detail: "Skips credentials, keys, certificates, password stores, databases, and hidden files.",
                        isOn: Binding(
                            get: { settings.skipSensitiveFiles },
                            set: { settings.skipSensitiveFiles = $0 }
                        )
                    )
                }
            }

            SettingsCard(
                title: "Limits & exclusions",
                subtitle: "Use exclusions for noisy folders such as caches or exports you never search."
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    SettingsRow(
                        title: "Maximum file size",
                        detail: "Files larger than this are indexed as metadata only. Range: 1 MB to 4 GB."
                    ) {
                        HStack(spacing: 10) {
                            Text("\(settings.maxFileSizeMB) MB")
                                .font(LuminaType.mono)
                                .foregroundStyle(Palette.secondary)
                                .monospacedDigit()
                            Stepper("", value: Binding(
                                get: { settings.maxFileSizeMB },
                                set: { settings.maxFileSizeMB = $0 }
                            ), in: 1...4096, step: 32)
                            .labelsHidden()
                        }
                    }

                    DividerRow()

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Excluded name patterns")
                                .font(LuminaType.bodyEmphasis)
                                .foregroundStyle(Palette.label)
                            Spacer()
                            Text("One per line · wildcards allowed")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }
                        Text("Examples: *.psd, Archive/**, node_modules, Final Cut Libraries")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)

                        TextEditor(text: Binding(
                            get: { settings.excludedPatternsText },
                            set: { settings.excludedPatternsText = $0 }
                        ))
                        .font(LuminaType.mono)
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(minHeight: 64, maxHeight: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.raised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Palette.separator.opacity(0.5), lineWidth: 0.7)
                        )
                    }
                }
            }

            SettingsCard(
                title: "Index health",
                subtitle: "A snapshot of what Lumina currently stores. Original files are never modified."
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        indexStat("Files", value: model.stats.fileCount.formatted(), icon: "doc")
                        indexStat("Passages", value: model.stats.chunkCount.formatted(), icon: "text.alignleft")
                        indexStat("Vectors", value: model.stats.embeddedChunkCount.formatted(), icon: "point.3.connected.trianglepath.dotted")
                        indexStat("Size", value: model.stats.totalBytes.luminaByteSize, icon: "externaldrive")
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        MetadataRow(label: "Folders", value: "\(model.folders.count) selected")
                        MetadataRow(
                            label: "Last scan",
                            value: model.stats.lastIndexedAt?.luminaFullDate ?? "Never"
                        )
                        if model.pendingEmbeddingChunkCount > 0 {
                            MetadataRow(
                                label: "Pending",
                                value: "\(model.pendingEmbeddingChunkCount.formatted()) passages need embeddings"
                            )
                        }
                    }

                    if model.embeddingModelMismatch {
                        InlineNotice(
                            text: "The index was built with a different embedding model. Reindex everything for accurate semantic results.",
                            tone: .warning
                        )
                    }

                    HStack(spacing: 9) {
                        Button {
                            model.startIndexing(force: false)
                        } label: {
                            Label(model.isIndexing ? "Indexing…" : "Index Now",
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.primaryAction)
                        .disabled(model.isIndexing || model.folders.isEmpty)

                        Button("Reindex Everything") { model.reindexAll() }
                            .buttonStyle(.secondaryAction)
                            .disabled(model.isIndexing || model.folders.isEmpty)

                        if model.isIndexing {
                            Button("Pause") { model.cancelIndexing() }
                                .buttonStyle(.secondaryAction)
                        }

                        Spacer()

                        Button("Reset Index…") { showResetConfirmation = true }
                            .buttonStyle(.quietAction)
                    }
                }
            }
        }
    }

    private func indexStat(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(label)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
            }
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.label)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.raised.opacity(0.55))
        )
    }

    // MARK: - Privacy

    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: "On-device by design",
                subtitle: "Lumina has no account system, analytics, crash uploader, or sync service. The privacy boundary is enforced in code."
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    privacyPoint(
                        icon: "network.slash",
                        title: "Loopback inference only",
                        detail: "The inference client rejects any endpoint that is not localhost, 127.0.0.1, or ::1. Remote model servers cannot be configured by accident."
                    )
                    privacyPoint(
                        icon: "folder.badge.questionmark",
                        title: "Only your chosen folders",
                        detail: "The scanner starts from folders you explicitly add, skips hidden items, and excludes sensitive file types when that option is on."
                    )
                    privacyPoint(
                        icon: "cylinder.split.1x2",
                        title: "One local database",
                        detail: "Passages, vectors, notes, conversations, and file metadata live in a SQLite database in Application Support. There is no cloud copy."
                    )
                    privacyPoint(
                        icon: "trash",
                        title: "Delete everything yourself",
                        detail: "Reset the index or erase all Lumina data at any time. Original files are never deleted."
                    )
                }
            }

            SettingsCard(
                title: "Local data",
                subtitle: "If you back up this folder, your index and conversations are included in that backup."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Data folder")
                            .font(LuminaType.captionEmphasis)
                            .foregroundStyle(Palette.tertiary)
                        Text(model.dataDirectory.path)
                            .font(LuminaType.monoSmall)
                            .foregroundStyle(Palette.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 9) {
                        Button {
                            model.openDataFolder()
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.secondaryAction)

                        Button("Why Local?") { model.showWhyLocal = true }
                            .buttonStyle(.secondaryAction)

                        Spacer()

                        Text("\(model.stats.fileCount.formatted()) files · \(model.stats.chunkCount.formatted()) passages")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    }

                    InlineNotice(
                        text: "The database is not encrypted by Lumina. FileVault protects the disk at rest; anyone with access to your unlocked Mac and this folder can read the index.",
                        tone: .neutral
                    )
                }
            }

            SettingsCard(
                title: "Erase",
                subtitle: "Destructive actions are local, immediate, and cannot be undone."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRow(
                        title: "Reset the search index",
                        detail: "Clears files, passages, vectors, notes, and conversations. Keeps your folder selections and preferences."
                    ) {
                        Button("Reset Index…") { showResetConfirmation = true }
                            .buttonStyle(.secondaryAction)
                    }

                    DividerRow()

                    SettingsRow(
                        title: "Erase all Lumina data",
                        detail: "Also removes folder bookmarks and resets preferences. The app returns to its first-run state."
                    ) {
                        Button("Erase Everything…") { showEraseConfirmation = true }
                            .buttonStyle(.secondaryAction)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func privacyPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconTile(systemImage: icon, size: 27)
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

    // MARK: - About

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Lumina", subtitle: nil) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 16) {
                        LuminaMark(size: 58, showBackground: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lumina")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(Palette.label)
                            Text("Illuminate your local knowledge.")
                                .font(LuminaType.body)
                                .foregroundStyle(Palette.secondary)
                            Text("Version \(appVersion) · macOS 14+ · Apple silicon")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }
                        Spacer()
                    }

                    Text("A private, local-first knowledge workspace for the files already on your Mac. Index folders, search by meaning and keyword, ask grounded questions, and keep notes beside the sources. No account, no telemetry, no cloud upload.")
                        .font(LuminaType.body)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(
                title: "Built with",
                subtitle: "Lumina is a native SwiftUI app. The heavy lifting uses Apple frameworks and the local runtime you choose."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    aboutRow("SwiftUI & AppKit", "Windows, navigation, and native controls.")
                    aboutRow("SQLite + FTS5", "The local index, keyword search, notes, and conversations.")
                    aboutRow("Vision & PDFKit", "OCR, image classification, thumbnails, and PDF text.")
                    aboutRow("Speech", "Optional on-device audio transcription.")
                    aboutRow("Ollama or MLX", "Local chat and embedding models over loopback.")
                }
            }

            SettingsCard(
                title: "Scope",
                subtitle: "Lumina is deliberately small. These are the current boundaries."
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    scopeRow("No cloud sync, sharing, or collaboration.")
                    scopeRow("No continuous screen recording or background screenshots.")
                    scopeRow("No large models are bundled; you choose what to download.")
                    scopeRow("Media organization is tag- and metadata-based, not automatic folder moves.")
                    scopeRow("Audio and video transcription are opt-in and on-device.")
                }
            }

            SettingsCard(title: "Details", subtitle: nil) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Button {
                            copyDiagnostics()
                        } label: {
                            Label("Copy Diagnostics", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.secondaryAction)

                        Button("Open Data Folder") { model.openDataFolder() }
                            .buttonStyle(.secondaryAction)

                        Spacer()
                    }

                    Text("Diagnostics contain app version, macOS version, endpoint, model names, and index counts. They never contain file contents, paths, or conversations.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    DividerRow()

                    HStack {
                        Text("Released under the MIT License.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                        Spacer()
                        Text("Made for local knowledge.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
        }
    }

    private func aboutRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(LuminaType.captionEmphasis)
                .foregroundStyle(Palette.label)
                .frame(width: 142, alignment: .leading)
            Text(detail)
                .font(LuminaType.caption)
                .foregroundStyle(Palette.secondary)
        }
    }

    private func scopeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "circle.fill")
                .font(.system(size: 3.5))
                .foregroundStyle(Palette.tertiary)
                .padding(.top, 6)
            Text(text)
                .font(LuminaType.caption)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private var endpointIsLoopback: Bool {
        let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return false }
        return LocalInferenceClient.isLoopback(url)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version
    }

    private func updateRuntime(_ kind: RuntimeKind) {
        let wasOllamaDefault = settings.endpoint == "http://127.0.0.1:11434"
        let wasMLXDefault = settings.endpoint == "http://127.0.0.1:8080"
        settings.runtimeKind = kind
        switch kind {
        case .ollama where wasMLXDefault:
            settings.endpoint = "http://127.0.0.1:11434"
        case .openAICompatible where wasOllamaDefault:
            settings.endpoint = "http://127.0.0.1:8080"
        default:
            break
        }
        endpointDraft = settings.endpoint
        Task { await model.refreshSetup() }
    }

    private func applyEndpoint() {
        let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpointIsLoopback else {
            model.errorBanner = UserFacingError(
                "Remote endpoints are not allowed",
                message: "Lumina enforces loopback-only inference. Use localhost, 127.0.0.1, or ::1."
            )
            return
        }
        settings.endpoint = trimmed
        Task { await model.refreshSetup() }
    }

    private func copyDiagnostics() {
        let report = """
        Lumina \(appVersion)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Runtime: \(settings.runtimeKind.title) at \(settings.endpoint)
        Embedding model: \(settings.embeddingModel)
        Chat model: \(settings.chatModel)
        Files: \(model.stats.fileCount)
        Passages: \(model.stats.chunkCount)
        Vectors: \(model.stats.embeddedChunkCount)
        Folders: \(model.folders.count)
        """
        FileActions.copyText(report)
        model.infoMessage = "Diagnostics copied. They contain no file contents or conversations."
    }
}

// MARK: - Tab

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case models
    case indexing
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .indexing: "Indexing"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .models: "cpu"
        case .indexing: "text.magnifyingglass"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}

// MARK: - Model field

private struct SettingsModelField: View {
    let role: String
    let detail: String
    @Binding var text: String
    let installed: [LocalModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(role)
                    .font(LuminaType.bodyEmphasis)
                    .foregroundStyle(Palette.label)
                Spacer()
                if !installed.isEmpty {
                    Menu {
                        ForEach(installed) { model in
                            Button {
                                text = model.name
                            } label: {
                                if LocalInferenceClient.modelNamesMatch(model.name, text) {
                                    Label("\(model.name) · \(model.sizeDescription)", systemImage: "checkmark")
                                } else {
                                    Text("\(model.name) · \(model.sizeDescription)")
                                }
                            }
                        }
                    } label: {
                        Label("Installed", systemImage: "chevron.down")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Choose a model already installed in the runtime")
                }
            }

            HStack(spacing: 8) {
                TextField(role, text: $text)
                    .textFieldStyle(.plain)
                    .font(LuminaType.mono)
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.raised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Palette.separator.opacity(0.55), lineWidth: 0.7)
                    )

                if installed.contains(where: { LocalInferenceClient.modelNamesMatch($0.name, text) }) {
                    LuminaTag(title: "Installed", icon: "checkmark", tint: .green, filled: true)
                } else {
                    LuminaTag(title: "Missing", icon: nil, tint: .orange, filled: false)
                }
            }

            Text(detail)
                .font(LuminaType.caption)
                .foregroundStyle(Palette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
