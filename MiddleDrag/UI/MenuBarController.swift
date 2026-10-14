import Cocoa
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// Manages the menu bar UI and user interactions
@MainActor
public class MenuBarController: NSObject {

    // MARK: - Properties

    private struct StatusItemBox: @unchecked Sendable {
        let value: NSStatusItem
    }

    private var statusItemStorage: StatusItemBox?
    private var statusItem: NSStatusItem! {
        get { statusItemStorage?.value }
        set { statusItemStorage = newValue.map(StatusItemBox.init(value:)) }
    }
    private weak var multitouchManager: MultitouchManager?
    private var preferences: UserPreferences
    private(set) var isMenuBarVisible = true

    // Menu item tags for easy reference
    private enum MenuItemTag: Int {
        case enabled = 1
        case launchAtLogin = 2
        case middleDrag = 3
        case tapToClick = 4
        case tapToDrag = 5
        case tapResponsiveness = 6
    }

    // MARK: - Initialization

    public init(multitouchManager: MultitouchManager, preferences: UserPreferences) {
        self.multitouchManager = multitouchManager
        self.preferences = preferences
        super.init()

        setupStatusItem()

        // Listen for late device connections (e.g., Bluetooth trackpad connecting after boot)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDidConnect),
            name: .middleDragDeviceConnected,
            object: nil
        )

        // Listen for polling timeout (no device found within time limit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pollingDidTimeout),
            name: .middleDragPollingTimedOut,
            object: nil
        )
    }

    deinit {
        let statusItemToRemove = statusItemStorage

        if Thread.isMainThread {
            if let statusItemToRemove {
                NSStatusBar.system.removeStatusItem(statusItemToRemove.value)
            }
            return
        }

        DispatchQueue.main.async {
            if let statusItemToRemove {
                NSStatusBar.system.removeStatusItem(statusItemToRemove.value)
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if statusItem.button != nil {
            updateStatusIcon(enabled: multitouchManager?.isEnabled ?? false)
        }

        buildMenu()
    }

    func updateStatusIcon(enabled: Bool) {
        guard let button = statusItem.button else { return }

        let iconName = enabled ? "hand.raised.fingers.spread" : "hand.raised.slash"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "MiddleDrag")
        button.image?.isTemplate = true

        // Animate the change and restore alpha when complete
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            button.animator().alphaValue = 0.7
        }, completionHandler: {
            // Ensure mutation happens on the main actor
            Task { @MainActor in
                button.alphaValue = 1.0
            }
        })
    }

    // MARK: - Menu Building

    func buildMenu() {
        let menu = NSMenu()

        // Status
        menu.addItem(createStatusItem())
        menu.addItem(NSMenuItem.separator())

        // Enable/Disable
        menu.addItem(createEnabledItem())
        menu.addItem(createTapToClickItem())
        menu.addItem(createMiddleDragItem())
        menu.addItem(createTapToDragItem())
        menu.addItem(NSMenuItem.separator())
        for fingerCount in [1, 2] {
            menu.addItem(createLowFingerTapToClickItem(fingerCount: fingerCount))
            menu.addItem(createTapToDragItem(fingerCount: fingerCount))
        }
        menu.addItem(NSMenuItem.separator())

        // Settings
        menu.addItem(createSensitivityMenu())
        menu.addItem(createAdvancedMenu())
        menu.addItem(NSMenuItem.separator())

        // App items
        menu.addItem(createMenuItem(title: "About MiddleDrag", action: #selector(showAbout)))
        menu.addItem(createLaunchAtLoginItem())
        menu.addItem(createCheckForUpdatesItem())
        menu.addItem(createAutoUpdateItem())
        menu.addItem(NSMenuItem.separator())

        // Actions
        menu.addItem(createMenuItem(title: "Quick Setup", action: #selector(showQuickSetup)))
        menu.addItem(createMenuItem(title: "Hide Menu Bar Icon (⌘⇧M or Spotlight to restore)", action: #selector(hideMenuBarIcon)))
        menu.addItem(createMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func createStatusItem() -> NSMenuItem {
        let isEnabled = multitouchManager?.isEnabled ?? false
        let isPolling = multitouchManager?.isPollingForDevices ?? false
        let title: String
        if isPolling {
            title = "Waiting for Trackpad…"
        } else if isEnabled {
            title = "MiddleDrag Active"
        } else {
            title = "MiddleDrag Disabled"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func createEnabledItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        item.target = self  // IMPORTANT: Set target
        item.state = (multitouchManager?.isEnabled ?? false) ? .on : .off
        item.tag = MenuItemTag.enabled.rawValue
        return item
    }

    private enum GestureChoice: Int {
        case tap, directDrag, tapToDrag, oneFingerTap, oneFingerDrag, twoFingerTap, twoFingerDrag
        var fingerCount: Int {
            switch self {
            case .oneFingerTap, .oneFingerDrag: return 1
            case .twoFingerTap, .twoFingerDrag: return 2
            default: return 3
            }
        }
        var isTap: Bool { self == .oneFingerTap || self == .twoFingerTap }
    }
    private struct TimeoutSelection {
        let fingerCount: Int
        let seconds: Double
    }
    private struct ButtonSelection {
        let gesture: GestureChoice
        let button: GestureMouseButton
    }

    private func createGestureMenu(title: String, gesture: GestureChoice,
                                   enabled: Bool, button: GestureMouseButton,
                                   action: Selector, tag: MenuItemTag? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.tag = tag?.rawValue ?? -1
        item.state = enabled ? .on : .off
        let submenu = NSMenu()
        let toggle = createMenuItem(title: "Enabled", action: action)
        toggle.state = enabled ? .on : .off
        submenu.addItem(toggle)
        submenu.addItem(.separator())
        for candidate in GestureMouseButton.allCases {
            let choice = createMenuItem(title: "\(candidate.displayName) Button",
                                        action: #selector(setGestureButton(_:)))
            choice.representedObject = ButtonSelection(gesture: gesture, button: candidate)
            choice.state = candidate == button ? .on : .off
            submenu.addItem(choice)
        }
        item.submenu = submenu
        // Set the action after attaching the submenu so the parent also toggles
        // on selection, while hovering still opens its configuration choices.
        item.target = self
        item.action = action
        item.representedObject = gesture
        return item
    }

    private func createMiddleDragItem() -> NSMenuItem {
        createGestureMenu(title: "3-finger Direct Drag", gesture: .directDrag,
                          enabled: preferences.middleDragEnabled,
                          button: preferences.directDragButton,
                          action: #selector(toggleMiddleDrag), tag: .middleDrag)
    }

    private func createTapToClickItem() -> NSMenuItem {
        let item = createGestureMenu(title: "3-finger Tap to Click", gesture: .tap,
                                     enabled: preferences.tapToClickEnabled,
                                     button: preferences.tapButton,
                                     action: #selector(toggleTapToClick), tag: .tapToClick)
        configureTapResponsivenessMenu(item, fingerCount: 3)
        return item
    }

    private func createLowFingerTapToClickItem(fingerCount: Int) -> NSMenuItem {
        let settings = preferences.gestureConfig.tapConfiguration(for: fingerCount)
        let gesture: GestureChoice = fingerCount == 1 ? .oneFingerTap : .twoFingerTap
        let item = createGestureMenu(title: "\(fingerCount)-finger Tap to Click", gesture: gesture,
                                     enabled: settings.tapToClickEnabled, button: settings.tapButton,
                                     action: #selector(toggleLowFingerGesture(_:)))
        item.submenu?.items.first?.representedObject = gesture
        configureTapResponsivenessMenu(item, fingerCount: fingerCount)
        return item
    }

    private func configureTapResponsivenessMenu(_ item: NSMenuItem, fingerCount: Int) {
        guard let submenu = item.submenu else { return }
        submenu.delegate = self
        updateTapResponsivenessMenu(submenu, fingerCount: fingerCount)
    }

    private func updateTapResponsivenessMenu(_ menu: NSMenu, fingerCount: Int) {
        for item in menu.items where item.tag == MenuItemTag.tapResponsiveness.rawValue {
            menu.removeItem(item)
        }
        let separator = NSMenuItem.separator()
        separator.tag = MenuItemTag.tapResponsiveness.rawValue
        menu.addItem(separator)

        if fingerCount == 2 && SystemGestureHelper.isSmartZoomEnabled() {
            let caveats = createMenuItem(title: "Caveats on compatibility with Smart Zoom",
                                         action: #selector(showSmartZoomCompatibility))
            caveats.tag = MenuItemTag.tapResponsiveness.rawValue
            menu.addItem(caveats)
            return
        }

        let settings = preferences.gestureConfig.tapConfiguration(for: fingerCount)
        let immediatePress = createMenuItem(title: "Press Button on First Tap Release",
                                            action: #selector(toggleTapToDragImmediatePress(_:)))
        immediatePress.representedObject = fingerCount
        immediatePress.state = settings.tapToDragImmediatePress ? .on : .off
        immediatePress.tag = MenuItemTag.tapResponsiveness.rawValue
        menu.addItem(immediatePress)
        let explanation = NSMenuItem(title: "Early press requires matching tap and drag buttons",
                                      action: nil, keyEquivalent: "")
        explanation.isEnabled = false
        explanation.tag = MenuItemTag.tapResponsiveness.rawValue
        menu.addItem(explanation)
    }

    private func createTapToDragItem(fingerCount: Int = 3) -> NSMenuItem {
        let settings = preferences.gestureConfig.tapConfiguration(for: fingerCount)
        let gesture: GestureChoice = fingerCount == 1 ? .oneFingerDrag
            : (fingerCount == 2 ? .twoFingerDrag : .tapToDrag)
        let item = createGestureMenu(title: "\(fingerCount)-finger Tap to Drag", gesture: gesture,
                                     enabled: settings.tapToDragEnabled, button: settings.tapToDragButton,
                                     action: fingerCount == 3 ? #selector(toggleTapToDrag)
                                         : #selector(toggleLowFingerGesture(_:)),
                                     tag: fingerCount == 3 ? .tapToDrag : nil)
        item.submenu?.items.first?.representedObject = gesture
        item.submenu?.addItem(.separator())
        let timeout = NSMenuItem(
            title: "Timeout (\(Int((settings.tapToDragTimeout * 1000).rounded())) ms)",
            action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for milliseconds in [100, 150, 200, 250, 300, 500, 1000] {
            let choice = createMenuItem(title: "\(milliseconds) ms",
                                        action: #selector(setTapToDragTimeout(_:)))
            choice.representedObject = TimeoutSelection(fingerCount: fingerCount, seconds: Double(milliseconds) / 1000)
            choice.state = abs(settings.tapToDragTimeout * 1000 - Double(milliseconds)) < 0.5 ? .on : .off
            choices.addItem(choice)
        }
        choices.addItem(.separator())
        let custom = createMenuItem(title: "Custom…", action: #selector(setCustomTapToDragTimeout(_:)))
        custom.representedObject = fingerCount
        choices.addItem(custom)
        timeout.submenu = choices
        item.submenu?.addItem(timeout)
        return item
    }

    private func createLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self  // IMPORTANT: Set target
        item.state = preferences.launchAtLogin ? .on : .off
        item.tag = MenuItemTag.launchAtLogin.rawValue
        return item
    }

    private func createCheckForUpdatesItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        item.target = self
        return item
    }

    private func createAutoUpdateItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Automatically Check for Updates", action: #selector(toggleAutoUpdate), keyEquivalent: "")
        item.target = self
        item.state = UpdateManager.shared.automaticallyChecksForUpdates ? .on : .off
        return item
    }

    private func createMenuItem(title: String, action: Selector, keyEquivalent: String = "")
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self  // IMPORTANT: Set target
        return item
    }

    private func createSensitivityMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Drag Sensitivity", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let sensitivities: [(String, Float)] = [
            ("Slow (0.5x)", 0.5),
            ("Precision (0.75x)", 0.75),
            ("Normal (1x)", 1.0),
            ("Fast (1.5x)", 1.5),
            ("Very Fast (2x)", 2.0),
        ]

        for (title, value) in sensitivities {
            let menuItem = NSMenuItem(
                title: title, action: #selector(setSensitivity(_:)), keyEquivalent: "")
            menuItem.target = self  // IMPORTANT: Set target
            menuItem.representedObject = value
            if abs(Float(preferences.dragSensitivity) - value) < 0.01 {
                menuItem.state = .on
            }
            submenu.addItem(menuItem)
        }

        item.submenu = submenu
        return item
    }

    private func createAdvancedMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        // Check compatibility of the currently enabled gestures.
        let gestureItem = NSMenuItem(
            title: "Check for Conflicting System Gestures...",
            action: #selector(checkForConflictingSystemGestures),
            keyEquivalent: ""
        )
        gestureItem.target = self
        submenu.addItem(gestureItem)

        submenu.addItem(NSMenuItem.separator())

        // Palm Rejection section
        submenu.addItem(createPalmRejectionMenu())

        submenu.addItem(NSMenuItem.separator())

        // Minimum Window Size section (separate from palm rejection as it's window-based)
        let windowSizeItem = createAdvancedMenuItem(
            title: "Ignore Small Windows",
            isOn: preferences.minimumWindowSizeFilterEnabled,
            action: #selector(toggleMinimumWindowSizeFilter)
        )
        submenu.addItem(windowSizeItem)

        // Window size threshold options (only shown when enabled)
        if preferences.minimumWindowSizeFilterEnabled {
            let sizes: [(String, Double)] = [
                ("Very Small (50px)", 50),
                ("Small (100px)", 100),
                ("Medium (200px)", 200),
                ("Large (300px)", 300),
            ]

            for (title, value) in sizes {
                let sizeItem = NSMenuItem(
                    title: "    \(title)", action: #selector(setMinimumWindowSize(_:)),
                    keyEquivalent: "")
                sizeItem.target = self
                sizeItem.representedObject = value
                if abs(preferences.minimumWindowWidth - value) < 0.01 {
                    sizeItem.state = .on
                }
                submenu.addItem(sizeItem)
            }
        }

        // Ignore Desktop option (suppress gestures when cursor is over desktop)
        let ignoreDesktopItem = createAdvancedMenuItem(
            title: "Ignore Desktop",
            isOn: preferences.ignoreDesktop,
            action: #selector(toggleIgnoreDesktop)
        )
        submenu.addItem(ignoreDesktopItem)

        // Window Bar Drag - pass through gestures when cursor is over title bar
        // Allows macOS native three-finger drag to work for window dragging
        let windowBarDragItem = createAdvancedMenuItem(
            title: "Window Bar Drag",
            isOn: preferences.passThroughTitleBar,
            action: #selector(toggleWindowBarDrag)
        )
        submenu.addItem(windowBarDragItem)

        submenu.addItem(NSMenuItem.separator())

        // Relift during drag - Linux-style text selection
        submenu.addItem(
            createAdvancedMenuItem(
                title: "Allow Relift During Drag",
                isOn: preferences.allowReliftDuringDrag,
                action: #selector(toggleAllowReliftDuringDrag)
            ))

        submenu.addItem(NSMenuItem.separator())
        
        // Emergency release for stuck drags
        let forceReleaseItem = NSMenuItem(
            title: "Force Release Stuck Drag",
            action: #selector(forceReleaseStuckDrag),
            keyEquivalent: ""
        )
        forceReleaseItem.target = self
        submenu.addItem(forceReleaseItem)
        submenu.addItem(createGestureDiagnosticsMenu())
        
        submenu.addItem(NSMenuItem.separator())

        // Hotkey rebinding
        let hotkeyItem = NSMenuItem(
            title: "Change Toggle Hotkey (\(preferences.toggleHotKey.displayString))…",
            action: #selector(rebindToggleHotKey),
            keyEquivalent: ""
        )
        hotkeyItem.target = self
        submenu.addItem(hotkeyItem)

        let menuBarHotkeyItem = NSMenuItem(
            title: "Change Menu Bar Hotkey (\(preferences.menuBarHotKey.displayString))…",
            action: #selector(rebindMenuBarHotKey),
            keyEquivalent: ""
        )
        menuBarHotkeyItem.target = self
        submenu.addItem(menuBarHotkeyItem)

        submenu.addItem(NSMenuItem.separator())

        // Telemetry section header
        let telemetryHeader = NSMenuItem(
            title: "Help Improve MiddleDrag:", action: nil, keyEquivalent: "")
        telemetryHeader.isEnabled = false
        submenu.addItem(telemetryHeader)

        // Crash reporting (only sends on crash)
        submenu.addItem(
            createAdvancedMenuItem(
                title: "Send Crash Reports",
                isOn: CrashReporter.shared.isEnabled,
                action: #selector(toggleCrashReporting)
            ))

        // Performance monitoring (sends during use)
        submenu.addItem(
            createAdvancedMenuItem(
                title: "Send Performance Data",
                isOn: CrashReporter.shared.performanceMonitoringEnabled,
                action: #selector(togglePerformanceMonitoring)
            ))

        item.submenu = submenu
        return item
    }

    private func createGestureDiagnosticsMenu() -> NSMenuItem {
        let recorder = GestureEventRecorder.shared
        let item = NSMenuItem(title: "Gesture Diagnostics", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(createMenuItem(
            title: recorder.isRecording ? "Stop Recording" : "Start New Recording",
            action: #selector(toggleGestureRecording)))
        let mark = createMenuItem(title: "Mark Unexpected Click", action: #selector(markUnexpectedClick))
        mark.isEnabled = recorder.isRecording
        submenu.addItem(mark)
        let save = createMenuItem(title: "Save Event Log…", action: #selector(saveGestureEventLog))
        save.isEnabled = recorder.hasRecords
        submenu.addItem(save)
        submenu.addItem(.separator())
        let note = NSMenuItem(title: "Local only · newest 30,000 records · cleared on restart",
                              action: nil, keyEquivalent: "")
        note.isEnabled = false
        submenu.addItem(note)
        item.submenu = submenu
        return item
    }

    @objc private func toggleGestureRecording() {
        let recorder = GestureEventRecorder.shared
        if recorder.isRecording {
            recorder.stop()
        } else {
            recorder.start()
            recorder.recordConfiguration(multitouchManager?.configuration ?? preferences.gestureConfig)
            recorder.record("manager.status",
                            "enabled=\(multitouchManager?.isEnabled ?? false) monitoring=\(multitouchManager?.isMonitoring ?? false)")
        }
        buildMenu()
    }

    @objc private func markUnexpectedClick() {
        GestureEventRecorder.shared.record("user.unexpected_click", "Look immediately before this marker for the unintended click and drag.")
    }

    @objc private func saveGestureEventLog() {
        let panel = NSSavePanel()
        panel.title = "Save MiddleDrag Gesture Event Log"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        panel.nameFieldStringValue = "MiddleDrag-gestures-\(formatter.string(from: Date())).log"
        panel.allowedContentTypes = [UTType(filenameExtension: "log") ?? .plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GestureEventRecorder.shared.snapshot().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func createPalmRejectionMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Palm Rejection", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        // Exclusion Zone section
        let exclusionItem = createAdvancedMenuItem(
            title: "Exclusion Zone",
            isOn: preferences.exclusionZoneEnabled,
            action: #selector(toggleExclusionZone)
        )
        submenu.addItem(exclusionItem)

        // Exclusion zone size options (only shown when enabled)
        if preferences.exclusionZoneEnabled {
            let sizes: [(String, Double)] = [
                ("10% (Small)", 0.10),
                ("15% (Default)", 0.15),
                ("20% (Medium)", 0.20),
                ("25% (Large)", 0.25),
            ]

            for (title, value) in sizes {
                let sizeItem = NSMenuItem(
                    title: "    \(title)", action: #selector(setExclusionZoneSize(_:)),
                    keyEquivalent: "")
                sizeItem.target = self
                sizeItem.representedObject = value
                if abs(preferences.exclusionZoneSize - value) < 0.01 {
                    sizeItem.state = .on
                }
                submenu.addItem(sizeItem)
            }
        }

        submenu.addItem(NSMenuItem.separator())

        // Modifier Key section
        let modifierItem = createAdvancedMenuItem(
            title: "Require Modifier Key",
            isOn: preferences.requireModifierKey,
            action: #selector(toggleRequireModifierKey)
        )
        submenu.addItem(modifierItem)

        // Modifier key options (only shown when enabled)
        if preferences.requireModifierKey {
            for keyType in ModifierKeyType.allCases {
                let keyItem = NSMenuItem(
                    title: "    \(keyType.displayName)", action: #selector(setModifierKeyType(_:)),
                    keyEquivalent: "")
                keyItem.target = self
                keyItem.representedObject = keyType.rawValue
                if preferences.modifierKeyType == keyType {
                    keyItem.state = .on
                }
                submenu.addItem(keyItem)
            }
        }

        submenu.addItem(NSMenuItem.separator())

        // Contact Size Filter section
        let contactSizeItem = createAdvancedMenuItem(
            title: "Filter Large Contacts",
            isOn: preferences.contactSizeFilterEnabled,
            action: #selector(toggleContactSizeFilter)
        )
        submenu.addItem(contactSizeItem)

        // Contact size threshold options (only shown when enabled)
        if preferences.contactSizeFilterEnabled {
            let thresholds: [(String, Double)] = [
                ("Strict (1.0)", 1.0),
                ("Normal (1.5)", 1.5),
                ("Lenient (2.0)", 2.0),
            ]

            for (title, value) in thresholds {
                let thresholdItem = NSMenuItem(
                    title: "    \(title)", action: #selector(setContactSizeThreshold(_:)),
                    keyEquivalent: "")
                thresholdItem.target = self
                thresholdItem.representedObject = value
                if abs(preferences.maxContactSize - value) < 0.01 {
                    thresholdItem.state = .on
                }
                submenu.addItem(thresholdItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func createAdvancedMenuItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self  // IMPORTANT: Set target
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc func deviceDidConnect() {
        let isEnabled = multitouchManager?.isEnabled ?? false
        updateStatusIcon(enabled: isEnabled)
        buildMenu()
    }

    @objc func pollingDidTimeout() {
        updateStatusIcon(enabled: false)
        buildMenu()
    }

    @objc public func toggleEnabled() {
        multitouchManager?.toggleEnabled()
        let isEnabled = multitouchManager?.isEnabled ?? false

        if let item = statusItem.menu?.item(withTag: MenuItemTag.enabled.rawValue) {
            item.state = isEnabled ? .on : .off
        }

        updateStatusIcon(enabled: isEnabled)
        buildMenu()  // Rebuild to update status text
    }

    private func applyGesturePreferences() {
        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.middleDragEnabled = preferences.middleDragEnabled
        config.tapToClickEnabled = preferences.tapToClickEnabled
        config.tapButton = preferences.tapButton
        config.directDragButton = preferences.directDragButton
        config.tapToDragEnabled = preferences.tapToDragEnabled
        config.tapToDragButton = preferences.tapToDragButton
        config.tapToDragTimeout = preferences.tapToDragTimeout
        config.tapToDragImmediatePress = preferences.tapToDragImmediatePress
        config.oneFingerTaps = preferences.oneFingerTaps
        config.twoFingerTaps = preferences.twoFingerTaps
        multitouchManager?.updateConfiguration(config)
        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleMiddleDrag() {
        preferences.middleDragEnabled.toggle()
        applyGesturePreferences()
        if preferences.middleDragEnabled {
            NSApp.activate(ignoringOtherApps: true)
            AlertHelper.showThreeFingerGestureCompatibilityIfNeeded()
        }
    }

    @objc func toggleTapToClick() {
        preferences.tapToClickEnabled.toggle()
        applyGesturePreferences()
    }

    @objc func toggleTapToDrag() {
        preferences.tapToDragEnabled.toggle()
        applyGesturePreferences()
        if preferences.tapToDragEnabled {
            NSApp.activate(ignoringOtherApps: true)
            AlertHelper.showThreeFingerGestureCompatibilityIfNeeded()
        }
    }

    private func modifyLowFingerSettings(_ fingerCount: Int, _ update: (inout FingerTapConfiguration) -> Void) {
        if fingerCount == 1 { update(&preferences.oneFingerTaps) }
        else { update(&preferences.twoFingerTaps) }
    }

    @objc private func toggleLowFingerGesture(_ sender: NSMenuItem) {
        guard let gesture = sender.representedObject as? GestureChoice else { return }
        modifyLowFingerSettings(gesture.fingerCount) {
            if gesture.isTap { $0.tapToClickEnabled.toggle() }
            else { $0.tapToDragEnabled.toggle() }
        }
        applyGesturePreferences()
        showNativeTapCompatibilityIfNeeded(for: gesture)
    }

    private func showNativeTapCompatibilityIfNeeded(for gesture: GestureChoice) {
        let settings = preferences.gestureConfig.tapConfiguration(for: gesture.fingerCount)
        guard gesture.isTap ? settings.tapToClickEnabled : settings.tapToDragEnabled else { return }

        let caveat: AlertHelper.NativeTapCaveat
        switch gesture {
        case .oneFingerDrag:
            guard SystemGestureHelper.isTapToClickEnabled() else { return }
            caveat = .oneFingerTapToDrag
        case .twoFingerTap:
            guard SystemGestureHelper.isTwoFingerSecondaryTapEnabled() else { return }
            caveat = .twoFingerTapToClick
        case .twoFingerDrag:
            guard SystemGestureHelper.isTwoFingerSecondaryTapEnabled() else { return }
            caveat = .twoFingerTapToDrag
        default:
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        AlertHelper.showNativeTapCompatibility(caveat)
    }

    @objc private func toggleTapToDragImmediatePress(_ sender: NSMenuItem) {
        guard let fingerCount = sender.representedObject as? Int else { return }
        if fingerCount == 3 { preferences.tapToDragImmediatePress.toggle() }
        else { modifyLowFingerSettings(fingerCount) { $0.tapToDragImmediatePress.toggle() } }
        applyGesturePreferences()
    }

    @objc private func showSmartZoomCompatibility() {
        NSApp.activate(ignoringOtherApps: true)
        AlertHelper.showSmartZoomCompatibility(button: preferences.twoFingerTaps.tapButton)
    }

    @objc private func setGestureButton(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? ButtonSelection else { return }
        switch selection.gesture {
        case .tap: preferences.tapButton = selection.button
        case .directDrag: preferences.directDragButton = selection.button
        case .tapToDrag: preferences.tapToDragButton = selection.button
        case .oneFingerTap, .oneFingerDrag, .twoFingerTap, .twoFingerDrag:
            modifyLowFingerSettings(selection.gesture.fingerCount) {
                if selection.gesture.isTap { $0.tapButton = selection.button }
                else { $0.tapToDragButton = selection.button }
            }
        }
        applyGesturePreferences()
    }

    @objc private func setTapToDragTimeout(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? TimeoutSelection else { return }
        setTapToDragTimeout(selection.seconds, fingerCount: selection.fingerCount)
        applyGesturePreferences()
    }

    private func setTapToDragTimeout(_ seconds: Double, fingerCount: Int) {
        if fingerCount == 3 { preferences.tapToDragTimeout = seconds }
        else { modifyLowFingerSettings(fingerCount) { $0.tapToDragTimeout = seconds } }
    }

    @objc private func setCustomTapToDragTimeout(_ sender: NSMenuItem) {
        guard let fingerCount = sender.representedObject as? Int else { return }
        let settings = preferences.gestureConfig.tapConfiguration(for: fingerCount)
        let alert = NSAlert()
        alert.messageText = "\(fingerCount)-finger Tap to Drag Timeout"
        alert.informativeText = "Time from releasing a \(fingerCount)-finger tap to the next matching contact (1–60000 milliseconds)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(string: String(Int((settings.tapToDragTimeout * 1000).rounded())))
        input.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let milliseconds = Double(input.stringValue), milliseconds.isFinite,
                  milliseconds >= 1, milliseconds <= 60000 else {
                alert.informativeText = "Enter a number between 1 and 60000 milliseconds."
                continue
            }
            setTapToDragTimeout(milliseconds / 1000, fingerCount: fingerCount)
            applyGesturePreferences()
            return
        }
    }

    @objc func setSensitivity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Float else { return }

        // Update UI
        if let menu = unsafe sender.menu {
            for item in menu.items {
                item.state = item == sender ? .on : .off
            }
        }

        // Update preferences and manager
        preferences.dragSensitivity = Double(value)
        multitouchManager?.configuration.sensitivity = value

        // Notify delegate to save preferences
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func checkForConflictingSystemGestures() {
        NSApp.activate(ignoringOtherApps: true)
        AlertHelper.showSystemGestureConflicts(configuration: preferences.gestureConfig)
    }
    
    @objc func rebindToggleHotKey() {
        showHotKeyRecorderPanel(
            title: "Toggle MiddleDrag Hotkey",
            current: preferences.toggleHotKey
        ) { [weak self] newBinding in
            guard let self else { return }
            self.preferences.toggleHotKey = newBinding
            NotificationCenter.default.post(name: .preferencesChanged, object: self.preferences)
            self.buildMenu()
        }
    }

    @objc func rebindMenuBarHotKey() {
        showHotKeyRecorderPanel(
            title: "Menu Bar Visibility Hotkey",
            current: preferences.menuBarHotKey
        ) { [weak self] newBinding in
            guard let self else { return }
            self.preferences.menuBarHotKey = newBinding
            NotificationCenter.default.post(name: .preferencesChanged, object: self.preferences)
            self.buildMenu()
        }
    }

    private func showHotKeyRecorderPanel(
        title: String,
        current: HotKeyBinding,
        onAccept: @escaping (HotKeyBinding) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Press a new key combination (with at least one modifier). Press Escape to cancel."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let recorder = HotKeyRecorderView(binding: current)
        recorder.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = recorder

        // Bring app to front so the alert can receive key events
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()

        // Ensure the recorder's local keyboard monitor is cleaned up regardless
        // of how the alert was dismissed (clicking OK/Cancel without pressing a key
        // does not trigger resignFirstResponder on the accessory view)
        recorder.cancelRecording()

        if response == .alertFirstButtonReturn {
            onAccept(recorder.binding)
        }
    }

    // MARK: - Palm Rejection Actions

    @objc func toggleExclusionZone() {
        preferences.exclusionZoneEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.exclusionZoneEnabled = preferences.exclusionZoneEnabled
        config.exclusionZoneSize = Float(preferences.exclusionZoneSize)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setExclusionZoneSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }

        preferences.exclusionZoneSize = value

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.exclusionZoneSize = Float(value)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleRequireModifierKey() {
        preferences.requireModifierKey.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.requireModifierKey = preferences.requireModifierKey
        config.modifierKeyType = preferences.modifierKeyType
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setModifierKeyType(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
            let keyType = ModifierKeyType(rawValue: rawValue)
        else { return }

        preferences.modifierKeyType = keyType

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.modifierKeyType = keyType
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleContactSizeFilter() {
        preferences.contactSizeFilterEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.contactSizeFilterEnabled = preferences.contactSizeFilterEnabled
        config.maxContactSize = Float(preferences.maxContactSize)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setContactSizeThreshold(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }

        preferences.maxContactSize = value

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.maxContactSize = Float(value)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleMinimumWindowSizeFilter() {
        preferences.minimumWindowSizeFilterEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.minimumWindowSizeFilterEnabled = preferences.minimumWindowSizeFilterEnabled
        config.minimumWindowWidth = CGFloat(preferences.minimumWindowWidth)
        config.minimumWindowHeight = CGFloat(preferences.minimumWindowHeight)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setMinimumWindowSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }

        // Set both width and height to the same value (square threshold)
        preferences.minimumWindowWidth = value
        preferences.minimumWindowHeight = value

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.minimumWindowWidth = CGFloat(value)
        config.minimumWindowHeight = CGFloat(value)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleIgnoreDesktop() {
        preferences.ignoreDesktop.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.ignoreDesktop = preferences.ignoreDesktop
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleWindowBarDrag() {
        preferences.passThroughTitleBar.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.passThroughTitleBar = preferences.passThroughTitleBar
        config.titleBarHeight = CGFloat(preferences.titleBarHeight)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleAllowReliftDuringDrag() {
        preferences.allowReliftDuringDrag.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.allowReliftDuringDrag = preferences.allowReliftDuringDrag
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }
    
    @objc func forceReleaseStuckDrag() {
        multitouchManager?.forceReleaseStuckDrag()
        
        // Provide visual feedback that the action was triggered
        flashStatusBarIcon()
    }
    
    /// Flash the status bar icon to provide visual feedback for actions
    /// Uses alpha animation consistent with updateStatusIcon pattern
    private func flashStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        
        // Use alpha animation for visual feedback (consistent with updateStatusIcon)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            button.animator().alphaValue = 0.3
        } completionHandler: { [weak button] in
            // NSAnimationContext runs completion handlers on the main thread,
            // but Swift's concurrency doesn't know that statically
            MainActor.assumeIsolated {
                guard let button = button else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    button.animator().alphaValue = 1.0
                }
            }
        }
    }

    @objc func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()

        if let item = statusItem.menu?.item(withTag: MenuItemTag.launchAtLogin.rawValue) {
            item.state = preferences.launchAtLogin ? .on : .off
        }

        NotificationCenter.default.post(
            name: .launchAtLoginChanged, object: preferences.launchAtLogin)
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc func toggleAutoUpdate() {
        UpdateManager.shared.automaticallyChecksForUpdates.toggle()
        buildMenu()  // Rebuild to update checkmark
    }

    @objc func toggleCrashReporting() {
        CrashReporter.shared.isEnabled.toggle()
        buildMenu()  // Rebuild to update checkmark
    }

    @objc func togglePerformanceMonitoring() {
        CrashReporter.shared.performanceMonitoringEnabled.toggle()
        buildMenu()  // Rebuild to update checkmark
    }

    @objc private func showAbout() {
        AlertHelper.showAbout()
    }

    @objc private func showQuickSetup() {
        AlertHelper.showQuickSetup()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Menu Bar Visibility

    @objc func hideMenuBarIcon() {
        setMenuBarVisible(false)
    }

    /// Show the menu bar icon (no-op if already visible). Called from Spotlight reopen.
    public func showMenuBarIcon() {
        guard !isMenuBarVisible else { return }
        setMenuBarVisible(true)
    }

    /// Toggle menu bar icon visibility. Called from the global hotkey (⌘⇧M).
    public func toggleMenuBarVisibility() {
        setMenuBarVisible(!isMenuBarVisible)
    }

    private func setMenuBarVisible(_ visible: Bool) {
        isMenuBarVisible = visible
        statusItem.isVisible = visible

        if visible {
            // Rebuild menu and update icon to reflect current state
            let isEnabled = multitouchManager?.isEnabled ?? false
            updateStatusIcon(enabled: isEnabled)
            buildMenu()

            // Pop the menu open so the user knows it's back
            // Skip during tests — performClick opens a modal menu loop that stalls CI
            let isRunningTests = NSClassFromString("XCTestCase") != nil
            if !isRunningTests, let button = statusItem.button {
                button.performClick(nil)
            }
        }
    }
}

extension MenuBarController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        // Refresh system-setting-dependent controls whenever the submenu opens.
        guard let parent = unsafe menu.supermenu,
              let item = parent.items.first(where: { $0.submenu === menu }),
              let gesture = item.representedObject as? GestureChoice else { return }
        updateTapResponsivenessMenu(menu, fingerCount: gesture.fingerCount)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    public static let preferencesChanged = Notification.Name("MiddleDragPreferencesChanged")
    public static let launchAtLoginChanged = Notification.Name("MiddleDragLaunchAtLoginChanged")
    /// Posted when a multitouch device connects after polling (e.g., Bluetooth trackpad at boot)
    public static let middleDragDeviceConnected = Notification.Name("MiddleDragDeviceConnected")
    /// Posted when device polling times out without finding a device
    public static let middleDragPollingTimedOut = Notification.Name("MiddleDragPollingTimedOut")
}

