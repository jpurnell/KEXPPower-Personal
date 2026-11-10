//
//  FieldEventCoalescer.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import os

/// Lets a repeated failure through once per window, so an outage that fails the same call dozens of times sends one report.
///
/// KEXP's API being down fails the live poll every few seconds. Without this each failure would be an event, queued on disk and
/// sent, which is no more informative than the first and fills the queue. Only events that name a repeated failure
/// (``FieldEvent/coalescingKey``) are held back; a launch or a rewind fallback always passes. The memory is this launch's
/// only: nothing is kept between launches.
final class FieldEventCoalescer: Sendable {
    private let window: TimeInterval
    private let now: @Sendable () -> Date
    private let lastAllowed = OSAllocatedUnfairLock<[String: Date]>(initialState: [:])

    /// - Parameters:
    ///   - window: How long a failure, once reported, is not reported again, in seconds.
    ///   - now: The time source; tests pass their own.
    init(window: TimeInterval = 600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.window = window
        self.now = now
    }

    /// Whether this event should be sent now. Asking counts: an event that is allowed starts its window.
    func allows(_ event: FieldEvent) -> Bool {
        guard let key = event.coalescingKey else { return true }
        let moment = now()
        return lastAllowed.withLock { seen in
            if let earlier = seen[key], moment.timeIntervalSince(earlier) < window { return false }
            seen[key] = moment
            return true
        }
    }
}
