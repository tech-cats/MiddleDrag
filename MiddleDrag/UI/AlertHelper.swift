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
            • Use "Configure System Gestures..." for advanced control

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
            • Use "Configure System Gestures..." in the Advanced menu for optimal control

            That's it! MiddleDrag uses Apple's multitouch framework to detect gestures before the system processes them.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it!")
        alert.addButton(withTitle: "Open Trackpad Settings")
        return alert
    }

    /// Creates and returns a configured Already Optimal alert without presenting it
    static func createGestureConfigurationAlreadyOptimalAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "System Gestures Already Configured"
        alert.informativeText = """
            ✅ Your trackpad is already configured for optimal MiddleDrag compatibility!

            3-finger system gestures are disabled, allowing MiddleDrag to use three-finger gestures without conflicts.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        return alert
    }

    /// Creates and returns a configured Gesture Configuration Prompt alert without presenting it
    /// - Parameter isFirstLaunch: Whether this is shown on first launch (affects both the welcome message and the button text)
    static func createGestureConfigurationPromptAlert(isFirstLaunch: Bool = false) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Configure System Gestures"
        
        let introText = isFirstLaunch
            ? "Welcome to MiddleDrag! We detected that your trackpad has 3-finger gestures enabled which can conflict with MiddleDrag."
            : "MiddleDrag uses 3-finger gestures which can conflict with macOS system gestures."
        
        alert.informativeText = """
            \(introText)

            Current conflicting settings:
            \(SystemGestureHelper.describeConflictingSettings())

            Would you like to automatically:
            • Disable 3-finger system gestures
            • Enable 4-finger gestures instead

            This preserves Mission Control and Spaces functionality while freeing up 3-finger gestures for MiddleDrag.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply Changes")
        alert.addButton(withTitle: "Open Trackpad Settings")
        alert.addButton(withTitle: isFirstLaunch ? "Not Now" : "Cancel")
        return alert
    }

    /// Creates and returns a configured Success alert without presenting it
    static func createGestureConfigurationSuccessAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Settings Applied"
        alert.informativeText = """
            ✅ System gesture settings have been updated!

            Changes applied:
            • 3-finger Mission Control → 4-finger
            • 3-finger Spaces swipe → 4-finger

            The Dock has been restarted to apply changes.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        return alert
    }

    /// Creates and returns a configured Failure alert without presenting it
    static func createGestureConfigurationFailureAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Failed to Apply Settings"
        alert.informativeText = """
            ⚠️ Some settings could not be applied automatically.

            Please configure manually:
            1. Open System Settings → Trackpad → More Gestures
            2. Set Mission Control to "Swipe Up with Four Fingers"
            3. Set "Swipe between full-screen applications" to "Swipe Left or Right with Four Fingers"
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Trackpad Settings")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func createSmartZoomCompatibilityAlert(button: GestureMouseButton) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Caveats on compatibility with Smart Zoom"
        alert.informativeText = """
            You may notice a little delay before \(button.displayName.lowercased()) button clicks after tapping with two fingers, when "Smart Zoom" is enabled in system trackpad settings.

            MiddleDrag needs to determine whether the gesture is a 2-finger double tap, so it doesn't generate two clicks while you intend to do Smart Zoom. We can't guess if you want a double tap as soon as you lift your fingers for the first tap, so the click has to come after a timeout.
            """

        let settingsPath = "System Settings → Trackpad → Scroll & Zoom"
        let guidance = "If you want more responsive clicks or if you do need double click from double tap, turn off Smart Zoom in \(settingsPath) tab."
        alert.accessoryView = createSettingsGuidance(guidance, settingsPath: settingsPath)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        return alert
    }

    static func createNativeTapCompatibilityAlert(_ caveat: NativeTapCaveat) -> NSAlert {
        let alert = NSAlert()
        let settingsPath = "System Settings → Trackpad → Point & Click tab"
        let guidance: String
        switch caveat {
        case .oneFingerTapToDrag:
            alert.messageText = "1-finger Tap to Drag Compatibility"
            alert.informativeText = "You have \"Tap to click\" enabled in system trackpad settings. The first tap of a tap-to-drag gesture will natively generate a click event, which means a real click will always precede your dragging."
            guidance = "If you don't want this, turn off \"Tap to click\" in \(settingsPath) and use MiddleDrag's Tap to Click options instead."
        case .twoFingerTapToClick:
            alert.messageText = "2-finger Tap to Click Compatibility"
            alert.informativeText = "You have \"Secondary click\" set to \"Click or Tap with Two Fingers\" in system trackpad settings. A 2-finger tap will generate duplicate clicks from MiddleDrag and the system."
            guidance = "Set \"Secondary click\" to another option or turn off \"Tap to click\" in \(settingsPath) to use MiddleDrag's event exclusively."
        case .twoFingerTapToDrag:
            alert.messageText = "2-finger Tap to Drag Compatibility"
            alert.informativeText = "You have \"Secondary click\" set to \"Click or Tap with Two Fingers\" in system trackpad settings. The first tap of a tap-to-drag gesture will natively generate a right click event, which means a real right click will always precede your dragging."
            guidance = "If you don't want this, set \"Secondary click\" to another option or turn off \"Tap to click\" in \(settingsPath) and use MiddleDrag's Tap to Click options instead."
        }
        alert.accessoryView = createSettingsGuidance(guidance, settingsPath: settingsPath)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        return alert
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

    /// Show dialog for configuring system gestures when they're already optimal
    static func showGestureConfigurationAlreadyOptimal() {
        let alert = createGestureConfigurationAlreadyOptimalAlert()
        _ = presenter.runModal(alert)
    }

    /// Show dialog explaining gesture conflict and offering to apply changes
    /// - Parameters:
    ///   - isFirstLaunch: Whether this is shown on first launch (affects both the welcome message and the button text)
    ///   - onDismiss: Optional callback when user dismisses without applying changes
    /// - Returns: true if user wants to apply the recommended changes
    public static func showGestureConfigurationPrompt(
        isFirstLaunch: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) -> Bool {
        let alert = createGestureConfigurationPromptAlert(isFirstLaunch: isFirstLaunch)
        let response = presenter.runModal(alert)

        if response == .alertSecondButtonReturn {
            openTrackpadSettings()
            return false
        }

        if response == .alertThirdButtonReturn {
            // User dismissed (Cancel or Not Now)
            onDismiss?()
            return false
        }

        return response == .alertFirstButtonReturn
    }

    /// Show success feedback after applying changes
    public static func showGestureConfigurationSuccess() {
        let alert = createGestureConfigurationSuccessAlert()
        _ = presenter.runModal(alert)
    }

    /// Show failure feedback if changes couldn't be applied
    public static func showGestureConfigurationFailure() {
        let alert = createGestureConfigurationFailureAlert()
        if presenter.runModal(alert) == .alertFirstButtonReturn {
            openTrackpadSettings()
        }
    }

    private static func openTrackpadSettings() {
        if let url = trackpadSettingsURL {
            presenter.openURL(url)
        }
    }
}
