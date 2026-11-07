import Foundation
import SwiftUI

// MARK: - Appearance

enum AppearanceChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AccentChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case sapphire
    case tide
    case moss
    case clay
    case amber
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sapphire: "Sapphire"
        case .tide: "Tide"
        case .moss: "Moss"
        case .clay: "Clay"
        case .amber: "Amber"
        case .graphite: "Graphite"
        }
    }
}

// MARK: - Shortcut

struct GlobalShortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let command: UInt32 = 256
    static let shift: UInt32 = 512
    static let option: UInt32 = 2048
    static let control: UInt32 = 4096

    static let `default` = GlobalShortcut(
        keyCode: 49, // Space
        modifiers: command | shift,
        display: "⇧⌘Space"
    )

    static let presets: [GlobalShortcut] = [
        .default,
        GlobalShortcut(keyCode: 49, modifiers: option, display: "⌥Space"),
        GlobalShortcut(keyCode: 49, modifiers: control, display: "⌃Space"),
        GlobalShortcut(keyCode: 49, modifiers: control | option, display: "⌃⌥Space")
    ]

    var hasModifier: Bool {
        modifiers & (Self.command | Self.shift | Self.option | Self.control) != 0
    }
}

// MARK: - Settings

/// App preferences are a single Codable snapshot stored in UserDefaults.
/// Views use the computed properties below, which write through to the snapshot
/// and persist immediately. There are intentionally no analytics or account keys.
@MainActor
@Observable
final class AppSettings {
    private struct Snapshot: Codable {
        var runtimeKind: RuntimeKind
        var endpoint: String
        var embeddingModel: String
        var chatModel: String
        var accent: AccentChoice
        var appearance: AppearanceChoice
        var shortcut: GlobalShortcut
        var ocrEnabled: Bool
        var visionCaptionsEnabled: Bool
        var transcriptionEnabled: Bool
        var indexCodeEnabled: Bool
        var skipSensitiveFiles: Bool
        var maxFileSizeMB: Int
        var excludedPatternsText: String
        var autoIndexEnabled: Bool
        var autoScanMinutes: Int
        var hasDismissedWelcome: Bool

        static func initial() -> Snapshot {
            let recommendation = ModelRecommendation.recommended(
                forMemory: ProcessInfo.processInfo.physicalMemory
            )
            return Snapshot(
                runtimeKind: .ollama,
                endpoint: "http://127.0.0.1:11434",
                embeddingModel: recommendation.embeddingModel,
                chatModel: recommendation.chatModel,
                accent: .sapphire,
                appearance: .system,
                shortcut: .default,
                ocrEnabled: true,
                visionCaptionsEnabled: false,
                transcriptionEnabled: false,
                indexCodeEnabled: true,
                skipSensitiveFiles: true,
                maxFileSizeMB: 512,
                excludedPatternsText: "",
                autoIndexEnabled: true,
                autoScanMinutes: 15,
                hasDismissedWelcome: false
            )
        }
    }

    private static let storageKey = "lumina.settings.v1"
    @ObservationIgnored private let defaults: UserDefaults
    private var snapshot: Snapshot

    var runtimeKind: RuntimeKind {
        get { snapshot.runtimeKind }
        set { snapshot.runtimeKind = newValue; save() }
    }

    var endpoint: String {
        get { snapshot.endpoint }
        set { snapshot.endpoint = newValue; save() }
    }

    var embeddingModel: String {
        get { snapshot.embeddingModel }
        set { snapshot.embeddingModel = newValue; save() }
    }

    var chatModel: String {
        get { snapshot.chatModel }
        set { snapshot.chatModel = newValue; save() }
    }

    var accent: AccentChoice {
        get { snapshot.accent }
        set { snapshot.accent = newValue; save() }
    }

    var appearance: AppearanceChoice {
        get { snapshot.appearance }
        set { snapshot.appearance = newValue; save() }
    }

    var shortcut: GlobalShortcut {
        get { snapshot.shortcut }
        set {
            guard newValue != snapshot.shortcut else { return }
            snapshot.shortcut = newValue
            save()
            NotificationCenter.default.post(name: .luminaShortcutChanged, object: nil)
        }
    }

    var ocrEnabled: Bool {
        get { snapshot.ocrEnabled }
        set { snapshot.ocrEnabled = newValue; save() }
    }

    var visionCaptionsEnabled: Bool {
        get { snapshot.visionCaptionsEnabled }
        set { snapshot.visionCaptionsEnabled = newValue; save() }
    }

    var transcriptionEnabled: Bool {
        get { snapshot.transcriptionEnabled }
        set { snapshot.transcriptionEnabled = newValue; save() }
    }

    var indexCodeEnabled: Bool {
        get { snapshot.indexCodeEnabled }
        set { snapshot.indexCodeEnabled = newValue; save() }
    }

    var skipSensitiveFiles: Bool {
        get { snapshot.skipSensitiveFiles }
        set { snapshot.skipSensitiveFiles = newValue; save() }
    }

    var maxFileSizeMB: Int {
        get { snapshot.maxFileSizeMB }
        set { snapshot.maxFileSizeMB = min(4096, max(1, newValue)); save() }
    }

    var excludedPatternsText: String {
        get { snapshot.excludedPatternsText }
        set { snapshot.excludedPatternsText = newValue; save() }
    }

    var autoIndexEnabled: Bool {
        get { snapshot.autoIndexEnabled }
        set { snapshot.autoIndexEnabled = newValue; save() }
    }

    var autoScanMinutes: Int {
        get { snapshot.autoScanMinutes }
        set { snapshot.autoScanMinutes = min(120, max(5, newValue)); save() }
    }

    var hasDismissedWelcome: Bool {
        get { snapshot.hasDismissedWelcome }
        set { snapshot.hasDismissedWelcome = newValue; save() }
    }

    var excludedPatterns: [String] {
        snapshot.excludedPatternsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var recommendation: ModelRecommendation {
        .recommended(forMemory: ProcessInfo.processInfo.physicalMemory)
    }

    var inferenceConfiguration: InferenceConfiguration {
        InferenceConfiguration(
            runtime: runtimeKind,
            endpoint: endpoint,
            embeddingModel: embeddingModel,
            chatModel: chatModel
        )
    }

    var indexingOptions: IndexingOptions {
        IndexingOptions(
            maxFileSizeBytes: Int64(maxFileSizeMB) * 1024 * 1024,
            ocrEnabled: ocrEnabled,
            visionCaptionsEnabled: visionCaptionsEnabled,
            transcriptionEnabled: transcriptionEnabled,
            indexCode: indexCodeEnabled,
            skipSensitive: skipSensitiveFiles,
            excludedPatterns: excludedPatterns
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = .initial()
        }
    }

    /// Adopt the models Lumina recommends for this Mac, without touching
    /// the user's other indexing preferences.
    func applyRecommendedModels() {
        let rec = recommendation
        snapshot.embeddingModel = rec.embeddingModel
        snapshot.chatModel = rec.chatModel
        save()
    }

    func markWelcomeDismissed() {
        snapshot.hasDismissedWelcome = true
        save()
    }

    func resetPreferences() {
        snapshot = .initial()
        save()
        NotificationCenter.default.post(name: .luminaShortcutChanged, object: nil)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

extension Notification.Name {
    static let luminaShortcutChanged = Notification.Name("com.lumina.shortcutChanged")
    static let luminaHotKeyPressed = Notification.Name("com.lumina.hotKeyPressed")
    static let luminaShowQuickSearch = Notification.Name("com.lumina.showQuickSearch")
    static let luminaOpenMainWindow = Notification.Name("com.lumina.openMainWindow")
    static let luminaAddFolder = Notification.Name("com.lumina.addFolder")
}
