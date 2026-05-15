//
//  ShelfWindowController.swift
//  Flow Drop
//

import Cocoa

/// Shared chrome for the shelf window or panel (level, fullscreen-space behavior, floating panel flags).
enum ShelfWindowConfiguration {
    static func applySharedChrome(to window: NSWindow) {
        window.level = ShelfViewController.shelfWindowLevel
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
        }
        window.alphaValue = ShelfViewController.restingAlpha
        window.ignoresMouseEvents = false
        window.isRestorable = false
    }
}

/// Storyboard loads a plain `NSWindow`; `NSPanel.init(coder:)` is unavailable for Swift subclasses, so we swap in
/// a programmatic `NSPanel` here. That matches how overlay HUDs are expected to behave over other apps’ fullscreen.
final class ShelfWindowController: NSWindowController {

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let oldWindow = window else { return }

        if oldWindow is NSPanel {
            ShelfWindowConfiguration.applySharedChrome(to: oldWindow)
            return
        }

        guard let vc = contentViewController else { return }

        let panel = NSPanel(
            contentRect: oldWindow.frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        ShelfWindowConfiguration.applySharedChrome(to: panel)
        panel.title = oldWindow.title
        panel.contentViewController = vc
        panel.isReleasedWhenClosed = oldWindow.isReleasedWhenClosed

        window = panel
        oldWindow.orderOut(nil)
    }
}
