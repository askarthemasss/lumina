import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            conversationSidebar
                .frame(width: 238)
            Rectangle()
                .fill(Palette.separator.opacity(0.55))
                .frame(width: 0.7)
            conversationPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.canvas)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                composerFocused = true
            }
        }
    }

    // MARK: Sidebar

    private var conversationSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(LuminaType.sectionTitle)
                    .foregroundStyle(Palette.label)
                Spacer()
                Button {
                    model.newConversation(mode: model.chatMode)
                    composerFocused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Palette.separator.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("New conversation")
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 12)

            if model.conversations.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No conversations yet")
                        .font(LuminaType.captionEmphasis)
                        .foregroundStyle(Palette.secondary)
                    Text("Ask a question and the conversation will appear here.")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }

            Spacer(minLength: 0)
            sidebarFooter
        }
        .background(Palette.sidebar.opacity(0.7))
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        let isActive = model.activeConversation?.id == conversation.id
        return Button {
            Task { await model.selectConversation(conversation) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: conversation.mode.systemImage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : Palette.tertiary)
                    .frame(width: 14)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(conversation.mode.title)
                        Text("·")
                        Text(conversation.updatedAt.luminaRelative)
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Conversation", role: .destructive) {
                Task { await model.deleteConversation(conversation) }
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Hairline()
            HStack(spacing: 6) {
                StatusDot(color: model.isFullyConfigured ? .green : .orange)
                Text(settings.chatModel)
                    .font(LuminaType.monoSmall)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Text("Answers stay on this Mac.")
                .font(LuminaType.caption)
                .foregroundStyle(Palette.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Conversation

    private var conversationPane: some View {
        VStack(spacing: 0) {
            chatHeader
            Hairline()
            messages
            Hairline()
            composer
        }
    }

    private var chatHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Lumina")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text(model.activeConversation?.title ?? "A grounded conversation with your local index")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Picker("Mode", selection: Binding(
                get: { model.chatMode },
                set: { model.setChatMode($0) }
            )) {
                ForEach(ChatMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 302)
            .help("Answer, summarize, extract into a table, or compare sources")

            Button {
                model.newConversation(mode: model.chatMode)
                composerFocused = true
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.secondaryAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !model.isFullyConfigured {
                        configurationNotice
                    }

                    if model.chatMessages.isEmpty && !model.isStreaming {
                        chatEmptyState
                    } else {
                        ForEach(model.chatMessages) { message in
                            ChatMessageView(message: message) { citation in
                                Task { await model.showFileInLibrary(id: citation.fileID) }
                            }
                        }

                        if model.isStreaming {
                            streamingBubble
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .frame(maxWidth: 790)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.chatMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.streamingText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.isStreaming) { _, _ in
                scrollToBottom(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var configurationNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.setup.isReachable ? "cpu" : "bolt.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Local chat model needed")
                    .font(LuminaType.bodyEmphasis)
                    .foregroundStyle(Palette.label)
                Text("Install \(settings.chatModel) and the embedding model, then Lumina can answer from your index without leaving this Mac.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Setup") {
                model.route = .home
            }
            .buttonStyle(.secondaryAction)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.7)
        )
    }

    private var chatEmptyState: some View {
        VStack(spacing: 16) {
            LuminaMark(size: 46)
            VStack(spacing: 5) {
                Text("Ask your library")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text("Lumina retrieves a handful of relevant passages, sends only those to the local chat model, and cites its sources.")
                    .font(LuminaType.body)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: 7) {
                suggestionButton("Summarize the most relevant documents in my library.", icon: "text.alignleft")
                suggestionButton("What decisions or action items have I saved?", icon: "checklist")
                suggestionButton("Extract key dates, names, and amounts into a table.", icon: "tablecells")
                suggestionButton("Compare my latest notes and highlight the differences.", icon: "arrow.left.arrow.right")
            }
            .frame(maxWidth: 460)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private func suggestionButton(_ prompt: String, icon: String) -> some View {
        Button {
            model.sendMessage(prompt)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)
                Text(prompt)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(0.45), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .disabled(!model.isFullyConfigured || model.isStreaming)
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            LuminaMark(size: 22)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Lumina")
                        .font(LuminaType.captionEmphasis)
                        .foregroundStyle(Palette.label)
                    Text("writing locally")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                    ProgressView().controlSize(.mini)
                }

                if model.streamingText.isEmpty {
                    Text("Reading the retrieved passages…")
                        .font(LuminaType.body)
                        .foregroundStyle(Palette.secondary)
                } else {
                    LuminaMarkdownText(text: model.streamingText)
                }

                if !model.chatSources.isEmpty {
                    Text("Grounded in \(model.chatSources.count) local passage\(model.chatSources.count == 1 ? "" : "s")")
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                }
            }
            Spacer(minLength: 20)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 7) {
            if let chatError = model.chatError {
                InlineNotice(text: chatError, tone: .warning)
                    .frame(maxWidth: 790)
            }

            HStack(alignment: .bottom, spacing: 9) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Ask about anything in your library…")
                            .font(LuminaType.body)
                            .foregroundStyle(Palette.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .font(LuminaType.body)
                        .foregroundStyle(Palette.label)
                        .scrollContentBackground(.hidden)
                        .focused($composerFocused)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(minHeight: 58, maxHeight: 108)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            composerFocused ? Color.accentColor.opacity(0.55) : Palette.separator.opacity(0.55),
                            lineWidth: composerFocused ? 1.1 : 0.7
                        )
                )

                if model.isStreaming {
                    Button {
                        model.cancelChat()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.label)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(Palette.separator.opacity(0.18))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating")
                    .padding(.bottom, 1)
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(canSend ? Color.accentColor : Palette.separator.opacity(0.55))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Send (⌘↩)")
                    .padding(.bottom, 1)
                }
            }
            .frame(maxWidth: 790)

            HStack {
                Text("⌘↩ to send · Answers are generated from retrieved passages, not the open web.")
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                if !model.chatMessages.isEmpty {
                    Button("Clear conversation") {
                        model.newConversation(mode: model.chatMode)
                    }
                    .buttonStyle(.quietAction)
                }
            }
            .frame(maxWidth: 790)
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 15)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isStreaming
            && model.isFullyConfigured
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isStreaming else { return }
        draft = ""
        model.sendMessage(text)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }
}

// MARK: - Message

private struct ChatMessageView: View {
    let message: ChatMessage
    let onCitation: (Citation) -> Void

    var body: some View {
        if message.role == .user {
            userMessage
        } else {
            assistantMessage
        }
    }

    private var userMessage: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(LuminaType.body)
                    .foregroundStyle(Palette.label)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.accentColor.opacity(0.09))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.13), lineWidth: 0.6)
                    )
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .padding(.trailing, 2)
            }
        }
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            LuminaMark(size: 22)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Lumina")
                        .font(LuminaType.captionEmphasis)
                        .foregroundStyle(Palette.label)
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                    if message.isError {
                        LuminaTag(title: "Error", icon: nil, tint: .red, filled: true)
                    }
                }

                if message.isError {
                    Text(message.content)
                        .font(LuminaType.body)
                        .foregroundStyle(.red.opacity(0.9))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                } else {
                    LuminaMarkdownText(text: message.content)
                }

                if !message.citations.isEmpty {
                    sources
                }

                HStack(spacing: 10) {
                    Button {
                        FileActions.copyText(message.content)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 20)
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Sources")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 218), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(message.citations.enumerated()), id: \.offset) { index, citation in
                    Button {
                        onCitation(citation)
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color.accentColor.opacity(0.1)))
                            Image(systemName: citation.kind.systemImage)
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.tertiary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(citation.fileName)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Palette.secondary)
                                    .lineLimit(1)
                                if let locator = citation.locator.compactDisplay {
                                    Text(locator)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Palette.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Palette.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Palette.separator.opacity(0.4), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(citation.quote)
                }
            }
        }
        .padding(.top, 2)
    }
}
