//
//  ShelfItemView.swift
//  Flow Drop
//
//  Created by Tamas Rares on 06.05.2026.
//

import Cocoa

class ShelfItemView: NSView, NSDraggingSource {

    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField()
    private let removeButton = NSButton()

    var representedObject: Any?
    var itemID: String?
    var persistedKind: AppSettings.PersistedShelfItem.Kind?
    var onRemove: ((ShelfItemView) -> Void)?
    private var securityScopedAccessActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
      wantsLayer = true
      layer?.isOpaque = true
      layer?.cornerRadius = 10
      layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor  // Good visibility
      layer?.borderWidth = 0.5
      layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        // Icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconImageView)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.textColor = .white
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Remove Button
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .inline
        removeButton.title = "×"
        removeButton.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        removeButton.isBordered = false
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Fixed height for stack view layout
        self.heightAnchor.constraint(equalToConstant: 50).isActive = true

        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Hover effect
        let trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    func configure(with item: Any) {
        print("[ShelfItemView] configure called with \(item)")
        representedObject = item

        if let url = item as? URL {
            let pathExtension = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "tiff", "bmp"].contains(pathExtension) {
                // Load actual image for image files
                if let image = NSImage(contentsOf: url) {
                    titleLabel.stringValue = url.lastPathComponent
                    iconImageView.image = image
                    print("[ShelfItemView] loaded image for \(url.lastPathComponent)")
                } else {
                    titleLabel.stringValue = url.lastPathComponent
                    iconImageView.image = NSWorkspace.shared.icon(forFile: url.path)
                    print("[ShelfItemView] failed to load image, using icon for \(url.lastPathComponent)")
                }
            } else {
                titleLabel.stringValue = url.lastPathComponent
                iconImageView.image = NSWorkspace.shared.icon(forFile: url.path)
                print("[ShelfItemView] using icon for \(url.lastPathComponent)")
            }
        } else if let text = item as? String {
            titleLabel.stringValue = text.prefix(35) + (text.count > 35 ? "..." : "")
            iconImageView.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil)
            print("[ShelfItemView] configured text item")
        } else if let image = item as? NSImage {
            titleLabel.stringValue = "Image"
            iconImageView.image = image
            print("[ShelfItemView] configured image item")
        } else {
            titleLabel.stringValue = "Unknown Item"
            iconImageView.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
            print("[ShelfItemView] configured unknown item")
        }

        self.needsDisplay = true
    }

    @objc private func removeTapped() {
        onRemove?(self)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        // Start dragging if not clicking remove button
        let location = convert(event.locationInWindow, from: nil)
        if !removeButton.frame.contains(location) {
            startDrag(with: event)
        }
    }

    private func startDrag(with event: NSEvent) {
        guard let representedObject = representedObject else { return }

        let kind = persistedKind
        print("[ShelfItemView] startDrag id=\(itemID ?? "nil") kind=\(kind?.rawValue ?? "unknown")")

        let draggingItem: NSDraggingItem
        if let url = representedObject as? URL {
            if kind == .url {
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .URL)
                draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            } else {
                if url.startAccessingSecurityScopedResource() {
                    securityScopedAccessActive = true
                    print("[ShelfItemView] security scope started for drag")
                } else {
                    print("[ShelfItemView] WARNING: startAccessingSecurityScopedResource failed (sandbox bookmark may be missing)")
                }
                draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            }
        } else if let text = representedObject as? String {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(text, forType: .string)
            draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        } else if let image = representedObject as? NSImage, let tiffData = image.tiffRepresentation {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(tiffData, forType: .tiff)
            draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        } else {
            return
        }

        draggingItem.setDraggingFrame(bounds, contents: iconImageView.image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func endSecurityScopedAccessIfNeeded() {
        guard securityScopedAccessActive, let url = representedObject as? URL, url.isFileURL else { return }
        url.stopAccessingSecurityScopedResource()
        securityScopedAccessActive = false
        print("[ShelfItemView] security scope ended after drag")
    }

    deinit {
        endSecurityScopedAccessIfNeeded()
    }

    // NSDraggingSource
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endSecurityScopedAccessIfNeeded()
        if operation.rawValue != 0 {
            // Successfully dragged out, remove from shelf
            onRemove?(self)
        }
    }
}
