import AppKit
import SwiftUI

// MARK: - Page chrome

struct PageHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                if let eyebrow {
                    SectionLabel(text: eyebrow)
                }
                Text(title)
                    .font(LuminaType.screenTitle)
                    .tracking(-0.35)
                    .foregroundStyle(Palette.label)
                if let subtitle {
                    Text(subtitle)
                        .font(LuminaType.body)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct ScreenScroll<Content: View>: View {
    var maxWidth: CGFloat = 1_060
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 34)
            .padding(.top, 28)
            .padding(.bottom, 42)
        }
        .background(Palette.canvas)
    }
}

// MARK: - Cards & rows

struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LuminaType.sectionTitle)
                    .foregroundStyle(Palette.label)
                if let subtitle {
                    Text(subtitle)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .luminaCard(padding: 18)
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LuminaType.bodyEmphasis)
                    .foregroundStyle(Palette.label)
                if let detail {
                    Text(detail)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            trailing()
        }
    }
}

struct ToggleSettingRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LuminaType.bodyEmphasis)
                    .foregroundStyle(Palette.label)
                Text(detail)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let icon: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.label)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(LuminaType.captionEmphasis)
                    .foregroundStyle(Palette.secondary)
                if let detail {
                    Text(detail)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.5), lineWidth: 0.7)
        )
    }
}

// MARK: - Files

struct FileGlyph: View {
    let kind: ContentKind
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color.accentColor.opacity(0.09))
            )
            .accessibilityHidden(true)
    }
}

/// Loads the small JPEG Lumina generated during indexing. The original file is
/// only read as a fallback for images that were indexed before thumbnails
/// existed, and never for other formats.
struct FileThumbnailView: View {
    let file: IndexedFile
    var cornerRadius: CGFloat = 8
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Palette.separator.opacity(0.11))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: file.kind.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.45), lineWidth: 0.6)
        )
        .task(id: file.thumbnailPath ?? file.path) {
            loadImage()
        }
        .accessibilityHidden(true)
    }

    @MainActor
    private func loadImage() {
        image = nil
        if let path = file.thumbnailPath,
           FileManager.default.fileExists(atPath: path),
           let loaded = NSImage(contentsOfFile: path) {
            image = loaded
            return
        }
        guard file.kind == .image,
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value < 40 * 1024 * 1024,
              let loaded = NSImage(contentsOfFile: file.path) else {
            return
        }
        image = loaded
    }
}

struct FileRow: View {
    let file: IndexedFile
    var subtitle: String?
    var snippet: String?
    var trailing: AnyView?
    var showsThumbnail: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showsThumbnail {
                FileThumbnailView(file: file)
                    .frame(width: 40, height: 40)
            } else {
                FileGlyph(kind: file.kind, size: 34)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(LuminaType.bodyEmphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                    if file.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let snippet {
                    HighlightedSnippet(text: snippet)
                } else {
                    Text(subtitle ?? defaultSubtitle)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                trailing
            } else {
                Text(file.modifiedAt.luminaShortDate)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 76, alignment: .trailing)
            }
        }
        .contentShape(Rectangle())
    }

    private var defaultSubtitle: String {
        var parts = [file.kind.displayName, file.fileSize.luminaByteSize]
        if let pageCount = file.pageCount { parts.append("\(pageCount) pages") }
        if let duration = file.duration { parts.append(ContentLocator.timecode(duration)) }
        return parts.joined(separator: " · ")
    }
}

struct FileCard: View {
    let file: IndexedFile
    var onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                FileThumbnailView(file: file, cornerRadius: 8)
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(file.name)
                            .font(LuminaType.bodyEmphasis)
                            .foregroundStyle(Palette.label)
                            .lineLimit(1)
                        if file.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(file.kind.displayName + " · " + file.modifiedAt.luminaShortDate)
                        .font(LuminaType.caption)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color.accentColor.opacity(0.45) : Palette.separator.opacity(0.5),
                        lineWidth: isHovering ? 1 : 0.7
                    )
            )
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Banners

struct ErrorBannerView: View {
    let error: UserFacingError
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red.opacity(0.9))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(LuminaType.bodyEmphasis)
                    .foregroundStyle(Palette.label)
                Text(error.message)
                    .font(LuminaType.caption)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.red.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

struct InfoBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(LuminaType.caption)
                .foregroundStyle(Palette.label)
                .lineLimit(2)
            Spacer(minLength: 10)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

struct InlineNotice: View {
    enum Tone {
        case neutral
        case warning
        case success

        var icon: String {
            switch self {
            case .neutral: "info.circle"
            case .warning: "exclamationmark.triangle"
            case .success: "checkmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .neutral: .accentColor
            case .warning: .orange
            case .success: .green
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: tone.icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(tone.color)
                .padding(.top, 1)
            Text(text)
                .font(LuminaType.caption)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tone.color.opacity(0.06))
        )
    }
}

// MARK: - Metadata & labels

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(LuminaType.caption)
                .foregroundStyle(Palette.tertiary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(LuminaType.caption)
                .foregroundStyle(Palette.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StatusPill: View {
    let text: String
    var tone: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tone)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Palette.separator.opacity(0.11))
        )
    }
}

// MARK: - Markdown

struct LuminaMarkdownText: View {
    let text: String

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: text,
                options: .init(
                    allowsExtendedAttributes: false,
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(LuminaType.body)
        .lineSpacing(3.5)
        .foregroundStyle(Palette.label)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Formatting

extension Date {
    var luminaShortDate: String {
        if Calendar.current.isDateInToday(self) {
            return formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        }
        if Calendar.current.component(.year, from: self) == Calendar.current.component(.year, from: Date()) {
            return formatted(.dateTime.month(.abbreviated).day())
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }

    var luminaRelative: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 45 { return "Just now" }
        if interval < 3_600 { return "\(max(1, Int(interval / 60))) min ago" }
        if Calendar.current.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var luminaFullDate: String {
        formatted(date: .long, time: .shortened)
    }

    var luminaDayHeader: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}

extension Int64 {
    var luminaByteSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// MARK: - File actions

enum FileActions {
    @MainActor
    static func open(_ file: IndexedFile) {
        NSWorkspace.shared.open(file.url)
    }

    @MainActor
    static func reveal(_ file: IndexedFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    static func copyPath(_ file: IndexedFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.path, forType: .string)
    }

    static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Small controls

struct CopyIconButton: View {
    let text: String
    var label: String = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            FileActions.copyText(text)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10.5, weight: .medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(copied ? Color.green : Palette.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct TextLinkButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9.5, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

struct DividerRow: View {
    var body: some View {
        Hairline()
            .padding(.vertical, 2)
    }
}
