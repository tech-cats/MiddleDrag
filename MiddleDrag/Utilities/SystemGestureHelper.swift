import Foundation

// MARK: - Protocols for Dependency Injection

/// Protocol for reading trackpad settings, enabling testability
protocol TrackpadSettingsProvider {
    func getSetting(forKey key: String, domain: String) -> Int?
}

// MARK: - Default Implementations

/// Default implementation using UserDefaults
class DefaultTrackpadSettingsProvider: TrackpadSettingsProvider {
    func getSetting(forKey key: String, domain: String) -> Int? {
        let defaults = UserDefaults(suiteName: domain)
        return defaults?.object(forKey: key) as? Int
    }
}

/// Read-only helper for detecting macOS settings that conflict with MiddleDrag.
public class SystemGestureHelper {

    // MARK: - Dependency Injection

    /// Injectable settings provider for testing
    /// Note: Only mutated during test setup, not during concurrent execution
    nonisolated(unsafe) static var settingsProvider: TrackpadSettingsProvider = DefaultTrackpadSettingsProvider()

    // MARK: - Constants

    /// Trackpad settings domain
    static let trackpadDomain = "com.apple.AppleMultitouchTrackpad"
    static let bluetoothTrackpadDomain = "com.apple.driver.AppleBluetoothMultitouch.trackpad"

    /// Trackpad gesture setting keys
    enum TrackpadKey: String, CaseIterable {
        case threeFingerVertSwipe = "TrackpadThreeFingerVertSwipeGesture"
        case threeFingerHorizSwipe = "TrackpadThreeFingerHorizSwipeGesture"
        case fourFingerVertSwipe = "TrackpadFourFingerVertSwipeGesture"
        case fourFingerHorizSwipe = "TrackpadFourFingerHorizSwipeGesture"
    }

    // MARK: - Detection

    /// Read only: Smart Zoom uses 0 for off and a nonzero value for on. Touch
    /// frames do not identify which preference domain owns the device, so give
    /// Smart Zoom priority conservatively if either trackpad domain enables it.
    static func isSmartZoomEnabled() -> Bool {
        let key = "TrackpadTwoFingerDoubleTapGesture"
        return [trackpadDomain, bluetoothTrackpadDomain].contains { domain in
            (unsafe settingsProvider.getSetting(forKey: key, domain: domain) ?? 0) != 0
        }
    }

    static func isTapToClickEnabled() -> Bool {
        [trackpadDomain, bluetoothTrackpadDomain].contains { domain in
            (unsafe settingsProvider.getSetting(forKey: "Clicking", domain: domain) ?? 0) != 0
        }
    }

    /// All conditions must hold in the same device domain. Corner secondary
    /// clicks do not generate the native two-finger tap this caveat describes.
    static func isTwoFingerSecondaryTapEnabled() -> Bool {
        [trackpadDomain, bluetoothTrackpadDomain].contains { domain in
            let tapping = unsafe settingsProvider.getSetting(forKey: "Clicking", domain: domain) ?? 0
            let secondaryClick = unsafe settingsProvider.getSetting(forKey: "TrackpadRightClick", domain: domain) ?? 0
            let secondaryCorner = unsafe settingsProvider.getSetting(forKey: "TrackpadCornerSecondaryClick", domain: domain) ?? 0
            return tapping != 0 && secondaryClick != 0 && secondaryCorner == 0
        }
    }

    /// Returns true if 3-finger gestures are enabled that could conflict with MiddleDrag
    public static func hasConflictingSettings() -> Bool {
        !conflictingThreeFingerGestures().isEmpty
    }

    public static func hasConflictingSettings(for configuration: GestureConfiguration) -> Bool {
        (configuration.middleDragEnabled || configuration.tapToDragEnabled) && hasConflictingSettings()
    }

    /// Report each conflicting gesture once, even if both trackpads enable it.
    static func conflictingThreeFingerGestures() -> [String] {
        let gestures: [(TrackpadKey, String)] = [
            (.threeFingerVertSwipe, "3-finger vertical swipe (Mission Control)"),
            (.threeFingerHorizSwipe, "3-finger horizontal swipe (Spaces)")
        ]
        return gestures.compactMap { key, description in
            let enabled = [trackpadDomain, bluetoothTrackpadDomain].contains { domain in
                (unsafe settingsProvider.getSetting(forKey: key.rawValue, domain: domain) ?? 0) != 0
            }
            return enabled ? description : nil
        }
    }

    /// Returns the current value for a trackpad setting
    /// - Parameter key: The trackpad setting key to read
    /// - Returns: The integer value, or nil if not found
    static func getTrackpadSetting(_ key: TrackpadKey) -> Int? {
        return unsafe settingsProvider.getSetting(forKey: key.rawValue, domain: trackpadDomain)
    }

    /// Returns a dictionary of all current trackpad gesture settings
    static func getAllSettings() -> [TrackpadKey: Int] {
        var settings: [TrackpadKey: Int] = [:]
        for key in TrackpadKey.allCases {
            if let value = getTrackpadSetting(key) {
                settings[key] = value
            }
        }
        return settings
    }

    // MARK: - Description

    /// Returns a human-readable description of only conflicting (3-finger) settings
    /// Use this when displaying which settings conflict with MiddleDrag
    static func describeConflictingSettings() -> String {
        let gestures = conflictingThreeFingerGestures()
        return gestures.isEmpty ? "No conflicting gestures detected"
            : gestures.map { "• \($0): Enabled" }.joined(separator: "\n")
    }

    /// Returns a human-readable description of all current gesture settings
    static func describeCurrentSettings() -> String {
        let threeVert = getTrackpadSetting(.threeFingerVertSwipe) ?? 0
        let threeHoriz = getTrackpadSetting(.threeFingerHorizSwipe) ?? 0
        let fourVert = getTrackpadSetting(.fourFingerVertSwipe) ?? 0
        let fourHoriz = getTrackpadSetting(.fourFingerHorizSwipe) ?? 0

        var lines: [String] = []

        if threeVert != 0 {
            lines.append("• 3-finger vertical swipe (Mission Control): Enabled")
        }
        if threeHoriz != 0 {
            lines.append("• 3-finger horizontal swipe (Spaces): Enabled")
        }
        if fourVert != 0 {
            lines.append("• 4-finger vertical swipe (Mission Control): Enabled")
        }
        if fourHoriz != 0 {
            lines.append("• 4-finger horizontal swipe (Spaces): Enabled")
        }

        if lines.isEmpty {
            return "All system gestures are disabled"
        }

        return lines.joined(separator: "\n")
    }
}
