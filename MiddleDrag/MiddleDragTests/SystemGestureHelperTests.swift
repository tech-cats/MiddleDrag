import XCTest

@testable import MiddleDragCore

// MARK: - Mock Implementations

/// Mock settings provider for testing SystemGestureHelper
class MockTrackpadSettingsProvider: TrackpadSettingsProvider {
    var settings: [String: Int] = [:]

    func getSetting(forKey key: String, domain: String) -> Int? {
        return settings[key]
    }

    func setSetting(_ value: Int, forKey key: String) {
        settings[key] = value
    }

    func clearSettings() {
        settings.removeAll()
    }
}

final class SystemGestureHelperTests: XCTestCase {

    var mockSettingsProvider: MockTrackpadSettingsProvider!

    // Store original providers for restoration
    var originalSettingsProvider: TrackpadSettingsProvider!

    override func setUp() {
        super.setUp()
        // Save originals
        originalSettingsProvider = unsafe SystemGestureHelper.settingsProvider

        // Create and inject mocks
        mockSettingsProvider = MockTrackpadSettingsProvider()
        unsafe SystemGestureHelper.settingsProvider = mockSettingsProvider
    }

    override func tearDown() {
        // Restore originals
        unsafe SystemGestureHelper.settingsProvider = originalSettingsProvider
        mockSettingsProvider = nil
        super.tearDown()
    }

    // MARK: - TrackpadKey Tests

    func testTrackpadKeyRawValues() {
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue,
            "TrackpadThreeFingerVertSwipeGesture"
        )
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue,
            "TrackpadThreeFingerHorizSwipeGesture"
        )
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue,
            "TrackpadFourFingerVertSwipeGesture"
        )
        XCTAssertEqual(
            SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue,
            "TrackpadFourFingerHorizSwipeGesture"
        )
    }

    func testTrackpadKeyAllCases() {
        let allCases = SystemGestureHelper.TrackpadKey.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.threeFingerVertSwipe))
        XCTAssertTrue(allCases.contains(.threeFingerHorizSwipe))
        XCTAssertTrue(allCases.contains(.fourFingerVertSwipe))
        XCTAssertTrue(allCases.contains(.fourFingerHorizSwipe))
    }

    // MARK: - trackpadDomain Tests

    func testTrackpadDomain() {
        XCTAssertEqual(
            SystemGestureHelper.trackpadDomain,
            "com.apple.AppleMultitouchTrackpad"
        )
    }

    // MARK: - getTrackpadSetting Tests

    func testGetTrackpadSettingReturnsValueWhenSet() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)

        let result = SystemGestureHelper.getTrackpadSetting(.threeFingerVertSwipe)

        XCTAssertEqual(result, 2)
    }

    func testGetTrackpadSettingReturnsNilWhenNotSet() {
        mockSettingsProvider.clearSettings()

        let result = SystemGestureHelper.getTrackpadSetting(.threeFingerVertSwipe)

        XCTAssertNil(result)
    }

    func testGetTrackpadSettingReturnsCorrectValueForEachKey() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            1, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            3, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.threeFingerVertSwipe), 0)
        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.threeFingerHorizSwipe), 2)
        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.fourFingerVertSwipe), 1)
        XCTAssertEqual(SystemGestureHelper.getTrackpadSetting(.fourFingerHorizSwipe), 3)
    }

    // MARK: - getAllSettings Tests

    func testGetAllSettingsReturnsEmptyWhenNoSettings() {
        mockSettingsProvider.clearSettings()

        let settings = SystemGestureHelper.getAllSettings()

        XCTAssertTrue(settings.isEmpty)
    }

    func testGetAllSettingsReturnsAllSetValues() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let settings = SystemGestureHelper.getAllSettings()

        XCTAssertEqual(settings.count, 4)
        XCTAssertEqual(settings[.threeFingerVertSwipe], 0)
        XCTAssertEqual(settings[.threeFingerHorizSwipe], 2)
        XCTAssertEqual(settings[.fourFingerVertSwipe], 2)
        XCTAssertEqual(settings[.fourFingerHorizSwipe], 2)
    }

    func testGetAllSettingsOnlyReturnsSetKeys() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)

        let settings = SystemGestureHelper.getAllSettings()

        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings[.threeFingerVertSwipe], 2)
    }

    // MARK: - hasConflictingSettings Tests

    func testHasConflictingSettingsReturnsFalseWhenAllDisabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertFalse(hasConflicts)
    }

    func testHasConflictingSettingsReturnsFalseWhenNotSet() {
        mockSettingsProvider.clearSettings()

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertFalse(hasConflicts)
    }

    func testHasConflictingSettingsReturnsTrueWhenVertEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertTrue(hasConflicts)
    }

    func testHasConflictingSettingsReturnsTrueWhenHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertTrue(hasConflicts)
    }

    func testHasConflictingSettingsReturnsTrueWhenBothEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertTrue(hasConflicts)
    }

    func testHasConflictingSettingsIgnoresFourFingerSettings() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let hasConflicts = SystemGestureHelper.hasConflictingSettings()

        XCTAssertFalse(hasConflicts)
    }

    // MARK: - describeCurrentSettings Tests

    func testDescribeCurrentSettingsWhenAllDisabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertEqual(description, "All system gestures are disabled")
    }

    func testDescribeCurrentSettingsWhenNoneSet() {
        mockSettingsProvider.clearSettings()

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertEqual(description, "All system gestures are disabled")
    }

    func testDescribeCurrentSettingsWhenThreeFingerVertEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("3-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertFalse(description.contains("3-finger horizontal swipe"))
    }

    func testDescribeCurrentSettingsWhenThreeFingerHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("3-finger horizontal swipe (Spaces): Enabled"))
        XCTAssertFalse(description.contains("3-finger vertical swipe"))
    }

    func testDescribeCurrentSettingsWhenFourFingerVertEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("4-finger vertical swipe (Mission Control): Enabled"))
    }

    func testDescribeCurrentSettingsWhenFourFingerHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("4-finger horizontal swipe (Spaces): Enabled"))
    }

    func testDescribeCurrentSettingsWhenAllEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        XCTAssertTrue(description.contains("3-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertTrue(description.contains("3-finger horizontal swipe (Spaces): Enabled"))
        XCTAssertTrue(description.contains("4-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertTrue(description.contains("4-finger horizontal swipe (Spaces): Enabled"))
    }

    func testDescribeCurrentSettingsFormatsMultipleLinesCorrectly() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeCurrentSettings()

        // Should be joined by newlines
        let lines = description.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
    }

    // MARK: - Default Implementation Tests

    func testDefaultTrackpadSettingsProviderExists() {
        let provider = DefaultTrackpadSettingsProvider()
        XCTAssertNotNil(provider)
    }

    // MARK: - describeConflictingSettings Tests

    func testDescribeConflictingSettingsWhenNoConflicts() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertEqual(description, "No conflicting gestures detected")
    }

    func testDescribeConflictingSettingsWhenNoneSet() {
        mockSettingsProvider.clearSettings()

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertEqual(description, "No conflicting gestures detected")
    }

    func testDescribeConflictingSettingsOnlyShowsThreeFingerGestures() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        // Should only show 3-finger gestures, not 4-finger
        XCTAssertTrue(description.contains("3-finger vertical swipe"))
        XCTAssertTrue(description.contains("3-finger horizontal swipe"))
        XCTAssertFalse(description.contains("4-finger"))
    }

    func testDescribeConflictingSettingsWhenOnlyVertEnabled() {
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertTrue(description.contains("3-finger vertical swipe (Mission Control): Enabled"))
        XCTAssertFalse(description.contains("3-finger horizontal swipe"))
    }

    func testDescribeConflictingSettingsWhenOnlyHorizEnabled() {
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        XCTAssertTrue(description.contains("3-finger horizontal swipe (Spaces): Enabled"))
        XCTAssertFalse(description.contains("3-finger vertical swipe"))
    }

    func testDescribeConflictingSettingsIgnoresFourFingerGestures() {
        // Only 4-finger enabled, no 3-finger
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            0, forKey: SystemGestureHelper.TrackpadKey.threeFingerHorizSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerVertSwipe.rawValue)
        mockSettingsProvider.setSetting(
            2, forKey: SystemGestureHelper.TrackpadKey.fourFingerHorizSwipe.rawValue)

        let description = SystemGestureHelper.describeConflictingSettings()

        // Should say no conflicts since 4-finger gestures don't conflict
        XCTAssertEqual(description, "No conflicting gestures detected")
    }
}
