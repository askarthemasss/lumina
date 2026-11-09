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

/// Renders the block structure that `Text(AttributedString)` discards:
/// headings, lists, quotes, fenced code, and pipe tables. Inline styling still
/// comes from Foundation's Markdown parser, so links and emphasis behave the
/// same as the rest of the app.
struct LuminaMarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .font(LuminaType.body)
        .lineSpacing(3.5)
        .foregroundStyle(Palette.label)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, content):
            inline(content)
                .font(.system(
                    size: level <= 1 ? 18 : (level == 2 ? 15.5 : 13.5),
                    weight: .semibold
                ))
                .padding(.top, level <= 2 ? 3 : 1)

        case let .paragraph(content):
            inline(content)
                .fixedSize(horizontal: false, vertical: true)

        case let .bullets(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 8)
                        inline(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case let .numbered(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(Palette.tertiary)
                            .monospacedDigit()
                            .frame(minWidth: 17, alignment: .trailing)
                        inline(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case let .quote(content):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 2.5)
                inline(content)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 1)

        case let .code(content):
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.separator.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.separator.opacity(0.45), lineWidth: 0.7)
                )

        case let .table(header, rows):
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        inline(cell)
                            .font(LuminaType.captionEmphasis)
                    }
                }
                Hairline()
                    .gridCellColumns(max(1, header.count))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inline(cell)
                                .font(LuminaType.caption)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.separator.opacity(0.07))
            )

        case .rule:
            Hairline()
                .padding(.vertical, 2)
        }
    }

    private func inline(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(
                allowsExtendedAttributes: false,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return Text(attributed)
        }
        return Text(source)
    }
}

// MARK: - Markdown blocks

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case quote(String)
    case code(String)
    case table(header: [String], rows: [[String]])
    case rule

    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                var code: [String] = []
                index += 1
                while index < lines.count,
                      lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isTableSeparator(after: index, in: lines) {
                let header = cells(in: lines[index])
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    rows.append(normalized(cells(in: row), count: header.count))
                    index += 1
                }
                if !header.isEmpty {
                    blocks.append(.table(header: header, rows: rows))
                }
                continue
            }

            if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
                continue
            }

            if let item = bullet(from: line) {
                var items = [item]
                index += 1
                while index < lines.count, let next = bullet(from: lines[index]) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.bullets(items))
                continue
            }

            if let item = numbered(from: line) {
                var items = [item]
                index += 1
                while index < lines.count, let next = numbered(from: lines[index]) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            if let quoted = quoteLine(from: line) {
                var parts = [quoted]
                index += 1
                while index < lines.count, let next = quoteLine(from: lines[index]) {
                    parts.append(next)
                    index += 1
                }
                blocks.append(.quote(parts.joined(separator: " ")))
                continue
            }

            var paragraph: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || startsBlock(at: index, in: lines) {
                    break
                }
                paragraph.append(nextTrimmed)
                index += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
        }

        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes.count, text)
    }

    private static func bullet(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2 else { return nil }
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            let text = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func numbered(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else {
            return nil
        }
        let text = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text)
    }

    private static func quoteLine(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "---" || compact == "***" || compact == "___"
    }

    private static func isTableSeparator(after index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let separator = cells(in: lines[index + 1])
        guard !separator.isEmpty else { return false }
        return separator.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            return !stripped.isEmpty
                && stripped.allSatisfy { $0 == "-" }
        }
    }

    private static func cells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func normalized(_ cells: [String], count: Int) -> [String] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private static func startsBlock(at index: Int, in lines: [String]) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("```") { return true }
        if heading(from: trimmed) != nil || isRule(trimmed) { return true }
        if isTableSeparator(after: index, in: lines) { return true }
        return bullet(from: lines[index]) != nil
            || numbered(from: lines[index]) != nil
            || quoteLine(from: lines[index]) != nil
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
