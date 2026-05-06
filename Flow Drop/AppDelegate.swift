//
//  AppDelegate.swift
//  Flow Drop
//
//  Created by Tamas Rares on 05.05.2026.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

  var shelfWindowController: NSWindowController?

  // Drag Detection
  private var dragMonitor: Any?
  private var lastDragPasteboardChangeCount = 0
  private var isDragging = false

  // MARK: - Application Lifecycle

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Load Window Controller
    let storyboard = NSStoryboard(name: "Main", bundle: nil)
    shelfWindowController = storyboard.instantiateController(withIdentifier: "ShelfWindowController") as? NSWindowController

    if let window = shelfWindowController?.window {
      window.orderOut(self)  // Hide initially
    }

    setupGlobalDragMonitoring()
  }

  // MARK: - Global Drag Monitoring (The Magic)

  private func setupGlobalDragMonitoring() {
    // Remove old monitor if exists
    if let monitor = dragMonitor {
      NSEvent.removeMonitor(monitor)
    }

    dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
      guard let self = self else { return }

      let dragPasteboard = NSPasteboard(name: .drag)
      let currentChangeCount = dragPasteboard.changeCount

      // Detect NEW drag session
      if currentChangeCount != self.lastDragPasteboardChangeCount {
        self.lastDragPasteboardChangeCount = currentChangeCount

        // This is likely the start of a drag
        if !self.isDragging {
          self.isDragging = true
          self.showShelf()
        }
      }
    }
  }

  // MARK: - Shelf Control

  private func showShelf() {
    guard let window = shelfWindowController?.window else { return }

    // Position near cursor
    if let cursorLocation = NSEvent.mouseLocation {
      let screenFrame = NSScreen.main?.frame ?? NSScreen.screens[0].frame
      let desiredX = min(max(cursorLocation.x - 200, 50), screenFrame.width - 450)
      let desiredY = min(max(cursorLocation.y - 100, 50), screenFrame.height - 600)

      window.setFrameOrigin(NSPoint(x: desiredX, y: desiredY))
    }

    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(self)
  }

  private func hideShelf() {
    isDragging = false
    shelfWindowController?.window?.orderOut(self)
  }

  // Handle mouse up to hide shelf when drag ends
  private func setupMouseUpMonitor() {
    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self?.hideShelf()
      }
    }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    if let monitor = dragMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
