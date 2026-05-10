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
  private var mouseUpMonitor: Any?
  private var lastDragPasteboardChangeCount = 0
  private var isDragging = false

  // MARK: - Application Lifecycle

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Load Window Controller
    let storyboard = NSStoryboard(name: "Main", bundle: nil)
    shelfWindowController = storyboard.instantiateController(withIdentifier: "ShelfWindowController") as? NSWindowController

    showShelfOnFocusedScreen()

    setupGlobalDragMonitoring()
    setupMouseUpMonitor()
    setupScreenChangeMonitoring()
  }

  // MARK: - Global Drag Monitoring (The Magic)
  private func setupGlobalDragMonitoring() {
      dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .mouseMoved]) { [weak self] _ in
          guard let self = self else { return }
          self.updateShelfScreenAndHover(using: NSEvent.mouseLocation)

          let dragPB = NSPasteboard(name: .drag)

          if dragPB.changeCount != self.lastDragPasteboardChangeCount {
              self.lastDragPasteboardChangeCount = dragPB.changeCount
              if !self.isDragging {
                  self.isDragging = true
                  self.setShelfHighlighted(true)
              }
          }
      }
  }

  // MARK: - Shelf Control
  private func showShelfOnFocusedScreen() {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController,
            let window = shelfWindowController?.window else { return }

      window.level = .floating
      window.orderFrontRegardless()
      vc.setHighlighted(false, animated: false)
      positionShelfOnFocusedScreen(animated: false)
  }

  private func setShelfHighlighted(_ highlighted: Bool) {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController else { return }
      vc.setHighlighted(highlighted)
  }

  private func positionShelfOnFocusedScreen(animated: Bool) {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController else { return }
      let mouseLocation = NSEvent.mouseLocation
      if let currentScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
          vc.positionOnLeft(of: currentScreen, animated: animated)
      } else if let mainScreen = NSScreen.main {
          vc.positionOnLeft(of: mainScreen, animated: animated)
      }
  }

  private func updateShelfScreenAndHover(using mouseLocation: NSPoint) {
      guard let window = shelfWindowController?.window else { return }

      if let currentScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }),
         window.screen !== currentScreen {
          positionShelfOnFocusedScreen(animated: true)
      }

      if isDragging {
          setShelfHighlighted(true)
      } else {
          let hoverFrame = window.frame.insetBy(dx: -8, dy: -8)
          setShelfHighlighted(hoverFrame.contains(mouseLocation))
      }
  }

  // Handle mouse up to hide shelf when drag ends
  private func setupMouseUpMonitor() {
    mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self?.isDragging = false
        self?.setShelfHighlighted(false)
      }
    }
  }

  private func setupScreenChangeMonitoring() {
      NotificationCenter.default.addObserver(
          forName: NSWorkspace.activeSpaceDidChangeNotification,
          object: nil,
          queue: .main
      ) { [weak self] _ in
          self?.positionShelfOnFocusedScreen(animated: true)
      }

      NotificationCenter.default.addObserver(
          forName: NSApplication.didChangeScreenParametersNotification,
          object: nil,
          queue: .main
      ) { [weak self] _ in
          self?.positionShelfOnFocusedScreen(animated: true)
      }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    if let monitor = dragMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = mouseUpMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
