import SwiftUI
import AppKit

// MARK: - Palette

/// A restrained, native palette. Lumina deliberately avoids decorative
/// gradients and translucent "AI" styling. System colors keep contrast
/// correct in both appearances.
enum Palette {
    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var card: Color { Color(nsColor: .controlBackgroundColor) }
    static var raised: Color { Color(nsColor: .textBackgroundColor) }
    static var sidebar: Color { Color(nsColor: .underPageBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var label: Color { Color(nsColor: .labelColor) }
    static var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiary: Color { Color(nsColor: .tertiaryLabelColor) }
    static var selection: Color { Color(nsColor: .selectedContentBackgroundColor) }

    static let ink = Color(hex: 0x111920)
    static let ivory = Color(hex: 0xEDE7DB)
    static let beam = Color(hex: 0xD3A45E)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension AccentChoice {
    var color: Color {
        switch self {
        case .sapphire: Color(hex: 0x3F6F9C)
        case .tide: Color(hex: 0x2F7A78)
        case .moss: Color(hex: 0x5C7448)
        case .clay: Color(hex: 0x9A5A45)
        case .amber: Color(hex: 0xA8782F)
        case .graphite: Color(hex: 0x5D646B)
        }
    }

    /// A slightly lighter accent for dark appearances and selection fills.
    var softColor: Color {
        color.opacity(0.12)
    }
}

// MARK: - Type

enum LuminaType {
    static func display(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static let screenTitle = Font.system(size: 27, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 15, weight: .semibold, design: .default)
    static let body = Font.system(size: 13.5, weight: .regular, design: .default)
    static let bodyEmphasis = Font.system(size: 13.5, weight: .medium, design: .default)
    static let caption = Font.system(size: 11.5, weight: .regular, design: .default)
    static let captionEmphasis = Font.system(size: 11.5, weight: .medium, design: .default)
    static let eyebrow = Font.system(size: 10.5, weight: .semibold, design: .default)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

// MARK: - Reusable modifiers

private struct LuminaCardModifier: ViewModifier {
    var padding: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(colorScheme == .dark ? 0.55 : 0.65), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.035), radius: 2, y: 1)
    }
}

extension View {
    func luminaCard(padding: CGFloat = 18) -> some View {
        modifier(LuminaCardModifier(padding: padding))
    }

    func screenTitleStyle() -> some View {
        font(LuminaType.screenTitle)
            .foregroundStyle(Palette.label)
    }

    func subtleBorder(_ radius: CGFloat = 10) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.55), lineWidth: 0.7)
        )
    }
}

// MARK: - Buttons

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.4))
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Palette.label)
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.raised.opacity(isEnabled ? 1 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(0.7), lineWidth: 0.7)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct QuietActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Palette.separator.opacity(0.25) : .clear)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Small components

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(LuminaType.eyebrow)
            .tracking(0.7)
            .foregroundStyle(Palette.tertiary)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.separator.opacity(0.55))
            .frame(height: 0.7)
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct LuminaTag: View {
    let title: String
    var icon: String?
    var tint: Color = .accentColor
    var filled: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(filled ? tint : Palette.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(filled ? tint.opacity(0.1) : Palette.separator.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(filled ? tint.opacity(0.16) : .clear, lineWidth: 0.6)
        )
    }
}

struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.separator.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Palette.separator.opacity(0.5), lineWidth: 0.6)
            )
    }
}

struct IconTile: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.opacity(0.1))
            )
            .accessibilityHidden(true)
    }
}

struct EmptyStateView<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.tertiary)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.separator.opacity(0.1))
                )
            Text(title)
                .font(LuminaType.sectionTitle)
                .foregroundStyle(Palette.label)
            Text(message)
                .font(LuminaType.body)
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 2)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

struct CommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(LuminaType.mono)
                .foregroundStyle(Palette.label)
                .textSelection(.enabled)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Color.green : Palette.secondary)
            .frame(width: 66, alignment: .trailing)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
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

// MARK: - Search field

struct LuminaSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var autoFocus: Bool = false
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(focused ? Color.accentColor : Palette.tertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.label)
                .focused($focused)
                .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
            }

            if focused, let onCancel {
                Button(action: onCancel) {
                    KeyCap(label: "esc")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.65) : Palette.separator.opacity(0.6),
                              lineWidth: focused ? 1.2 : 0.7)
        )
        .onAppear {
            guard autoFocus else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                focused = true
            }
        }
    }
}

// MARK: - Keyboard shortcut formatting

enum ShortcutFormatter {
    static func display(keyCode: UInt32, modifiers: UInt32, fallbackKey: String?) -> String {
        var result = ""
        if modifiers & GlobalShortcut.control != 0 { result += "⌃" }
        if modifiers & GlobalShortcut.option != 0 { result += "⌥" }
        if modifiers & GlobalShortcut.shift != 0 { result += "⇧" }
        if modifiers & GlobalShortcut.command != 0 { result += "⌘" }
        result += fallbackKey ?? keyName(for: keyCode)
        return result
    }

    static func keyName(for code: UInt32) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 18: return "1"; case 19: return "2"; case 20: return "3"
        case 21: return "4"; case 22: return "6"; case 23: return "5"; case 24: return "="
        case 25: return "9"; case 26: return "7"; case 27: return "-"; case 28: return "8"
        case 29: return "0"; case 30: return "]"; case 31: return "O"; case 32: return "U"
        case 33: return "["; case 34: return "I"; case 35: return "P"; case 37: return "L"
        case 38: return "J"; case 39: return "'"; case 40: return "K"; case 41: return ";"
        case 42: return "\\"; case 43: return ","; case 44: return "/"; case 45: return "N"
        case 46: return "M"; case 47: return "."; case 50: return "`"
        default: return "Key \(code)"
        }
    }
}

// MARK: - Progress

struct ThinProgressBar: View {
    var value: Double?
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.separator.opacity(0.24))
                if let value {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, proxy.size.width * min(1, max(0, value))))
                } else {
                    Capsule()
                        .fill(tint.opacity(0.7))
                        .frame(width: proxy.size.width * 0.28)
                        .blur(radius: 2)
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }
}

// MARK: - Snippets

/// Search snippets use [[brackets]] around matched terms. This view parses
/// those markers into emphasized text without injecting HTML or markdown.
struct HighlightedSnippet: View {
    let text: String

    var body: some View {
        composed
            .font(LuminaType.body)
            .foregroundStyle(Palette.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var composed: Text {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        guard normalized.contains("[[") else { return Text(normalized) }

        var output = Text("")
        var remainder = normalized[...]
        while let open = remainder.range(of: "[["),
              let close = remainder.range(of: "]]", range: open.upperBound..<remainder.endIndex) {
            output = output + Text(remainder[..<open.lowerBound])
            let highlighted = remainder[open.upperBound..<close.lowerBound]
            output = output + Text(highlighted).bold().foregroundColor(.accentColor)
            remainder = remainder[close.upperBound...]
        }
        output = output + Text(remainder)
        return output
    }
}
