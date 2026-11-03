//
//  VolumeBar.swift
//  Spinner Watch
//

import SwiftUI

/// A slim vertical level meter for the right edge of the screen.
struct VolumeBar: View {
    /// The volume, 0...1.
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 110

    /// The level limited to 0...1; a non-finite level counts as silent.
    private var clamped: Float {
        guard level.isFinite else { return 0 }
        return min(max(level, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.3))
            Capsule()
                .fill(.white)
                .frame(height: height * CGFloat(clamped))
                // The system moves volume in coarse steps; easing between them reads as smoother.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        }
        .frame(width: 6, height: height)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(clamped.formatted(.percent.precision(.fractionLength(0))))
    }
}
