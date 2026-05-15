//
//  StatusBarController.swift
//  Flow Drop
//

import AppKit

/// Menu bar extra: click opens menu with Preferences and Quit.
final class StatusBarController: NSObject {

  private var statusItem: NSStatusItem?
  private var settingsWindowController: NSWindowController?

  func install() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem = item

    guard let button = item.button else { return }
    if let image = menuBarImage() {
      button.image = image
    }
    button.toolTip = "Flow Drop"

    let menu = NSMenu()
    let preferences = NSMenuItem(
      title: "Preferences…",
      action: #selector(showPreferences),
      keyEquivalent: ""
    )
    preferences.target = self
    menu.addItem(preferences)
    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: "Quit Flow Drop",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: ""
    )
    quit.target = NSApp
    menu.addItem(quit)

    item.menu = menu
  }

  func uninstall() {
    if let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
    }
    statusItem = nil
    settingsWindowController = nil
  }

  @objc func showPreferences() {
    if settingsWindowController == nil {
      let storyboard = NSStoryboard(name: "Main", bundle: nil)
      settingsWindowController = storyboard.instantiateController(
        withIdentifier: "SettingsWindowController"
      ) as? NSWindowController
      settingsWindowController?.window?.title = "Flow Drop Preferences"
    }

    guard let windowController = settingsWindowController,
          let settingsVC = windowController.contentViewController as? SettingsViewController else {
      return
    }

    settingsVC.reloadFromUserDefaults()
    NSApp.activate(ignoringOtherApps: true)
    windowController.showWindow(nil)
    windowController.window?.center()
    windowController.window?.makeKeyAndOrderFront(nil)
  }

  private func menuBarImage() -> NSImage? {
    guard let image = NSImage(named: "statusbar_icon") else {
      return nil
    }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
  }
}
