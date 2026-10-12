import Cocoa
import CoreGraphics
import Foundation

/// Manages gesture recognition from touch input
/// Touch processing, deadlines, configuration, and reset must run on timerQueue.
class GestureRecognizer: @unchecked Sendable {

    // MARK: - Properties

    /// Configuration for gesture detection
    var configuration = GestureConfiguration()

    /// Current gesture state
    private(set) var state: GestureState = .idle

    /// Delegate for gesture events
    weak var delegate: GestureRecognizerDelegate?

    // Position tracking
    private var lastFingerPositions: [MTPoint] = []
    private var gestureStartTime: Double = 0
    private var gestureStartPosition: MTPoint?
    private var lastCentroid: MTPoint?
    private var frameCount: Int = 0
    private(set) var traceContactID: UInt64 = 0
    private var pendingTapContactID: UInt64 = 0
    private var lastTraceFingerCount = -1
    private var traceMaximumMovement: Float = 0

    // Stability tracking - prevents false gesture ends during brief state transitions
    private var stableFrameCount: Int = 0

    // Cooldown after 4-finger cancellation
    // Prevents accidental gesture triggers when lifting one finger during Mission Control
    private var isInCancellationCooldown: Bool = false

    // The coordinator supplies its serial gesture queue; deadlines do not depend on
    // stationary contacts producing another hardware frame.
    var timerQueue: DispatchQueue = .main
    private(set) var isTapToDragContact = false
    private var pendingTap = false
    private var pendingTapReleaseTime: Double = 0
    private var releaseTime: Double?
    private var tapDeadline: DispatchWorkItem?
    private var holdDeadline: DispatchWorkItem?
    private var releaseDeadline: DispatchWorkItem?
    private var releaseGeneration: UInt64 = 0
    private var holdMonitor: DispatchSourceTimer?
    private var deadlineGeneration: UInt64 = 0

    /// Drop sequence history when the coordinator rejects/passes through a gesture.
    func discardTapToDragSequence() {
        GestureEventRecorder.shared.record("sequence.discarded",
            "contact=\(traceContactID) pending=\(pendingTap) pending_contact=\(pendingTapContactID) state=\(state)")
        deadlineGeneration &+= 1
        tapDeadline?.cancel()
        holdDeadline?.cancel()
        tapDeadline = nil
        holdDeadline = nil
        pendingTap = false
        isTapToDragContact = false
    }

    deinit {
        tapDeadline?.cancel()
        holdDeadline?.cancel()
        releaseDeadline?.cancel()
        holdMonitor?.cancel()
    }

    // MARK: - Public Interface

    /// Process new touch data from the multitouch device
    /// - Parameters:
    ///   - touches: Raw pointer to touch data array
    ///   - count: Number of touches in the array
    ///   - timestamp: Timestamp of the touch frame
    ///   - modifierFlags: Current modifier key flags (captured on main thread by caller)
    func processTouches(
        _ touches: UnsafeMutableRawPointer, count: Int, timestamp: Double,
        modifierFlags: CGEventFlags
    ) {
        let touchArray = unsafe touches.bindMemory(to: MTTouch.self, capacity: count)

        // Check modifier key requirement first (if enabled)
        if configuration.requireModifierKey {
            let requiredFlagPresent: Bool
            switch configuration.modifierKeyType {
            case .shift:
                requiredFlagPresent = modifierFlags.contains(.maskShift)
            case .control:
                requiredFlagPresent = modifierFlags.contains(.maskControl)
            case .option:
                requiredFlagPresent = modifierFlags.contains(.maskAlternate)
            case .command:
                requiredFlagPresent = modifierFlags.contains(.maskCommand)
            }

            if !requiredFlagPresent {
                // Required modifier not held - cancel any active gesture and return
                if state != .idle || pendingTap {
                    GestureEventRecorder.shared.record("contact.modifier_missing", "contact=\(traceContactID) state=\(state)")
                    handleGestureCancel()
                }
                return
            }
        }

        // Collect only valid touching fingers (state 3 = touching down, state 4 = active)
        // Skip state 5 (lifting), 6 (lingering), 7 (gone)
        // Apply palm rejection filters
        var validFingers: [MTPoint] = []

        for i in 0..<count {
            let touch = unsafe touchArray[i]
            if touch.state == 3 || touch.state == 4 {
                let position = touch.normalizedVector.position

                // Palm rejection: Exclusion zone filter
                // Skip touches in the bottom portion of trackpad (where palm rests)
                if configuration.exclusionZoneEnabled {
                    if position.y < configuration.exclusionZoneSize {
                        continue  // Skip this touch
                    }
                }

                // Palm rejection: Contact size filter
                // Skip touches that are too large (palms have larger contact area)
                if configuration.contactSizeFilterEnabled {
                    if touch.zTotal > configuration.maxContactSize {
                        continue  // Skip this touch - likely a palm
                    }
                }

                validFingers.append(position)
            }
        }

        let fingerCount = validFingers.count
        // Keep every candidate-tap frame, but only finger-count changes during
        // established drags. This captures brief dropouts without logging motion forever.
        if state == .possibleTap || fingerCount != lastTraceFingerCount {
            GestureEventRecorder.shared.record("touch.frame",
                "contact=\(traceContactID) frame_time=\(timestamp) raw=\(count) valid=\(fingerCount) "
                + "touch_states=\((0..<count).map { unsafe touchArray[$0].state }) "
                + "finger_ids=\((0..<count).map { unsafe touchArray[$0].fingerID }) "
                + "state=\(state) release_frames=\(stableFrameCount) pending=\(pendingTap) "
                + "pending_contact=\(pendingTapContactID) tap_to_drag_contact=\(isTapToDragContact)")
        }
        lastTraceFingerCount = fingerCount

        // ALWAYS cancel on 4+ fingers regardless of configuration
        // This ensures Mission Control and other system gestures always work
        if fingerCount >= 4 {
            GestureEventRecorder.shared.record("contact.four_finger_cancel", "contact=\(traceContactID) valid=\(fingerCount)")
            if state != .idle || pendingTap {
                handleGestureCancel()
            }
            // Enter cooldown to prevent restart when finger is briefly lifted
            isInCancellationCooldown = true
            return
        }

        // Clear cooldown when finger count drops to 0-2,
        // or when finger count is 3 and we're idle (so user can start a new gesture)
        if fingerCount <= 2 || (fingerCount == 3 && state == .idle) {
            isInCancellationCooldown = false
        }

        // Process gesture based on finger count
        // - 4+ fingers: cancelled above
        // - 3 fingers: always valid for starting/continuing gesture
        // - 2 fingers: valid for continuing drag if allowReliftDuringDrag is enabled
        // - 0-1 fingers: ends the gesture
        let canReliftDuringDrag =
            configuration.allowReliftDuringDrag
            && state == .dragging
            && fingerCount >= 2
        let isValidGesture =
            !isInCancellationCooldown
            && (fingerCount == 3 || canReliftDuringDrag)

        if isValidGesture {
            handleValidGesture(fingers: validFingers, timestamp: timestamp)
        } else if state != .idle {
            // Gesture no longer valid for current finger count
            // (needs 3 to start, or 2+ if allowReliftDuringDrag is on during drag)
            // Use stable frame count to prevent false ends during brief transitions
            if releaseTime == nil {
                releaseTime = timestamp
                GestureEventRecorder.shared.record("contact.release_candidate",
                    "contact=\(traceContactID) frame_time=\(timestamp) valid=\(fingerCount) state=\(state)")
            }
            // Do not turn a contact already lifting into a hold during release debounce.
            holdDeadline?.cancel()
            holdDeadline = nil
            stableFrameCount += 1
            if stableFrameCount == 1 && configuration.tapToDragEnabled {
                scheduleReleaseConfirmation(at: timestamp)
            }
            if stableFrameCount >= 2 {
                GestureEventRecorder.shared.record("contact.release_confirmed", "contact=\(traceContactID) via=two_frames")
                handleGestureEnd(timestamp: timestamp)
            }
        }

        frameCount += 1
    }

    /// Reset gesture recognition state
    func reset() {
        GestureEventRecorder.shared.record("recognizer.reset", "contact=\(traceContactID) state=\(state)")
        discardTapToDragSequence()
        resetContact()
    }

    private func resetContact() {
        releaseGeneration &+= 1
        releaseDeadline?.cancel()
        releaseDeadline = nil
        holdMonitor?.cancel()
        holdMonitor = nil
        holdDeadline?.cancel()
        holdDeadline = nil
        isTapToDragContact = false
        releaseTime = nil
        state = .idle
        lastFingerPositions = []
        gestureStartPosition = nil
        lastCentroid = nil
        gestureStartTime = 0
        frameCount = 0
        stableFrameCount = 0
        isInCancellationCooldown = false  // Clear cooldown on reset
    }

    // MARK: - Private Methods

    private func handleValidGesture(fingers: [MTPoint], timestamp: Double) {
        if stableFrameCount > 0 {
            GestureEventRecorder.shared.record("contact.release_aborted", "contact=\(traceContactID) frame_time=\(timestamp)")
        }
        releaseGeneration &+= 1
        releaseDeadline?.cancel()
        releaseDeadline = nil
        stableFrameCount = 0
        releaseTime = nil

        let centroid = calculateCentroid(fingers: fingers)

        // Filter large centroid jumps from finger add/remove (not fast movement)
        if let last = lastCentroid {
            let jump = centroid.distance(to: last)
            if jump > 0.15 {
                GestureEventRecorder.shared.record("motion.jump_filtered", "contact=\(traceContactID) displacement=\(jump)")
                lastCentroid = centroid
                lastFingerPositions = fingers
                return
            }
        }

        switch state {
        case .idle:
            traceContactID &+= 1
            traceMaximumMovement = 0
            // Claim the preceding tap before its delayed click can be emitted.
            if pendingTap {
                let interval = timestamp - pendingTapReleaseTime
                GestureEventRecorder.shared.record("sequence.next_contact",
                    "contact=\(traceContactID) pending_contact=\(pendingTapContactID) gap=\(interval) timeout=\(configuration.tapToDragTimeout)")
                if interval >= 0 && interval <= configuration.tapToDragTimeout {
                    isTapToDragContact = true
                    tapDeadline?.cancel()
                    tapDeadline = nil
                } else {
                    commitPendingTap()
                }
            }
            state = .possibleTap
            gestureStartTime = timestamp
            gestureStartPosition = centroid
            lastCentroid = centroid
            lastFingerPositions = fingers
            GestureEventRecorder.shared.record("contact.started",
                "contact=\(traceContactID) frame_time=\(timestamp) tap_to_drag_contact=\(isTapToDragContact)")
            delegate?.gestureRecognizerDidStart(self, at: centroid)
            if isTapToDragContact { scheduleHoldDeadline() }

        case .possibleTap:
            // Check if we should transition to drag
            guard let startPos = gestureStartPosition else { return }
            let movement = startPos.distance(to: centroid)
            traceMaximumMovement = max(traceMaximumMovement, movement)
            GestureEventRecorder.shared.record("tap.motion",
                "contact=\(traceContactID) elapsed=\(timestamp - gestureStartTime) displacement=\(movement) "
                + "max_displacement=\(traceMaximumMovement) threshold=\(configuration.moveThreshold)")
            let holdLimit = min(configuration.tapThreshold, configuration.maxTapHoldDuration)
            if movement > configuration.moveThreshold
                || (isTapToDragContact && timestamp - gestureStartTime >= holdLimit) {
                GestureEventRecorder.shared.record("drag.threshold_reached",
                    "contact=\(traceContactID) movement=\(movement > configuration.moveThreshold) elapsed=\(timestamp - gestureStartTime)")
                beginDragging()
                lastCentroid = centroid
            } else {
                lastCentroid = centroid
                if isTapToDragContact && holdDeadline == nil {
                    scheduleHoldDeadline(elapsed: timestamp - gestureStartTime)
                }
            }

        case .dragging:
            if let last = lastCentroid {
                let deltaX = centroid.x - last.x
                let deltaY = centroid.y - last.y

                // Filter jumps from finger changes
                let maxDelta: Float = 0.15
                if abs(deltaX) < maxDelta && abs(deltaY) < maxDelta {
                    if abs(deltaX) > 0.0001 || abs(deltaY) > 0.0001 {
                        let gestureData = GestureData(
                            centroid: centroid,
                            velocity: MTPoint(x: 0, y: 0),
                            pressure: 0,
                            fingerCount: fingers.count,
                            startPosition: gestureStartPosition,
                            lastPosition: last
                        )
                        delegate?.gestureRecognizerDidUpdateDragging(self, with: gestureData)
                    }
                }
            }
            lastCentroid = centroid

        case .waitingForRelease:
            break
        }

        lastFingerPositions = fingers
    }

    private func beginDragging() {
        GestureEventRecorder.shared.record("drag.recognized",
            "contact=\(traceContactID) mode=\(isTapToDragContact ? "tap_to_drag" : "direct") consumes_pending=\(pendingTap)")
        holdDeadline?.cancel()
        holdDeadline = nil
        if isTapToDragContact {
            pendingTap = false  // A hold/drag consumes the preceding click.
            tapDeadline?.cancel()
            tapDeadline = nil
        }
        state = .dragging
        delegate?.gestureRecognizerDidBeginDragging(self)
        if isTapToDragContact && configuration.requireModifierKey {
            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
            timer.setEventHandler { [weak self] in
                guard let self, self.state == .dragging else { return }
                if !self.requiredModifierIsHeld() { self.handleGestureCancel() }
            }
            holdMonitor = timer
            timer.resume()
        }
    }

    private func requiredModifierIsHeld() -> Bool {
        guard configuration.requireModifierKey else { return true }
        let flags = CGEventSource.flagsState(.hidSystemState)
        switch configuration.modifierKeyType {
        case .shift: return flags.contains(.maskShift)
        case .control: return flags.contains(.maskControl)
        case .option: return flags.contains(.maskAlternate)
        case .command: return flags.contains(.maskCommand)
        }
    }

    private func scheduleReleaseConfirmation(at timestamp: Double) {
        let generation = releaseGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.releaseGeneration == generation,
                  self.stableFrameCount > 0, self.state != .idle else { return }
            // Hardware need not send a second empty frame. Retain the release
            // debounce, but guarantee taps/holds finish when callbacks go quiet.
            GestureEventRecorder.shared.record("contact.release_confirmed", "contact=\(self.traceContactID) via=timer")
            self.handleGestureEnd(timestamp: timestamp + 0.02)
        }
        releaseDeadline = work
        timerQueue.asyncAfter(deadline: .now() + 0.02, execute: work)
    }

    private func scheduleHoldDeadline(elapsed: Double = 0) {
        let generation = deadlineGeneration
        let duration = min(configuration.tapThreshold, configuration.maxTapHoldDuration)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.deadlineGeneration == generation,
                  self.state == .possibleTap, self.isTapToDragContact,
                  self.stableFrameCount == 0 else { return }
            guard self.requiredModifierIsHeld() else {
                self.handleGestureCancel()
                return
            }
            GestureEventRecorder.shared.record("hold.deadline_fired", "contact=\(self.traceContactID)")
            self.beginDragging()
        }
        holdDeadline = work
        timerQueue.asyncAfter(deadline: .now() + max(0, duration - elapsed), execute: work)
    }

    private func commitPendingTap() {
        guard pendingTap else { return }
        GestureEventRecorder.shared.record("tap.pending_committed",
            "contact=\(traceContactID) pending_contact=\(pendingTapContactID) state=\(state)")
        pendingTap = false
        tapDeadline?.cancel()
        tapDeadline = nil
        delegate?.gestureRecognizerDidTap(self)
    }

    private func deferTap(releasedAt timestamp: Double, processedAt frameTime: Double) {
        pendingTap = true
        pendingTapContactID = traceContactID
        pendingTapReleaseTime = timestamp
        deadlineGeneration &+= 1
        let generation = deadlineGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.deadlineGeneration == generation,
                  self.state == .idle else { return }
            GestureEventRecorder.shared.record("tap.deadline_fired", "pending_contact=\(self.pendingTapContactID)")
            self.commitPendingTap()
        }
        tapDeadline = work
        // Frame timestamps need not share Dispatch's epoch. Only subtract frame
        // timestamps from each other, then schedule the remaining duration.
        let remaining = max(0, configuration.tapToDragTimeout - (frameTime - timestamp))
        GestureEventRecorder.shared.record("tap.deferred",
            "contact=\(traceContactID) released_at=\(timestamp) remaining=\(remaining) timeout=\(configuration.tapToDragTimeout)")
        timerQueue.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func handleGestureEnd(timestamp: Double) {
        // Preserve legacy release-debounce timing when the new feature is off.
        let endedAt = configuration.tapToDragEnabled ? (releaseTime ?? timestamp) : timestamp
        let elapsed = endedAt - gestureStartTime
        GestureEventRecorder.shared.record("contact.ended",
            "contact=\(traceContactID) state=\(state) elapsed=\(elapsed) max_displacement=\(traceMaximumMovement) "
            + "tap_limit=\(configuration.tapThreshold) tap_to_drag_contact=\(isTapToDragContact)")

        // A release frame can arrive before a queued hold deadline is serviced.
        // Classify that long second contact as a press/release, consuming the tap.
        if state == .possibleTap && isTapToDragContact
            && elapsed >= min(configuration.tapThreshold, configuration.maxTapHoldDuration) {
            beginDragging()
        }

        switch state {
        case .possibleTap:
            if isTapToDragContact { commitPendingTap() }
            if elapsed < configuration.tapThreshold && elapsed <= configuration.maxTapHoldDuration {
                // Eligibility is checked at recognition, before storing a delayed click.
                let accepted = delegate?.gestureRecognizerShouldAcceptTap(self) ?? true
                GestureEventRecorder.shared.record("tap.recognized", "contact=\(traceContactID) accepted=\(accepted)")
                resetContact()
                if accepted {
                    if configuration.tapToDragEnabled {
                        deferTap(releasedAt: endedAt, processedAt: timestamp)
                    } else {
                        GestureEventRecorder.shared.record("tap.immediate", "contact=\(traceContactID)")
                        delegate?.gestureRecognizerDidTap(self)
                    }
                }
                return
            } else {
                delegate?.gestureRecognizerDidCancel(self)
            }
        case .dragging:
            delegate?.gestureRecognizerDidEndDragging(self)
        default:
            break
        }

        resetContact()
    }

    /// Cancel gesture without completing it (e.g., when 4th finger detected)
    private func handleGestureCancel() {
        GestureEventRecorder.shared.record("contact.cancelled", "contact=\(traceContactID) state=\(state) pending=\(pendingTap)")
        switch state {
        case .possibleTap:
            // Cancel the possible tap - notify delegate so it can reset state
            delegate?.gestureRecognizerDidCancel(self)
        case .dragging:
            // Cancel the drag - don't complete it normally
            delegate?.gestureRecognizerDidCancelDragging(self)
        default:
            if pendingTap { delegate?.gestureRecognizerDidCancel(self) }
        }

        reset()
    }

    private func calculateCentroid(fingers: [MTPoint]) -> MTPoint {
        let sumX = fingers.reduce(0) { $0 + $1.x }
        let sumY = fingers.reduce(0) { $0 + $1.y }
        return MTPoint(x: sumX / Float(fingers.count), y: sumY / Float(fingers.count))
    }
}

// MARK: - Gesture Data

/// Data representing the current state of a gesture
struct GestureData: Sendable {
    let centroid: MTPoint
    let velocity: MTPoint
    let pressure: Float
    let fingerCount: Int
    let startPosition: MTPoint?
    let lastPosition: MTPoint

    /// Calculate frame-to-frame delta with sensitivity applied
    func frameDelta(from configuration: GestureConfiguration) -> (x: CGFloat, y: CGFloat) {
        let deltaX = CGFloat(centroid.x - lastPosition.x)
        let deltaY = CGFloat(centroid.y - lastPosition.y)

        // Filter jumps from finger changes
        if abs(deltaX) > 0.15 || abs(deltaY) > 0.15 {
            return (0, 0)
        }

        let sensitivity = CGFloat(configuration.effectiveSensitivity(for: velocity))
        return (deltaX * sensitivity, deltaY * sensitivity)
    }
}

// MARK: - Delegate Protocol

/// Protocol for receiving gesture recognition events
protocol GestureRecognizerDelegate: AnyObject {
    /// Called when a gesture starts (3 fingers detected)
    func gestureRecognizerDidStart(_ recognizer: GestureRecognizer, at position: MTPoint)

    /// Validate a recognized tap and capture its target before any click delay.
    func gestureRecognizerShouldAcceptTap(_ recognizer: GestureRecognizer) -> Bool

    /// Called when a tap click is committed (possibly after the sequence timeout)
    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer)

    /// Called when dragging begins
    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer)

    /// Called during drag with movement data
    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData)

    /// Called when dragging ends normally (user lifted fingers)
    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer)

    /// Called when gesture is cancelled from early state (e.g., possibleTap when 4th finger added)
    func gestureRecognizerDidCancel(_ recognizer: GestureRecognizer)

    /// Called when dragging is cancelled (e.g., 4th finger added for Mission Control)
    func gestureRecognizerDidCancelDragging(_ recognizer: GestureRecognizer)
}

// Existing delegates can accept taps without handling the delayed-click policy.
extension GestureRecognizerDelegate {
    func gestureRecognizerShouldAcceptTap(_ recognizer: GestureRecognizer) -> Bool { true }
}
