import SwiftUI

/// Onboarding and diagnostics in one place. The guide is deliberately explicit:
/// a local-first app should tell people exactly which process is running, which
/// files were downloaded, and where the data lives.
struct SetupGuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up Lumina")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.label)
                    Text("Four local pieces: a model runtime, two models, a folder, and a quick check.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refreshSetup() }
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondaryAction)
                .disabled(model.isRefreshingSetup)
                .help("Re-check the local runtime and installed models")
            }

            runtimeStep
            modelStep
            folderStep
            verificationStep

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
                Text("Everything above happens on this Mac. No account is created.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                Button("Why local?") {
                    model.showWhyLocal = true
                }
                .buttonStyle(.quietAction)
            }
            .padding(.top, 2)
        }
    }

    // MARK: Step 1 — runtime

    private var runtimeStep: some View {
        SetupStepCard(
            number: 1,
            title: "Connect a local model runtime",
            subtitle: runtimeSubtitle,
            isComplete: model.setup.isReachable,
            isBusy: model.isRefreshingSetup
        ) {
            if model.setup.isReachable {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text(runtimeReadyText)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                    Spacer()
                    if settings.runtimeKind == .ollama, model.setup.installation.appURL != nil {
                        Button("Open Ollama") { model.openOllama() }
                            .buttonStyle(.quietAction)
                    }
                }
            } else if settings.runtimeKind == .openAICompatible {
                VStack(alignment: .leading, spacing: 10) {
                    InlineNotice(
                        text: model.setup.error ?? "Start your local MLX / OpenAI-compatible server at \(settings.endpoint), then check again.",
                        tone: .warning
                    )
                    CommandRow(command: "See Settings → Models to change the endpoint and model names.")
                    Button("Open Model Settings") {
                        model.route = .settings
                    }
                    .buttonStyle(.secondaryAction)
                }
            } else if model.setup.installation.isInstalled {
                VStack(alignment: .leading, spacing: 10) {
                    InlineNotice(
                        text: model.setup.error ?? "Ollama is installed but Lumina can't reach it. Open Ollama and wait for the menu-bar icon to appear.",
                        tone: .warning
                    )
                    HStack(spacing: 9) {
                        Button("Open Ollama") { model.openOllama() }
                            .buttonStyle(.primaryAction)
                        Button("Download again") { model.openOllamaDownload() }
                            .buttonStyle(.secondaryAction)
                    }
                    DisclosureGroup("Run Ollama from a terminal instead") {
                        CommandRow(command: "ollama serve")
                            .padding(.top, 6)
                    }
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ollama runs the language and embedding models locally. It is a normal Mac app with no account and no cloud requirement.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) {
                        Button("Download Ollama") { model.openOllamaDownload() }
                            .buttonStyle(.primaryAction)
                        Button("Check again") {
                            Task { await model.refreshSetup() }
                        }
                        .buttonStyle(.secondaryAction)
                    }
                    DisclosureGroup("Install with Homebrew") {
                        CommandRow(command: "brew install ollama")
                            .padding(.top, 6)
                    }
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    if let error = model.setup.error {
                        InlineNotice(text: error, tone: .warning)
                    }
                }
            }
        }
    }

    private var runtimeSubtitle: String {
        if model.setup.isReachable {
            return "Connected at \(settings.endpoint)"
        }
        switch settings.runtimeKind {
        case .ollama:
            return "Ollama provides both models and stays on this Mac."
        case .openAICompatible:
            return "Any OpenAI-compatible server listening on loopback works."
        }
    }

    private var runtimeReadyText: String {
        let version = model.setup.installation.version.map { " \($0)" } ?? ""
        switch settings.runtimeKind {
        case .ollama:
            return "Ollama\(version) is reachable at \(settings.endpoint)"
        case .openAICompatible:
            return "Local server is reachable at \(settings.endpoint)"
        }
    }

    // MARK: Step 2 — models

    private var modelStep: some View {
        SetupStepCard(
            number: 2,
            title: "Install two local models",
            subtitle: "One understands language, one turns text into searchable vectors.",
            isComplete: model.isEmbeddingModelInstalled && model.isChatModelInstalled,
            isBusy: model.isPullingModels
        ) {
            let recommendation = settings.recommendation

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Mac has \(recommendation.memoryDescription) of unified memory")
                            .font(LuminaType.captionEmphasis)
                            .foregroundStyle(Palette.label)
                        Text("Recommended: \(recommendation.chatModel) + \(recommendation.embeddingModel) · about \(String(format: "%.1f", recommendation.chatApproxSizeGB)) GB for the chat model. \(recommendation.rationale)")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 6) {
                    modelStatusRow(
                        name: settings.embeddingModel,
                        role: "Embedding",
                        detail: "Converts passages and questions into vectors."
                    )
                    modelStatusRow(
                        name: settings.chatModel,
                        role: "Chat",
                        detail: "Writes grounded answers and summaries."
                    )
                }

                if model.isPullingModels {
                    pullProgressView
                }

                if !model.isFullyConfigured {
                    HStack(spacing: 9) {
                        if settings.runtimeKind == .ollama {
                            Button {
                                model.pullRecommendedModels()
                            } label: {
                                Label("Download Recommended Models", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.primaryAction)
                            .disabled(model.isPullingModels || !model.setup.isReachable)
                        }

                        if let installed = installedAlternative {
                            Button("Use Installed Models") {
                                settings.embeddingModel = installed.embedding
                                settings.chatModel = installed.chat
                                model.infoMessage = "Using models already installed on this Mac."
                                Task { await model.verifySetup() }
                            }
                            .buttonStyle(.secondaryAction)
                        }

                        if !model.setup.isReachable {
                            Text("Connect the runtime first.")
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.tertiary)
                        }
                    }

                    DisclosureGroup("Manual install commands") {
                        VStack(spacing: 6) {
                            ForEach(recommendation.pullCommands, id: \.self) { command in
                                CommandRow(command: command)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                }

                if settings.runtimeKind == .openAICompatible {
                    InlineNotice(
                        text: "Automatic downloads are Ollama-only. Load or download models in your local server, then use Refresh in Settings → Models.",
                        tone: .neutral
                    )
                }

                if let error = model.setupError, model.setup.isReachable {
                    InlineNotice(text: error, tone: .warning)
                }

                if !recommendation.hasAdequateMemory {
                    InlineNotice(
                        text: "Less than 8 GB is available to the model server. Smaller context windows and closing memory-heavy apps will help.",
                        tone: .warning
                    )
                }
            }
        }
    }

    private var installedAlternative: (embedding: String, chat: String)? {
        guard let embedding = RuntimeDiscovery.firstEmbeddingModel(in: model.setup.models),
              let chat = RuntimeDiscovery.firstChatModel(in: model.setup.models) else {
            return nil
        }
        let embeddingInstalled = model.isEmbeddingModelInstalled
        let chatInstalled = model.isChatModelInstalled
        guard !embeddingInstalled || !chatInstalled else { return nil }
        return (embedding, chat)
    }

    private func modelStatusRow(name: String, role: String, detail: String) -> some View {
        let installed = model.setup.models.first {
            LocalInferenceClient.modelNamesMatch($0.name, name)
        }
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(installed == nil ? Palette.separator.opacity(0.18) : Color.green.opacity(0.13))
                    .frame(width: 22, height: 22)
                Image(systemName: installed == nil ? "arrow.down" : "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(installed == nil ? Palette.tertiary : .green)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(LuminaType.monoSmall)
                        .foregroundStyle(Palette.label)
                    Text(role)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Palette.separator.opacity(0.13)))
                }
                Text(detail)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(installed.map(\.sizeDescription) ?? "Not installed")
                .font(LuminaType.caption)
                .foregroundStyle(installed == nil ? Palette.tertiary : Palette.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Palette.raised.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.42), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var pullProgressView: some View {
        if let progress = model.pullProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
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

    // MARK: Step 3 — folders

    private var folderStep: some View {
        SetupStepCard(
            number: 3,
            title: "Choose what Lumina can read",
            subtitle: "Only the folders you add are scanned. Everything else is invisible to the index.",
            isComplete: model.hasFolders,
            isBusy: false
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if model.folders.isEmpty {
                    Text("Good starting points: Documents, a notes folder, a project directory, or an archive of PDFs and screenshots.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.folders.enumerated()), id: \.element.id) { index, folder in
                            if index > 0 { Hairline() }
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(folder.name)
                                        .font(LuminaType.captionEmphasis)
                                        .foregroundStyle(Palette.label)
                                    Text(folder.path)
                                        .font(LuminaType.caption)
                                        .foregroundStyle(Palette.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                if !folder.isEnabled {
                                    LuminaTag(title: "Paused", icon: nil, tint: .secondary, filled: false)
                                }
                            }
                            .padding(.vertical, 7)
                        }
                    }
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.raised.opacity(0.65))
                    )
                }

                HStack(spacing: 9) {
                    Button {
                        model.chooseFolder()
                    } label: {
                        Label(model.hasFolders ? "Add Another Folder" : "Choose a Folder", systemImage: "plus")
                    }
                    .buttonStyle(.primaryAction)

                    if model.hasFolders {
                        Button {
                            model.startIndexing(force: false)
                        } label: {
                            Label(model.isIndexing ? "Indexing…" : "Index Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.secondaryAction)
                        .disabled(model.isIndexing)
                    }

                    if model.hasFolders, model.isFullyConfigured, settings.autoIndexEnabled {
                        Text("Indexing starts automatically after a folder is added.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    } else if model.hasFolders {
                        Text("Keyword indexing works before models are installed.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    }
                }
            }
        }
    }

    // MARK: Step 4 — verification

    private var verificationStep: some View {
        SetupStepCard(
            number: 4,
            title: "Verify the local pipeline",
            subtitle: "Sends one sentence to the embedding model and checks that a vector comes back.",
            isComplete: isVerified,
            isBusy: model.verificationState == .testing
        ) {
            VStack(alignment: .leading, spacing: 10) {
                switch model.verificationState {
                case .idle:
                    Text("This is a good final check after installing models. It uses no network beyond loopback.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .testing:
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("Testing the local embedding model…")
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
                        Text("Install both models to enable verification.")
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.tertiary)
                    }

                    Spacer()

                    if model.isFullyConfigured, model.hasFolders {
                        Button("Index Now") {
                            model.startIndexing(force: false)
                        }
                        .buttonStyle(.primaryAction)
                    }
                }
            }
        }
    }

    private var isVerified: Bool {
        if case .success = model.verificationState { return true }
        return false
    }
}

// MARK: - Step chrome

private struct SetupStepCard<Content: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    let isComplete: Bool
    let isBusy: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            indicator
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(LuminaType.bodyEmphasis)
                            .foregroundStyle(Palette.label)
                        Text(subtitle)
                            .font(LuminaType.caption)
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if isBusy {
                        ProgressView().controlSize(.mini)
                    } else if isComplete {
                        StatusPill(text: "Done", tone: .green)
                    }
                }
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .luminaCard(padding: 16)
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(isComplete ? Color.green.opacity(0.13) : Color.accentColor.opacity(0.09))
                .frame(width: 27, height: 27)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.top, 1)
    }
}
