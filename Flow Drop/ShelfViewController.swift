//
//  ShelfViewController.swift
//  Flow Drop
//
//  Created by Tamas Rares on 05.05.2026.
//

import Cocoa

class ShelfViewController: NSViewController, DropAreaViewDelegate {
    /// Above menu/status layers; use with `NSPanel` + `fullScreenAuxiliary` so the shelf can paint over native fullscreen.
    /// `.statusBar` was still below other apps’ fullscreen; `.popUpMenu` is the usual HUD overlay tier.
    static let shelfWindowLevel = NSWindow.Level.popUpMenu

    static let restingAlpha: CGFloat = 0.7
    static let highlightedAlpha: CGFloat = 1.0
    /// How long the shelf stays expanded after ⌃⇧S stash (matches hover “peek” duration).
    static let keyboardStashRevealDuration: TimeInterval = 2.0

    /// Narrow resting strip (must stay ≥ window min width in storyboard / `setupWindow`).
    private static let minimumVisibleEdgePixels: CGFloat = 18

    private var visualEffectView: NSVisualEffectView!
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    /// Constraints for scrollView when the shelf is expanded (margins to superview).
    private var scrollExpandedConstraints: [NSLayoutConstraint] = []
    /// Constraints that collapse scrollView to zero width so the window can shrink to the resting strip.
    private var scrollCollapsedConstraints: [NSLayoutConstraint] = []
    private var scrollLayoutIsCollapsed = false

    private var items: [AppSettings.PersistedShelfItem] = []
    private var expandedWidth: CGFloat = 0
    private var currentSide: AppSettings.ShelfSide = .left
    private var isHighlighted = false
    private var isExpanded = false
    private var lastPositionedScreenID: String?
    /// Screen last set by `position(on:side:...)` so expand/collapse does not re-resolve from window geometry.
    private var pinnedScreen: NSScreen?
    private var highlightResetWorkItem: DispatchWorkItem?
    /// True after `didReceiveItems` in the current drag; `dropAreaDidExitDrag` skips immediate collapse so the delayed reset can run.
    private var didReceiveDropThisDraggingSession = false
    /// After a successful drop, keep shelf highlighted briefly even if hover flickers during mouse-up.
    private var postDropGraceUntil: Date?

    override func viewDidLoad() {
        super.viewDidLoad()
        print("[ShelfViewController] viewDidLoad")
        setupUI()
        configureDropAreaDelegate()
        setupObservers()
        loadPersistedItemsIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureDropAreaDelegate() {
        if let dropArea = findDropArea(in: view) {
            dropArea.delegate = self
            dropArea.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        // Do not pin scrollView here — `buildScrollLayoutConstraintSets` + `applyScrollLayoutForShelfExpanded`
        // own expanded vs collapsed constraints. Duplicate constraints would stay active and block a narrow window.

        // Stack View
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView

        // Match clip width when wide, but allow compressing below intrinsic row width when the window is narrow.
        stackView.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor).isActive = true
        let stackWidthEqClip = stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        stackWidthEqClip.priority = .defaultLow
        stackWidthEqClip.isActive = true
        stackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Resting = not highlighted: hide item list until hover/drag highlights the shelf.
        stackView.isHidden = true

        buildScrollLayoutConstraintSets()
        applyScrollLayoutForShelfExpanded(false)

        print("[ShelfViewController] setupUI completed")
    }

    private func buildScrollLayoutConstraintSets() {
        scrollExpandedConstraints = [
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ]
        scrollCollapsedConstraints = [
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: 0),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ]
    }

    /// NSScrollView + margins cannot shrink to ~18pt; use zero-width scroll layout when resting.
    private func applyScrollLayoutForShelfExpanded(_ expanded: Bool) {
        if expanded == !scrollLayoutIsCollapsed { return }
        if expanded {
            NSLayoutConstraint.deactivate(scrollCollapsedConstraints)
            NSLayoutConstraint.activate(scrollExpandedConstraints)
            scrollView.isHidden = false
            scrollView.hasVerticalScroller = true
            scrollLayoutIsCollapsed = false
        } else {
            NSLayoutConstraint.deactivate(scrollExpandedConstraints)
            NSLayoutConstraint.activate(scrollCollapsedConstraints)
            scrollView.isHidden = true
            scrollView.hasVerticalScroller = false
            scrollLayoutIsCollapsed = true
        }
        view.needsUpdateConstraints = true
        view.layoutSubtreeIfNeeded()
    }

    func didReceiveItems(_ pasteboardItems: [NSPasteboardItem]) {
        print("[ShelfViewController] didReceiveItems count = \(pasteboardItems.count)")
        if ingestPasteboardItems(pasteboardItems) {
            didReceiveDropThisDraggingSession = true
            postDropGraceUntil = Date().addingTimeInterval(1.5)
            scheduleHighlightResetAfterInteraction()
        }
    }

    /// ⌃⇧S — capture selection, expand shelf ~2s, then collapse unless the pointer is over the strip.
    func stashFromKeyboardShortcut(pasteboardItems: [NSPasteboardItem]) {
        guard !pasteboardItems.isEmpty else {
            print("[ShelfViewController] keyboard stash: nothing to add")
            return
        }

        cancelHighlightResetWorkItem()
        setHighlighted(true, animated: true)

        let added = ingestPasteboardItems(pasteboardItems)
        guard added else {
            print("[ShelfViewController] keyboard stash: pasteboard had no supported types")
            setHighlighted(false, animated: true)
            return
        }

        didReceiveDropThisDraggingSession = true
        postDropGraceUntil = Date().addingTimeInterval(Self.keyboardStashRevealDuration)
        scheduleHighlightResetAfterInteraction(after: Self.keyboardStashRevealDuration)
        print("[ShelfViewController] keyboard stash added items, reveal \(Self.keyboardStashRevealDuration)s")
    }

    @discardableResult
    private func ingestPasteboardItems(_ pasteboardItems: [NSPasteboardItem]) -> Bool {
        var didAddAny = false

        for (index, item) in pasteboardItems.enumerated() {
            print("[ShelfViewController] item[\(index)] types = \(item.types)")
            if let urlString = item.string(forType: .fileURL), let url = URL(string: urlString) {
                print("[ShelfViewController] parsed fileURL: \(url)")
                let bookmark = makeSecurityScopedBookmark(for: url)
                if bookmark == nil {
                    print("[ShelfViewController] WARNING: bookmark creation failed; drag-after-relaunch may not work for this file")
                } else {
                    print("[ShelfViewController] bookmark bytes=\(bookmark?.count ?? 0)")
                }
                addItemToShelf(kind: .fileURL, stringValue: url.absoluteString, dataValue: nil, bookmarkData: bookmark)
                didAddAny = true
            } else if let text = item.string(forType: .string) {
                print("[ShelfViewController] parsed string: \(text)")
                addItemToShelf(kind: .text, stringValue: text, dataValue: nil, bookmarkData: nil)
                didAddAny = true
            } else if let imageData = item.data(forType: .tiff) ?? item.data(forType: .png), let image = NSImage(data: imageData) {
                print("[ShelfViewController] parsed image data")
                _ = image
                addItemToShelf(kind: .imageTIFF, stringValue: nil, dataValue: imageData, bookmarkData: nil)
                didAddAny = true
            } else if let urlString = item.string(forType: .URL), let url = URL(string: urlString) {
                print("[ShelfViewController] parsed URL: \(url)")
                addItemToShelf(kind: .url, stringValue: url.absoluteString, dataValue: nil, bookmarkData: nil)
                didAddAny = true
            } else {
                print("[ShelfViewController] could not parse pasteboard item")
            }
        }
        return didAddAny
    }

    /// While active, AppDelegate hover logic keeps the shelf expanded/highlighted.
    func isPostDropGraceActive() -> Bool {
        guard let end = postDropGraceUntil else { return false }
        return Date() < end
    }

    func dropAreaDidEnterDrag(_ dropArea: DropAreaView) {
        cancelHighlightResetWorkItem()
        didReceiveDropThisDraggingSession = false
        setHighlighted(true)
    }

    func dropAreaDidExitDrag(_ dropArea: DropAreaView) {
        if didReceiveDropThisDraggingSession {
            didReceiveDropThisDraggingSession = false
            return
        }
        cancelHighlightResetWorkItem()
        setHighlighted(false, animated: true)
    }

    private func addItemToShelf(kind: AppSettings.PersistedShelfItem.Kind, stringValue: String?, dataValue: Data?, bookmarkData: Data?) {
        let stored = AppSettings.PersistedShelfItem(
            id: UUID().uuidString,
            kind: kind,
            stringValue: stringValue,
            dataValue: dataValue,
            bookmarkData: bookmarkData
        )
        guard let uiItem = makeDisplayItem(from: stored) else { return }
        print("[ShelfViewController] addItemToShelf called with kind \(stored.kind.rawValue)")
        let itemView = ShelfItemView(frame: NSRect(x: 0, y: 0, width: 300, height: 50))
        itemView.itemID = stored.id
        itemView.persistedKind = stored.kind
        itemView.configure(with: uiItem)
        itemView.onRemove = { [weak self] view in
            self?.removeItem(withID: view.itemID)
        }
        stackView.addArrangedSubview(itemView)
        items.append(stored)
        persistItemsIfNeeded()

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
            window.animator().alphaValue = Self.restingAlpha
        }, completionHandler: nil)
    }

    func hideWithAnimation(completion: (() -> Void)? = nil) {
        guard let window = view.window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = Self.restingAlpha
            completion?()
        })
    }

    // This will be called when window is created
    func setupWindow() {
        guard let window = view.window else { return }

        ShelfWindowConfiguration.applySharedChrome(to: window)
        // Storyboard / intrinsic layout defaults can fight a 24pt-wide window; allow narrow content.
        window.contentMinSize = NSSize(width: Self.minimumVisibleEdgePixels, height: 220)
        window.minSize = NSSize(width: Self.minimumVisibleEdgePixels, height: 220)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        expandedWidth = max(window.frame.width, 300)
        applyCurrentSideFromSettings(animated: false, hideDuringMove: false)
    }

    /// Global hover hit zone anchored to the **pinned screen** and expanded width — does not use `window.frame`,
    /// so it stays stable while the window width animates (avoids expand/collapse oscillation).
    func globalPointInteractsWithShelfHover(_ screenPoint: NSPoint) -> Bool {
        guard let screen = pinnedScreen ?? view.window?.screen ?? NSScreen.main else { return false }
        let vf = screen.visibleFrame
        let fullW = max(expandedWidth, 260)
        let pad: CGFloat = 16
        let stripWidth = min(fullW + pad * 2, vf.width)
        switch currentSide {
        case .left:
            let r = NSRect(x: vf.minX, y: vf.minY, width: stripWidth, height: vf.height)
            return r.contains(screenPoint)
        case .right:
            let r = NSRect(x: vf.maxX - stripWidth, y: vf.minY, width: stripWidth, height: vf.height)
            return r.contains(screenPoint)
        }
    }

    func setHighlighted(_ highlighted: Bool, animated: Bool = true) {
        guard highlighted != isHighlighted else { return }
        if highlighted {
            cancelHighlightResetWorkItem()
        }
        isHighlighted = highlighted
        let targetAlpha = highlighted ? Self.highlightedAlpha : Self.restingAlpha

        guard let window = view.window else { return }
        let screen = pinnedScreen ?? window.screen ?? NSScreen.main
        guard let screen else { return }

        stackView.isHidden = true

        if !highlighted {
            applyScrollLayoutForShelfExpanded(false)
            view.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
        }

        isExpanded = highlighted
        let targetFrame = targetFrameForCurrentState(screen: screen, expanded: highlighted)

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = targetAlpha
            }, completionHandler: { [weak self] in
                guard let self else { return }
                if self.isHighlighted {
                    self.applyScrollLayoutForShelfExpanded(true)
                    self.stackView.isHidden = false
                }
            })
        } else {
            if highlighted {
                applyScrollLayoutForShelfExpanded(true)
            }
            window.setFrame(targetFrame, display: true)
            window.alphaValue = targetAlpha
            updateShelfItemsVisibility()
        }
    }

    /// Items are only visible while the shelf is highlighted (hover / drag / post-drop window).
    private func updateShelfItemsVisibility() {
        stackView.isHidden = !isHighlighted
    }

    func position(on screen: NSScreen, side: AppSettings.ShelfSide, animated: Bool = false, hideDuringMove: Bool = false) {
        guard let window = view.window else { return }
        pinnedScreen = screen
        currentSide = side
        let targetFrame = targetFrameForCurrentState(screen: screen, expanded: isExpanded)
        let screenID = screen.localizedName
        print("[ShelfViewController] position screen=\(screenID) side=\(side.rawValue) expanded=\(isExpanded) animated=\(animated) hiddenMove=\(hideDuringMove)")
        lastPositionedScreenID = screenID

        if hideDuringMove {
            let restoreAlpha = isHighlighted ? Self.highlightedAlpha : Self.restingAlpha
            window.alphaValue = 0
            window.setFrame(targetFrame, display: false)
            window.alphaValue = restoreAlpha
            return
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    func clearAllItems() {
        items.removeAll()
        stackView.arrangedSubviews.forEach { subview in
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        persistItemsIfNeeded()
    }

    /// Collapsed: narrow strip fully inside `visibleFrame` (no bleed to adjacent displays).
    /// Expanded: full width inside `visibleFrame`.
    private func targetFrameForCurrentState(screen: NSScreen, expanded: Bool) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let fullWidth = max(expandedWidth, 260)
        let collapsedWidth = min(visibleFrame.width, Self.minimumVisibleEdgePixels)
        let width = expanded ? min(fullWidth, visibleFrame.width) : collapsedWidth
        let height = min(max(view.frame.height, 260), visibleFrame.height)

        let x: CGFloat
        if currentSide == .left {
            x = visibleFrame.minX
        } else {
            x = visibleFrame.maxX - width
        }
        let centeredY = visibleFrame.midY - (height / 2.0)
        let y = max(visibleFrame.minY, min(centeredY, visibleFrame.maxY - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func applyExpandedState(_ expanded: Bool, animated: Bool, hideDuringMove: Bool) {
        guard let window = view.window else { return }
        isExpanded = expanded
        let screen = pinnedScreen ?? window.screen ?? NSScreen.main
        guard let screen else {
            print("[ShelfViewController] applyExpandedState could not resolve screen")
            return
        }
        position(on: screen, side: currentSide, animated: animated, hideDuringMove: hideDuringMove)
    }

    private func makeSecurityScopedBookmark(for url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            print("[ShelfViewController] bookmarkData error: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeDisplayItem(from item: AppSettings.PersistedShelfItem) -> Any? {
        switch item.kind {
        case .fileURL:
            if let bookmark = item.bookmarkData {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    if isStale {
                        print("[ShelfViewController] bookmark is stale for id=\(item.id)")
                    }
                    return url
                }
                print("[ShelfViewController] failed to resolve bookmark for id=\(item.id)")
            }
            guard let raw = item.stringValue else { return nil }
            if let url = URL(string: raw), url.isFileURL {
                return url
            }
            return URL(fileURLWithPath: raw)
        case .url:
            guard let raw = item.stringValue, let url = URL(string: raw) else { return nil }
            return url
        case .text:
            return item.stringValue ?? ""
        case .imageTIFF:
            guard let data = item.dataValue, let image = NSImage(data: data) else { return nil }
            return image
        }
    }

    private func removeItem(withID id: String?) {
        guard let id else { return }
        items.removeAll { $0.id == id }
        if let itemView = stackView.arrangedSubviews
            .compactMap({ $0 as? ShelfItemView })
            .first(where: { $0.itemID == id }) {
            stackView.removeArrangedSubview(itemView)
            itemView.removeFromSuperview()
        }
        persistItemsIfNeeded()
    }

    private func loadPersistedItemsIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppSettings.Keys.keepData) == nil {
            defaults.set(true, forKey: AppSettings.Keys.keepData)
        }
        guard defaults.bool(forKey: AppSettings.Keys.keepData),
              let data = defaults.data(forKey: AppSettings.Keys.persistedItems),
              let storedItems = try? JSONDecoder().decode([AppSettings.PersistedShelfItem].self, from: data) else {
            print("[ShelfViewController] loadPersistedItems skipped")
            return
        }
        print("[ShelfViewController] loadPersistedItems count=\(storedItems.count)")

        for stored in storedItems {
            guard let uiItem = makeDisplayItem(from: stored) else { continue }
            let itemView = ShelfItemView(frame: NSRect(x: 0, y: 0, width: 300, height: 50))
            itemView.itemID = stored.id
            itemView.persistedKind = stored.kind
            itemView.configure(with: uiItem)
            itemView.onRemove = { [weak self] view in
                self?.removeItem(withID: view.itemID)
            }
            stackView.addArrangedSubview(itemView)
            items.append(stored)
        }
    }

    private func persistItemsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppSettings.Keys.keepData) else {
            defaults.removeObject(forKey: AppSettings.Keys.persistedItems)
            print("[ShelfViewController] persistItems disabled, cleared stored data")
            return
        }
        guard let encoded = try? JSONEncoder().encode(items) else { return }
        defaults.set(encoded, forKey: AppSettings.Keys.persistedItems)
        print("[ShelfViewController] persistItems saved count=\(items.count)")
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShelfSideChanged),
            name: .shelfSideChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeepDataChanged),
            name: .shelfKeepDataChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClearRequested),
            name: .shelfClearRequested,
            object: nil
        )
    }

    @objc private func handleShelfSideChanged() {
        applyCurrentSideFromSettings(animated: true, hideDuringMove: true)
    }

    @objc private func handleKeepDataChanged() {
        if !UserDefaults.standard.bool(forKey: AppSettings.Keys.keepData) {
            UserDefaults.standard.removeObject(forKey: AppSettings.Keys.persistedItems)
        } else {
            persistItemsIfNeeded()
        }
    }

    @objc private func handleClearRequested() {
        clearAllItems()
    }

    private func cancelHighlightResetWorkItem() {
        highlightResetWorkItem?.cancel()
        highlightResetWorkItem = nil
    }

    /// After a drop or ⌃C stash, stay highlighted briefly; then rest only if the cursor is not over the shelf strip.
    private func scheduleHighlightResetAfterInteraction(after delay: TimeInterval = 1.5) {
        cancelHighlightResetWorkItem()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.postDropGraceUntil = nil
            if self.globalPointInteractsWithShelfHover(NSEvent.mouseLocation) {
                return
            }
            self.setHighlighted(false, animated: true)
        }
        highlightResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyCurrentSideFromSettings(animated: Bool, hideDuringMove: Bool) {
        let sideRaw = UserDefaults.standard.string(forKey: AppSettings.Keys.shelfSide) ?? AppSettings.ShelfSide.left.rawValue
        currentSide = AppSettings.ShelfSide(rawValue: sideRaw) ?? .left
        print("[ShelfViewController] applyCurrentSide side=\(currentSide.rawValue)")
        applyExpandedState(isHighlighted, animated: animated, hideDuringMove: hideDuringMove)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        print("[ShelfViewController] viewDidAppear")
        setupWindow()
        setHighlighted(false, animated: false)
    }
}
