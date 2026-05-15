//
//  KeyboardStashMonitor.swift
//  Flow Drop
//

import AppKit
import Carbon.HIToolbox

/// Stash shortcut: **⌃⇧S** (Control+Shift+S). Registered with Carbon so it works system-wide
/// (NSEvent global key monitors often never fire without Accessibility).
final class KeyboardStashMonitor {

    /// Shown in settings / docs — Control+Shift+S (“S” for Shelf).
    static let shortcutDisplayName = "⌃⇧S"

    private static let hotKeySignature: OSType = 0x4644_5354 // 'FDST'
    private static let hotKeyID: UInt32 = 1
    private static let keyCode = UInt32(kVK_ANSI_S)
    private static let modifiers = UInt32(controlKey | shiftKey)

    private static weak var activeInstance: KeyboardStashMonitor?

    private weak var shelfViewController: ShelfViewController?
    private var localMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var lastTriggerTime: TimeInterval = 0
    private var isCapturing = false

    init(shelfViewController: ShelfViewController) {
        self.shelfViewController = shelfViewController
    }

    func start() {
        Self.activeInstance = self
        registerCarbonHotKey()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matchesShortcut(event) {
                self.performStash()
                return nil
            }
            return event
        }
        print("[KeyboardStashMonitor] stash shortcut \(Self.shortcutDisplayName) (Carbon hot key + local fallback)")
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        self.localMonitor = nil
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        self.hotKeyRef = nil
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        self.eventHandlerRef = nil
        if Self.activeInstance === self { Self.activeInstance = nil }
    }

    private func registerCarbonHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard status == noErr else {
            print("[KeyboardStashMonitor] InstallEventHandler failed: \(status)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let registerStatus = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            print("[KeyboardStashMonitor] RegisterEventHotKey failed: \(registerStatus)")
        }
    }

    private static let carbonHotKeyHandler: EventHandlerUPP = { _, event, _ in
        guard let monitor = activeInstance else { return OSStatus(eventNotHandledErr) }

        var received = EventHotKeyID()
        let paramStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &received
        )
        guard paramStatus == noErr,
              received.signature == hotKeySignature,
              received.id == hotKeyID else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async {
            monitor.performStash()
        }
        return noErr
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.keyCode == UInt16(Self.keyCode) else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.control)
            && flags.contains(.shift)
            && !flags.contains(.command)
            && !flags.contains(.option)
    }

    private func performStash() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerTime > 0.35, !isCapturing else { return }
        lastTriggerTime = now
        isCapturing = true

        print("[KeyboardStashMonitor] \(Self.shortcutDisplayName) — capturing selection…")
        SelectionStashService.captureSelection { [weak self] items in
            defer { self?.isCapturing = false }
            guard let vc = self?.shelfViewController else { return }
            DispatchQueue.main.async {
                vc.stashFromKeyboardShortcut(pasteboardItems: items)
            }
        }
    }
}
