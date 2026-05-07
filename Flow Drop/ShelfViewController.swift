//
//  ShelfViewController.swift
//  Flow Drop
//
//  Created by Tamas Rares on 05.05.2026.
//

import Cocoa

class ShelfViewController: NSViewController, DropAreaViewDelegate {

    private var visualEffectView: NSVisualEffectView!
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!

    private var items: [Any] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        print("[ShelfViewController] viewDidLoad")
        setupUI()
        configureDropAreaDelegate()
    }

    private func configureDropAreaDelegate() {
        if let dropArea = findDropArea(in: view) {
            dropArea.delegate = self
            print("[ShelfViewController] DropAreaView delegate connected")
        } else {
            print("[ShelfViewController] WARNING: DropAreaView delegate not found")
        }
    }

    private func findDropArea(in view: NSView) -> DropAreaView? {
        if let dropArea = view as? DropAreaView {
            return dropArea
        }

        for subview in view.subviews {
            if let dropArea = findDropArea(in: subview) {
                return dropArea
            }
        }
        return nil
    }

    private func setupUI() {
        // Background
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(visualEffectView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: view.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Scroll View
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        // Stack View
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView

        // Ensure stackView has proper width
        stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true

        print("[ShelfViewController] setupUI completed")
    }

    func didReceiveItems(_ pasteboardItems: [NSPasteboardItem]) {
        print("[ShelfViewController] didReceiveItems count = \(pasteboardItems.count)")

        for (index, item) in pasteboardItems.enumerated() {
            print("[ShelfViewController] item[\(index)] types = \(item.types)")
            if let urlString = item.string(forType: .fileURL), let url = URL(string: urlString) {
                print("[ShelfViewController] parsed fileURL: \(url)")
                addItemToShelf(url)
            } else if let text = item.string(forType: .string) {
                print("[ShelfViewController] parsed string: \(text)")
                addItemToShelf(text)
            } else if let imageData = item.data(forType: .tiff) ?? item.data(forType: .png), let image = NSImage(data: imageData) {
                print("[ShelfViewController] parsed image data")
                addItemToShelf(image)
            } else if let urlString = item.string(forType: .URL), let url = URL(string: urlString) {
                print("[ShelfViewController] parsed URL: \(url)")
                addItemToShelf(url)
            } else {
                print("[ShelfViewController] could not parse pasteboard item")
            }
        }
    }

    private func addItemToShelf(_ item: Any) {
        print("[ShelfViewController] addItemToShelf called with \(item)")
        let itemView = ShelfItemView(frame: NSRect(x: 0, y: 0, width: 340, height: 50))
        itemView.configure(with: item)
        stackView.addArrangedSubview(itemView)
        items.append(item)

        // Force layout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.stackView.needsLayout = true
            self.stackView.layoutSubtreeIfNeeded()
            self.scrollView.needsLayout = true
            print("[ShelfViewController] layout updated, stackView frame: \(self.stackView.frame), item count: \(self.stackView.arrangedSubviews.count)")
            self.view.needsDisplay = true
        }

        // Scroll to bottom
        if let docView = scrollView.documentView {
            let bottom = NSPoint(x: 0, y: docView.bounds.height)
            docView.scroll(bottom)
        }
    }

    // Animations
    func showWithAnimation() {
        guard let window = view.window else { return }
        window.alphaValue = 0.0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }

    func hideWithAnimation(completion: (() -> Void)? = nil) {
        guard let window = view.window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1.0
            completion?()
        })
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
        print("[ShelfViewController] viewDidAppear")
        setupWindow()
    }
}
