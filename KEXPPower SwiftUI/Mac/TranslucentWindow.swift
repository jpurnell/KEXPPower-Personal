//
//  TranslucentWindow.swift
//  Spinner Mac
//

import AppKit
import SwiftUI

/// A background that lets the desktop show through the whole window, blurred behind the content.
///
/// A SwiftUI material only blends with the window's own backdrop, which is opaque. This also makes the window itself
/// non-opaque, hides its title bar so the content can run up under the traffic lights, and lets the window be dragged
/// by any part of its background. With Reduce Transparency on, macOS draws the blur as a solid colour.
struct TranslucentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowStylingEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    /// The blur view, which also styles the window it ends up in.
    private final class WindowStylingEffectView: NSVisualEffectView {
        /// Never take a click: the content above it, or the window background, should get it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
    }
}
