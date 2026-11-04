//
//  WidgetConstants.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// Names the app and its widget agree on.
enum WidgetConstants {
    /// The App Group the app and the widget share.
    static let groupID = "group.com.JPEnterprises.Spinner"
    /// The widget's identifier, used to ask WidgetKit to reload it.
    static let kind = "NowPlayingWidget"
    /// The station's logo, shown when a play has no artwork of its own.
    static let logoURL = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg")
    /// The hosts artwork may be fetched from.
    static let artworkDomains = ["kexp.org", "archive.org"]
}
