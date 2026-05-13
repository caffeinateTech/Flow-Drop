//
//  AppDelegate.swift
//  Flow Drop
//
//  Created by Tamas Rares on 05.05.2026.
//

import Cocoa

enum AppSettings {
  enum Keys {
    static let shelfSide = "shelf.side"
    static let keepData = "shelf.keepData"
    static let persistedItems = "shelf.persistedItems"
  }

  enum ShelfSide: String {
    case left
    case right
  }

  struct PersistedShelfItem: Codable {
    enum Kind: String, Codable {
      case fileURL
      case url
      case text
      case imageTIFF
    }

    let id: String
    let kind: Kind
    let stringValue: String?
    let dataValue: Data?
    /// Security-scoped bookmark so sandboxed drags work after relaunch.
    let bookmarkData: Data?

    init(id: String, kind: Kind, stringValue: String?, dataValue: Data?, bookmarkData: Data? = nil) {
      self.id = id
      self.kind = kind
      self.stringValue = stringValue
      self.dataValue = dataValue
      self.bookmarkData = bookmarkData
    }
  }
}

extension Notification.Name {
  static let shelfSideChanged = Notification.Name("shelfSideChanged")
  static let shelfKeepDataChanged = Notification.Name("shelfKeepDataChanged")
  static let shelfClearRequested = Notification.Name("shelfClearRequested")
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

  var shelfWindowController: NSWindowController?

  // Drag Detection
  private var dragMonitor: Any?
  private var mouseUpMonitor: Any?
  private var lastDragPasteboardChangeCount = 0
  private var isDragging = false
  private var lastTargetScreenName: String?
  /// Stable display id from `NSScreen` so we do not jump back to main on space/screen notifications.
  private var lastShelfScreenNumber: UInt32?
  private var clickMonitorGlobal: Any?
  private var clickMonitorLocal: Any?

  private func screenNumber(for screen: NSScreen) -> UInt32? {
      (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  // MARK: - Application Lifecycle

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: AppSettings.Keys.shelfSide) == nil {
      defaults.set(AppSettings.ShelfSide.left.rawValue, forKey: AppSettings.Keys.shelfSide)
    }
    if defaults.object(forKey: AppSettings.Keys.keepData) == nil {
      defaults.set(true, forKey: AppSettings.Keys.keepData)
    }

    // Load Window Controller
    let storyboard = NSStoryboard(name: "Main", bundle: nil)
    shelfWindowController = storyboard.instantiateController(withIdentifier: "ShelfWindowController") as? NSWindowController

    showShelfOnFocusedScreen()

    setupGlobalDragMonitoring()
    setupMouseUpMonitor()
    setupClickToAnchorScreen()
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
      positionShelfOnFocusedScreen(animated: false, forceReposition: true)
  }

  private func setShelfHighlighted(_ highlighted: Bool) {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController else { return }
      vc.setHighlighted(highlighted)
  }

  /// Shelf stays on the last display the user **clicked** on, or main until the first click.
  private func activeScreenForShelf() -> NSScreen? {
      if let n = lastShelfScreenNumber,
         let match = NSScreen.screens.first(where: { screenNumber(for: $0) == n }) {
          return match
      }
      return NSScreen.main ?? NSScreen.screens.first
  }

  private func positionShelfOnFocusedScreen(animated: Bool, forceReposition: Bool = false, targetScreen: NSScreen? = nil) {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController else { return }
      let sideRaw = UserDefaults.standard.string(forKey: AppSettings.Keys.shelfSide) ?? AppSettings.ShelfSide.left.rawValue
      let side = AppSettings.ShelfSide(rawValue: sideRaw) ?? .left
      guard let targetScreen = targetScreen ?? activeScreenForShelf() else { return }
      let targetName = targetScreen.localizedName
      let targetNum = screenNumber(for: targetScreen)

      if !forceReposition, let tn = targetNum, tn == lastShelfScreenNumber {
          return
      }

      print("[AppDelegate] positionShelf target=\(targetName) id=\(String(describing: targetNum)) side=\(side.rawValue) force=\(forceReposition) animated=\(animated)")
      vc.position(on: targetScreen, side: side, animated: false, hideDuringMove: true)
      lastTargetScreenName = targetName
      if let targetNum {
          lastShelfScreenNumber = targetNum
      }
  }

  private func updateShelfScreenAndHover(using mouseLocation: NSPoint) {
      guard let vc = shelfWindowController?.contentViewController as? ShelfViewController else { return }

      if isDragging {
          setShelfHighlighted(true)
      } else if vc.isPostDropGraceActive() {
          setShelfHighlighted(true)
      } else {
          // Do not use `window.frame` here: it changes every frame during width animation and makes hover flicker.
          setShelfHighlighted(vc.globalPointInteractsWithShelfHover(mouseLocation))
      }
  }

  /// Reposition shelf to the screen that received this click (user “activated” that display). Not cursor-hover.
  private func setupClickToAnchorScreen() {
      let matching: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      let handler: (NSEvent) -> Void = { [weak self] _ in
          guard let self else { return }
          let globalPoint = NSEvent.mouseLocation
          guard let screen = NSScreen.screens.first(where: { NSMouseInRect(globalPoint, $0.frame, false) }) else { return }
          let name = screen.localizedName
          let num = self.screenNumber(for: screen)
          if let num, let last = self.lastShelfScreenNumber, num == last { return }
          print("[AppDelegate] clickAnchor screen=\(name) id=\(String(describing: num)) (user click)")
          self.positionShelfOnFocusedScreen(animated: false, forceReposition: true, targetScreen: screen)
      }
      clickMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: matching) { handler($0) }
      clickMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: matching) { event in
          handler(event)
          return event
      }
  }

  // After a system drag ends, clear drag state and re-sync hover (do not force-collapse while pointer is still over the shelf).
  private func setupMouseUpMonitor() {
    mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self?.isDragging = false
        self?.updateShelfScreenAndHover(using: NSEvent.mouseLocation)
      }
    }
  }

  private func setupScreenChangeMonitoring() {
      NotificationCenter.default.addObserver(
          forName: NSWorkspace.activeSpaceDidChangeNotification,
          object: nil,
          queue: .main
      ) { [weak self] _ in
          self?.positionShelfOnFocusedScreen(animated: false, forceReposition: true)
      }

      NotificationCenter.default.addObserver(
          forName: NSApplication.didChangeScreenParametersNotification,
          object: nil,
          queue: .main
      ) { [weak self] _ in
          self?.positionShelfOnFocusedScreen(animated: false, forceReposition: true)
      }

      NotificationCenter.default.addObserver(
          forName: .shelfSideChanged,
          object: nil,
          queue: .main
      ) { [weak self] _ in
          print("[AppDelegate] received shelfSideChanged")
          self?.positionShelfOnFocusedScreen(animated: false, forceReposition: true)
      }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    if let monitor = dragMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = mouseUpMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = clickMonitorGlobal {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = clickMonitorLocal {
      NSEvent.removeMonitor(monitor)
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
