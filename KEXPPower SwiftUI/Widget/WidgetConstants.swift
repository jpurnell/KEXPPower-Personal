//
//  WidgetConstants.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// Names the app and its widget agree on.
enum WidgetConstants {
    /// The App Group the app and the widget share.
    ///
    /// The two platforms have different rules. iOS and visionOS accept only `group.`-prefixed identifiers, which are
    /// registered in the Developer portal. On the Mac a group that starts with the Team ID works with no portal
    /// registration or explicit profile, whereas a `group.` identifier is refused without one, so the widget would
    /// find nothing to read. (They never share data across platforms, so they need not be the same.)
    static var groupID: String {
        #if os(macOS)
        "BNDA9Y6YV9.com.JPEnterprises.Spinner"
        #else
        "group.com.JPEnterprises.Spinner"
        #endif
    }
    /// The widget's identifier, used to ask WidgetKit to reload it.
    static let kind = "NowPlayingWidget"
    /// The station's logo, shown when a play has no artwork of its own.
    static let logoURL = URL(string: "https://kexp.org/static/assets/img/kexp_logo.jpg")
    /// The hosts artwork may be fetched from.
    static let artworkDomains = ["kexp.org", "archive.org"]
}
