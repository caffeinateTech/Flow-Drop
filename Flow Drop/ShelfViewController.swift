//
//  ShelfViewController.swift
//  Flow Drop
//
//  Created by Tamas Rares on 05.05.2026.
//

import Cocoa

class ShelfViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Make background transparent
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
    }

    // This will be called when window is created
    func setupWindow() {
        guard let window = view.window else { return }

        window.level = .floating          // Always on top
        window.isMovableByWindowBackground = true   // Drag by clicking anywhere
        window.hasShadow = true
        window.backgroundColor = .clear
        window.isOpaque = false
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupWindow()
    }
}
