//
//  DropAreaView.swift
//  Flow Drop
//
//  Created by Tamas Rares on 06.05.2026.
//

import Cocoa

import Cocoa

protocol DropAreaViewDelegate: AnyObject {
    func didReceiveItems(_ items: [NSPasteboardItem])   // Match what you have
    func dropAreaDidEnterDrag(_ dropArea: DropAreaView)
    func dropAreaDidExitDrag(_ dropArea: DropAreaView)
}

class DropAreaView: NSView {

    weak var delegate: DropAreaViewDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        registerForDraggedTypes([
            .fileURL, .string, .URL, .png, .tiff, .pdf, .rtfd
        ])

        wantsLayer = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        delegate?.dropAreaDidEnterDrag(self)
        print("[DropAreaView] draggingEntered types=\(sender.draggingPasteboard.types ?? [])")
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.backgroundColor = nil
        delegate?.dropAreaDidExitDrag(self)
        print("[DropAreaView] draggingExited")
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.backgroundColor = nil
        delegate?.dropAreaDidExitDrag(self)
        let pasteboardItems = sender.draggingPasteboard.pasteboardItems ?? []
        print("[DropAreaView] performDragOperation items=\(pasteboardItems.count)")
        for (index, item) in pasteboardItems.enumerated() {
            print("[DropAreaView] item[\(index)] types=\(item.types)")
        }
        delegate?.didReceiveItems(pasteboardItems)
        return true
    }
}
