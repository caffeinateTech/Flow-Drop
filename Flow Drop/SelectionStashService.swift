//
//  SelectionStashService.swift
//  Flow Drop
//

import AppKit
import ApplicationServices

/// Resolves the user's current selection into pasteboard-shaped items for the shelf.
enum SelectionStashService {

    private static let captureQueue = DispatchQueue(label: "flowdrop.selectionStash", qos: .userInitiated)

    /// Finder file selection, then synthetic ⌘C, then existing general pasteboard.
    static func captureSelection(completion: @escaping ([NSPasteboardItem]) -> Void) {
        captureQueue.async {
            if let finderItems = pasteboardItemsFromFinderSelection(), !finderItems.isEmpty {
                DispatchQueue.main.async { completion(finderItems) }
                return
            }

            DispatchQueue.main.async {
                captureViaCopyOrPasteboard(completion: completion)
            }
        }
    }

    private static func captureViaCopyOrPasteboard(completion: @escaping ([NSPasteboardItem]) -> Void) {
        let pasteboard = NSPasteboard.general
        let changeCountBefore = pasteboard.changeCount

        postCommandC()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if pasteboard.changeCount != changeCountBefore,
               let items = pasteboard.pasteboardItems, !items.isEmpty {
                completion(items)
                return
            }
            if let items = pasteboard.pasteboardItems, !items.isEmpty, pasteboardHasStashableContent(pasteboard) {
                completion(items)
                return
            }
            completion([])
        }
    }

    private static func pasteboardHasStashableContent(_ pasteboard: NSPasteboard) -> Bool {
        let types: [NSPasteboard.PasteboardType] = [.fileURL, .string, .URL, .tiff, .png, .pdf]
        let available = Set(pasteboard.types ?? [])
        return types.contains { available.contains($0) }
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode: CGKeyCode = 8 // ANSI C
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private static func pasteboardItemsFromFinderSelection() -> [NSPasteboardItem]? {
        let scriptSource = """
        tell application "Finder"
            set sel to selection
            if (count of sel) is 0 then return ""
            set out to ""
            repeat with f in sel
                set out to out & (POSIX path of (f as alias)) & linefeed
            end repeat
            return out
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            print("[SelectionStashService] Finder AppleScript error: \(error)")
            return nil
        }
        let raw = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        let paths = raw.split(separator: "\n").map { String($0) }
        var items: [NSPasteboardItem] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            items.append(item)
        }
        return items.isEmpty ? nil : items
    }
}
