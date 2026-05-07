//
//  AppDelegate.swift
//  Flow Drop
//
//  Created by Tamas Rares on 05.05.2026.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate, HoverHintDelegate {

  var shelfWindowController: NSWindowController?
  private var hoverHintWindow: NSWindow?

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
    setupHoverHintWindow()
  }

  // MARK: - Hover Hint Window
  private func setupHoverHintWindow() {
    let hintView = HoverHintView(frame: NSRect(x: 0, y: 0, width: 60, height: 120))
    hintView.delegate = self

    hoverHintWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 120),
                               styleMask: [],
                               backing: .buffered,
                               defer: false)
    hoverHintWindow?.isOpaque = false
    hoverHintWindow?.backgroundColor = .clear
    hoverHintWindow?.level = .floating
    hoverHintWindow?.contentView = hintView
    hoverHintWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary]

    // Position near the shelf location (top-right area)
    if let screen = NSScreen.main {
      let hintX = screen.frame.maxX - 80
      let hintY = screen.frame.midY - 60
      hoverHintWindow?.setFrameOrigin(NSPoint(x: hintX, y: hintY))
    }

    hoverHintWindow?.makeKeyAndOrderFront(self)
  }

  // MARK: - HoverHintDelegate
  func hoverHintDidEnter() {
    print("[AppDelegate] hover hint entered, showing shelf")
    showShelf()
  }

  func hoverHintDidExit() {
    print("[AppDelegate] hover hint exited")
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
      }
  }

  // MARK: - Shelf Control
  private func showShelf() {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController,
            let window = shelfWindowController?.window else { return }

      window.level = .popUpMenu      // Better than .floating for this use case
      window.alphaValue = 0.0
      window.orderFrontRegardless()

      hoverHintWindow?.orderOut(self)  // Hide hint when shelf is visible

      vc.showWithAnimation()
  }

  private func hideShelf() {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController else { return }

      vc.hideWithAnimation {
          self.isDragging = false
          self.hoverHintWindow?.orderFrontRegardless()  // Show hint again
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
