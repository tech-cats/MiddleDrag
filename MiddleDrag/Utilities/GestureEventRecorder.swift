import Foundation
import QuartzCore

/// Opt-in, bounded, local diagnostics. No disk I/O occurs on gesture/event queues,
/// and records never pass through Log or the telemetry SDK.
final class GestureEventRecorder: @unchecked Sendable {
    static let shared = GestureEventRecorder()

    private let lock = NSLock()
    private let capacity = 30_000
    private var recording = false
    private var entries: [String] = []
    private var nextIndex = 0
    private var sequence: UInt64 = 0
    private var startedAt = Date()
    private var startedUptime: CFTimeInterval = 0
    private var session = ""

    var isRecording: Bool { lock.withLock { recording } }
    var hasRecords: Bool { lock.withLock { !entries.isEmpty } }

    func start() {
        lock.withLock {
            entries.removeAll(keepingCapacity: true)
            nextIndex = 0
            sequence = 0
            startedAt = Date()
            startedUptime = CACurrentMediaTime()
            session = UUID().uuidString
            recording = true
            appendLocked("capture.started", details: "capacity=\(capacity)")
        }
    }

    func stop() {
        lock.withLock {
            guard recording else { return }
            appendLocked("capture.stopped", details: "")
            recording = false
        }
    }

    /// Details are evaluated only while recording. Keep them to plain values;
    /// callers must capture values protected by other locks before calling here.
    func record(_ event: String, _ details: @autoclosure () -> String = "") {
        lock.withLock {
            guard recording else { return }
            appendLocked(event, details: details())
        }
    }

    private func appendLocked(_ event: String, details: String) {
        sequence &+= 1
        let elapsed = unsafe String(format: "%.6f", CACurrentMediaTime() - startedUptime)
        let line = "\(sequence)\t\(elapsed)\t[MD-GESTURE] \(event)\t\(details)"
        if entries.count < capacity {
            entries.append(line)
        } else {
            entries[nextIndex] = line
            nextIndex = (nextIndex + 1) % capacity
        }
    }

    func snapshot() -> String {
        let (lines, date, id, total, active) = lock.withLock {
            let ordered = Array(entries[nextIndex...]) + Array(entries[..<nextIndex])
            return (ordered, startedAt, session, sequence, recording)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return """
        MiddleDrag gesture event log v1
        session=\(id)
        started_at=\(ISO8601DateFormatter().string(from: date))
        app_version=\(version) build=\(build)
        os=\(ProcessInfo.processInfo.operatingSystemVersionString)
        recording=\(active) retained=\(lines.count) dropped=\(total - UInt64(lines.count))
        Times are monotonic seconds since capture start. frame_time uses the separate touch-device clock.
        The buffer retains the newest \(capacity) records. No application names, text, or screen coordinates are collected.
        sequence\tseconds\tevent\tdetails
        \(lines.joined(separator: "\n"))

        """
    }

    func recordConfiguration(_ config: GestureConfiguration) {
        record("configuration",
               "tap_enabled=\(config.tapToClickEnabled) tap_button=\(config.tapButton.rawValue) "
               + "direct_drag_enabled=\(config.middleDragEnabled) direct_drag_button=\(config.directDragButton.rawValue) "
               + "force_click_conversion=\(config.allowsForceClickConversion) "
               + "tap_to_drag_enabled=\(config.tapToDragEnabled) tap_to_drag_button=\(config.tapToDragButton.rawValue) "
               + "sequence_timeout=\(config.tapToDragTimeout) tap_limit=\(config.tapThreshold) "
               + "max_tap_hold=\(config.maxTapHoldDuration) move_threshold=\(config.moveThreshold) "
               + "relift=\(config.allowReliftDuringDrag) modifier_required=\(config.requireModifierKey) modifier=\(config.modifierKeyType.rawValue) "
               + "exclusion_enabled=\(config.exclusionZoneEnabled) exclusion_size=\(config.exclusionZoneSize) "
               + "contact_filter=\(config.contactSizeFilterEnabled) max_contact_size=\(config.maxContactSize) "
               + "ignore_desktop=\(config.ignoreDesktop) window_filter=\(config.minimumWindowSizeFilterEnabled) "
               + "min_window=\(config.minimumWindowWidth)x\(config.minimumWindowHeight) title_bar_passthrough=\(config.passThroughTitleBar) "
               + "sensitivity=\(config.sensitivity) smoothing=\(config.smoothingFactor)")
    }
}
