//
//  SpinnerWidgetBundle.swift
//  Spinner Widget
//

import SwiftUI
import WidgetKit

@main
struct SpinnerWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        #if !os(visionOS)
        if #available(iOS 18.0, macOS 26.0, *) {
            NowPlayingControl()
        }
        #endif
    }
}
