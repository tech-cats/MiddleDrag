import Cocoa

// MARK: - Protocols for Dependency Injection

/// Protocol for presenting alerts and opening URLs, enabling testability
@MainActor
protocol AlertPresenter {
    func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse
    func openURL(_ url: URL)
}

/// Default implementation using NSAlert and NSWorkspace
@MainActor
class DefaultAlertPresenter: AlertPresenter {
    func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        return alert.runModal()
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Helper for displaying alerts and dialogs
@MainActor
public class AlertHelper {

    // MARK: - Dependency Injection

    /// Injectable presenter for testing
    static var presenter: AlertPresenter = DefaultAlertPresenter()

    enum NativeTapCaveat {
        case oneFingerTapToDrag
        case twoFingerTapToClick
        case twoFingerTapToDrag
    }

    // MARK: - Alert Configuration (Testable)

    /// Creates and returns a configured About alert without presenting it
    static func createAboutAlert() -> NSAlert {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        let alert = NSAlert()
        alert.messageText = "MiddleDrag"
        alert.icon = NSImage(
            systemSymbolName: "hand.raised.fingers.spread", accessibilityDescription: nil)
        alert.informativeText = """
            Three-finger drag for middle mouse button emulation.
            Works alongside your system gestures!

            Version \(version)

            ✨ Features:
            • Works WITH system gestures enabled
            • Three-finger drag → Middle mouse drag
            • Three-finger tap → Middle mouse click
            • Smart gesture detection
            • Minimal CPU usage

            💡 Tips:
            • No need to disable system gestures
            • Adjust sensitivity for your workflow
            • Use "Check for Conflicting System Gestures..." for advanced control

            Created for engineers, designers, and makers.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")
        return alert
    }

    /// Creates and returns a configured Quick Setup alert without presenting it
    static func createQuickSetupAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "MiddleDrag Quick Setup"
        alert.informativeText = """
            ✅ MiddleDrag works WITH your existing trackpad gestures!

            No configuration needed - just use:
            • Three fingers drag = Middle mouse drag
            • Three-finger tap = Middle click

            Optional optimizations:
            • If you experience conflicts, you can disable system three-finger gestures
            • Use "Check for Conflicting System Gestures..." in the Advanced menu for optimal control

            That's it! MiddleDrag uses Apple's multitouch framework to detect gestures before the system processes them.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it!")
        alert.addButton(withTitle: "Open Trackpad Settings")
        return alert
    }

    private struct CompatibilityCaveat {
        let title: String
        let message: String
        let guidance: String
        let settingsPath: String
    }

    private static func createCompatibilityAlert(_ caveat: CompatibilityCaveat) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = caveat.title
        alert.informativeText = caveat.message
        alert.accessoryView = createSettingsGuidance(caveat.guidance, settingsPath: caveat.settingsPath)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        return alert
    }

    private static func smartZoomCaveat(button: GestureMouseButton) -> CompatibilityCaveat {
        let settingsPath = "System Settings → Trackpad → Scroll & Zoom"
        return CompatibilityCaveat(
            title: "Caveats on compatibility with Smart Zoom",
            message: """
                You may notice a little delay before \(button.displayName.lowercased()) button clicks after tapping with two fingers, when "Smart Zoom" is enabled in system trackpad settings.

                MiddleDrag needs to determine whether the gesture is a 2-finger double tap, so it doesn't generate two clicks while you intend to do Smart Zoom. We can't guess if you want a double tap as soon as you lift your fingers for the first tap, so the click has to come after a timeout.
                """,
            guidance: "If you want more responsive clicks or if you do need double click from double tap, turn off Smart Zoom in \(settingsPath) tab.",
            settingsPath: settingsPath)
    }

    static func createSmartZoomCompatibilityAlert(button: GestureMouseButton) -> NSAlert {
        createCompatibilityAlert(smartZoomCaveat(button: button))
    }

    private static func nativeTapCaveat(_ caveat: NativeTapCaveat) -> CompatibilityCaveat {
        let settingsPath = "System Settings → Trackpad → Point & Click tab"
        let title: String
        let message: String
        let guidance: String
        switch caveat {
        case .oneFingerTapToDrag:
            title = "1-finger Tap to Drag Compatibility"
            message = "You have \"Tap to click\" enabled in system trackpad settings. The first tap of a tap-to-drag gesture will natively generate a click event, which means a real click will always precede your dragging."
            guidance = "If you don't want this, turn off \"Tap to click\" in \(settingsPath) and use MiddleDrag's Tap to Click options instead."
        case .twoFingerTapToClick:
            title = "2-finger Tap to Click Compatibility"
            message = "You have \"Secondary click\" set to \"Click or Tap with Two Fingers\" in system trackpad settings. A 2-finger tap will generate duplicate clicks from MiddleDrag and the system."
            guidance = "Set \"Secondary click\" to another option or turn off \"Tap to click\" in \(settingsPath) to use MiddleDrag's event exclusively."
        case .twoFingerTapToDrag:
            title = "2-finger Tap to Drag Compatibility"
            message = "You have \"Secondary click\" set to \"Click or Tap with Two Fingers\" in system trackpad settings. The first tap of a tap-to-drag gesture will natively generate a right click event, which means a real right click will always precede your dragging."
            guidance = "If you don't want this, set \"Secondary click\" to another option or turn off \"Tap to click\" in \(settingsPath) and use MiddleDrag's Tap to Click options instead."
        }
        return CompatibilityCaveat(title: title, message: message, guidance: guidance, settingsPath: settingsPath)
    }

    static func createNativeTapCompatibilityAlert(_ caveat: NativeTapCaveat) -> NSAlert {
        createCompatibilityAlert(nativeTapCaveat(caveat))
    }

    private static func threeFingerGestureCaveat() -> CompatibilityCaveat? {
        let conflicts = SystemGestureHelper.conflictingThreeFingerGestures()
        guard !conflicts.isEmpty else { return nil }
        let settingsPath = "System Settings → Trackpad → More Gestures"
        return CompatibilityCaveat(
            title: "3-finger Drag Compatibility",
            message: """
                You have system three-finger swipe gestures enabled that can conflict with MiddleDrag's 3-finger Direct Drag or 3-finger Tap to Drag:

                \(conflicts.map { "• \($0)" }.joined(separator: "\n"))
                """,
            guidance: "To use MiddleDrag's three-finger dragging, turn off the conflicting gestures or select four-finger swipes in \(settingsPath).",
            settingsPath: settingsPath)
    }

    private static func systemGestureCaveats(configuration: GestureConfiguration) -> [CompatibilityCaveat] {
        var caveats: [CompatibilityCaveat] = []
        if configuration.middleDragEnabled || configuration.tapToDragEnabled,
           let caveat = threeFingerGestureCaveat() {
            caveats.append(caveat)
        }
        if configuration.oneFingerTaps.tapToDragEnabled && SystemGestureHelper.isTapToClickEnabled() {
            caveats.append(nativeTapCaveat(.oneFingerTapToDrag))
        }
        let twoFinger = configuration.twoFingerTaps
        if (twoFinger.tapToClickEnabled || twoFinger.tapToDragEnabled)
            && SystemGestureHelper.isTwoFingerSecondaryTapEnabled() {
            if twoFinger.tapToClickEnabled { caveats.append(nativeTapCaveat(.twoFingerTapToClick)) }
            if twoFinger.tapToDragEnabled { caveats.append(nativeTapCaveat(.twoFingerTapToDrag)) }
        }
        if twoFinger.tapToClickEnabled && SystemGestureHelper.isSmartZoomEnabled() {
            caveats.append(smartZoomCaveat(button: twoFinger.tapButton))
        }
        return caveats
    }

    static func createSystemGestureConflictsAlert(configuration: GestureConfiguration) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Check for Conflicting System Gestures"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        let caveats = systemGestureCaveats(configuration: configuration)
        guard !caveats.isEmpty else {
            alert.informativeText = "No known conflicts were detected for your enabled MiddleDrag gestures."
            return alert
        }
        alert.informativeText = "These system settings affect your enabled MiddleDrag gestures:"
        alert.accessoryView = createCaveatsView(caveats)
        return alert
    }

    private static func createCaveatsView(_ caveats: [CompatibilityCaveat]) -> NSScrollView {
        let content = NSMutableAttributedString(string: "")
        for caveat in caveats {
            if content.length > 0 { content.append(NSAttributedString(string: "\n\n")) }
            let text = "\(caveat.title)\n\n\(caveat.message)\n\n\(caveat.guidance)"
            let section = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ])
            section.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                range: NSRange(location: 0, length: (caveat.title as NSString).length))
            section.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                range: (text as NSString).range(of: caveat.settingsPath))
            content.append(section)
        }
        let width: CGFloat = 540
        let height = ceil(content.boundingRect(
            with: NSSize(width: width - 32, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 16
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(height, 420)))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        unsafe textView.textContainer?.widthTracksTextView = true
        unsafe textView.textStorage?.setAttributedString(content)
        scrollView.documentView = textView
        return scrollView
    }

    private static func createSettingsGuidance(_ guidance: String, settingsPath: String) -> NSTextField {
        let attributedGuidance = NSMutableAttributedString(string: guidance, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ])
        attributedGuidance.addAttribute(.font,
            value: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            range: (guidance as NSString).range(of: settingsPath))
        let label = NSTextField(wrappingLabelWithString: guidance)
        label.attributedStringValue = attributedGuidance
        label.preferredMaxLayoutWidth = 420
        label.frame.size = NSSize(width: 420,
            height: ceil(attributedGuidance.boundingRect(
                with: NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 4)
        return label
    }

    // MARK: - URL Constants

    /// GitHub project URL
    static let gitHubURL = URL(
        string: "https://github.com/NullPointerDepressiveDisorder/MiddleDrag")

    /// Trackpad settings URL
    static let trackpadSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.trackpad")

    // MARK: - Public Methods (Present Alerts)

    static func showAbout() {
        let alert = createAboutAlert()
        if presenter.runModal(alert) == .alertSecondButtonReturn {
            if let url = gitHubURL {
                presenter.openURL(url)
            }
        }
    }

    static func showQuickSetup() {
        let alert = createQuickSetupAlert()
        if presenter.runModal(alert) == .alertSecondButtonReturn {
            openTrackpadSettings()
        }
    }

    static func showSmartZoomCompatibility(button: GestureMouseButton) {
        _ = presenter.runModal(createSmartZoomCompatibilityAlert(button: button))
    }

    static func showNativeTapCompatibility(_ caveat: NativeTapCaveat) {
        _ = presenter.runModal(createNativeTapCompatibilityAlert(caveat))
    }

    public static func showThreeFingerGestureCompatibilityIfNeeded() {
        guard let caveat = threeFingerGestureCaveat() else { return }
        _ = presenter.runModal(createCompatibilityAlert(caveat))
    }

    static func showSystemGestureConflicts(configuration: GestureConfiguration) {
        _ = presenter.runModal(createSystemGestureConflictsAlert(configuration: configuration))
    }

    private static func openTrackpadSettings() {
        if let url = trackpadSettingsURL {
            presenter.openURL(url)
        }
    }
}
