//
//  WatchWidgetConstants.swift
//  Spinner Watch
//

/// Names the watch app and its widget agree on.
enum WatchWidgetConstants {
    /// The App Group the watch app and its widget share. The watch uses the same group as the phone; the two
    /// devices never share data through it, since each device has its own copy of the group's storage.
    static let groupID = "group.com.JPEnterprises.Spinner"
    /// The watch widget's identifier, used to ask WidgetKit to reload it.
    static let kind = "WatchNowPlayingWidget"
}
