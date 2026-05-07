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
    setupMouseUpMonitor()
  }

  // MARK: - Global Drag Monitoring (The Magic)
  private func setupGlobalDragMonitoring() {
      dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .mouseMoved]) { [weak self] event in
          guard let self = self else { return }

          let dragPB = NSPasteboard(name: .drag)

          if dragPB.changeCount != self.lastDragPasteboardChangeCount {
              self.lastDragPasteboardChangeCount = dragPB.changeCount
              if !self.isDragging {
                  self.isDragging = true
                  self.showShelf()
              }
          }

          // Hover detection over shelf area
          if event.type == .mouseMoved, !self.isDragging,
             let window = self.shelfWindowController?.window,
             !window.isVisible {
              let mouseLocation = NSEvent.mouseLocation
              let hoverFrame = window.frame.insetBy(dx: -20, dy: -20)
              if hoverFrame.contains(mouseLocation) {
                  print("[AppDelegate] hover detected over shelf area, showing shelf")
                  self.showShelf()
              }
          }
      }
  }

  // MARK: - Shelf Control
  private func showShelf() {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController,
            let window = shelfWindowController?.window else { return }

      window.level = .popUpMenu      // Better than .floating for this use case
      window.alphaValue = 0.0
      window.orderFrontRegardless()

      vc.showWithAnimation()
  }

  private func hideShelf() {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController else { return }

      vc.hideWithAnimation {
          self.isDragging = false
      }
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
