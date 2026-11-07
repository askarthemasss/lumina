import Carbon
import Foundation

/// Registers a single system-wide shortcut with the Carbon hot key API.
///
/// Carbon remains the correct API for global shortcuts on macOS: it does not
/// require Accessibility permissions and coexists with the system's own
/// shortcut handling. The actual event handler only forwards a notification;
/// all UI work remains on the main actor.
@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isHandlerInstalled = false

    private static let hotKeySignature: OSType = 0x4C4D4E41 // 'LMNA'
    private static let hotKeyIdentifier: UInt32 = 1

    // The manager lives for the lifetime of the process, so the Carbon hot key
    // and handler are released by the system when the app exits. An explicit
    // deinit would be nonisolated under Swift 6 and cannot touch these opaque
    // Carbon references safely.

    /// Returns false when macOS (or another app) already owns the combination.
    @discardableResult
    func register(_ shortcut: GlobalShortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()
        guard shortcut.hasModifier else { return false }

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else { return false }
        hotKeyRef = reference
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            luminaHotKeyCallback,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        isHandlerInstalled = status == noErr
    }

    fileprivate func handlePress() {
        NotificationCenter.default.post(name: .luminaShowQuickSearch, object: nil)
    }
}

/// C callback for the Carbon event loop. The manager is retained by the app
/// delegate for the lifetime of the process, so the unretained pointer is safe.
private func luminaHotKeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.handlePress()
    }
    return noErr
}
