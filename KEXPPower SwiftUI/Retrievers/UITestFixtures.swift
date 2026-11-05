//
//  UITestFixtures.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import KEXPPower

/// Fixed songs for the UI tests, so they do not depend on what KEXP is playing or on the network.
///
/// The UI test launches the app with `-uitest-fixtures`; a normal launch never sees them.
enum UITestFixtures {
    /// The launch argument that turns the fixtures on.
    static let launchArgument = "-uitest-fixtures"

    /// How many songs the fixtures hold: one on the air and the rest previously played.
    static let playCount = 6

    /// Whether the app was launched for a UI test.
    /// - Parameter arguments: The launch arguments; the process's own by default.
    static func isActive(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    /// The fixed songs, newest first, each with its own id.
    static var plays: [Play] {
        (0..<playCount).map { Play.fixture(id: 3_000_448 - $0) }
    }
}
