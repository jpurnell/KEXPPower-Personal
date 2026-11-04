//
//  OverlayScrollers.swift
//  Spinner Mac
//

import AppKit
import SwiftUI

/// Makes the scroll views in the window use overlay scrollers: thin bars that appear while scrolling and take no room.
///
/// SwiftUI has no setting for this. With a mouse attached, or "Show scroll bars: Always", macOS otherwise reserves a
/// permanent gutter that pushes content out of line with the views above it.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollerProbe { ScrollerProbe() }

    func updateNSView(_ nsView: ScrollerProbe, context: Context) { nsView.apply() }

    /// A zero-size view that finds the window's scroll views and sets their scroller style.
    final class ScrollerProbe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // The system resets the style when the scroll-bar preference changes; set it again.
            // A selector-based observer is removed automatically when this view goes away.
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrollerPreferenceChanged),
                name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        }

        @objc private func scrollerPreferenceChanged() { apply() }

        /// Sets the style now and once more after SwiftUI has built the scroll view, which can be a moment later.
        func apply() {
            setOverlayStyle()
            DispatchQueue.main.async { [weak self] in self?.setOverlayStyle() }
        }

        private func setOverlayStyle() {
            guard let root = window?.contentView else { return }
            for scrollView in Self.scrollViews(in: root) where scrollView.scrollerStyle != .overlay {
                scrollView.scrollerStyle = .overlay
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            let own = (view as? NSScrollView).map { [$0] } ?? []
            return own + view.subviews.flatMap { scrollViews(in: $0) }
        }
    }
}
