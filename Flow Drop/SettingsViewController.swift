//
//  SettingsViewController.swift
//  Flow Drop
//
//  Created by Tamas Rares on 10.05.2026.
//

import Cocoa

class SettingsViewController: NSViewController {

  @IBOutlet weak var leftCheckBoxButton: NSButton!
  @IBOutlet weak var rightCheckBoxButton: NSButton!
  @IBOutlet weak var clearBoardButton: NSButton!
  @IBOutlet weak var keepDataCheckBox: NSButton!

  override func viewDidLoad() {
    super.viewDidLoad()
    reloadFromUserDefaults()
  }

  /// Refresh controls from `UserDefaults` (e.g. when opening Preferences from the menu bar).
  func reloadFromUserDefaults() {
    applySavedSettingsToUI()
  }


  @IBAction func onLeftButtonClicked(_ sender: Any) {
    leftCheckBoxButton.state = .on
    rightCheckBoxButton.state = .off
    UserDefaults.standard.set(AppSettings.ShelfSide.left.rawValue, forKey: AppSettings.Keys.shelfSide)
    NotificationCenter.default.post(name: .shelfSideChanged, object: nil)
  }
  
  @IBAction func onRightButtonClicked(_ sender: Any) {
    rightCheckBoxButton.state = .on
    leftCheckBoxButton.state = .off
    UserDefaults.standard.set(AppSettings.ShelfSide.right.rawValue, forKey: AppSettings.Keys.shelfSide)
    NotificationCenter.default.post(name: .shelfSideChanged, object: nil)
  }

  @IBAction func onClearBoardButtonCLicked(_ sender: Any) {
    NotificationCenter.default.post(name: .shelfClearRequested, object: nil)
  }
  
  @IBAction func onKeepDataButtonClicked(_ sender: Any) {
    let keepData = keepDataCheckBox.state == .on
    UserDefaults.standard.set(keepData, forKey: AppSettings.Keys.keepData)
    NotificationCenter.default.post(name: .shelfKeepDataChanged, object: nil)
  }

  private func applySavedSettingsToUI() {
    let defaults = UserDefaults.standard
    let savedSide = defaults.string(forKey: AppSettings.Keys.shelfSide) ?? AppSettings.ShelfSide.left.rawValue
    let side = AppSettings.ShelfSide(rawValue: savedSide) ?? .left
    leftCheckBoxButton.state = side == .left ? .on : .off
    rightCheckBoxButton.state = side == .right ? .on : .off

    if defaults.object(forKey: AppSettings.Keys.keepData) == nil {
      defaults.set(true, forKey: AppSettings.Keys.keepData)
    }
    keepDataCheckBox.state = defaults.bool(forKey: AppSettings.Keys.keepData) ? .on : .off
  }
}
