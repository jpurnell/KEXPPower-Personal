//
//  FieldIdentity.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import SwiftDiagnosticsClient

/// Which build this is, in the terms the diagnostics hub wants: the version and build, the platform, the operating system and
/// a coarse device class. A model identifier is more than the hub needs and is not sent.
enum FieldIdentity {
    /// The identity from an info dictionary and the facts about where the app is running.
    /// - Parameters:
    ///   - info: The bundle's info dictionary.
    ///   - platform: The platform the build runs on.
    ///   - osVersion: The operating system version, such as `27.2`.
    ///   - deviceClass: A coarse class: `iPhone`, `iPad`, `Mac` or `AppleTV`.
    static func make(info: [String: Any], platform: Platform, osVersion: String, deviceClass: String) -> AppIdentity {
        AppIdentity(
            app: "spinner", platform: platform, appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown", osVersion: osVersion, deviceClass: deviceClass)
    }

    /// The identity of the running app.
    static func current(bundle: Bundle = .main) -> AppIdentity {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let deviceClass = currentDeviceClass()
        return make(
            info: bundle.infoDictionary ?? [:], platform: currentPlatform(deviceClass: deviceClass),
            osVersion: "\(version.majorVersion).\(version.minorVersion)", deviceClass: deviceClass)
    }

    /// `iPhone`, `iPad`, `Mac` or `AppleTV`.
    static func currentDeviceClass() -> String {
        #if os(macOS)
        return "Mac"
        #elseif os(tvOS)
        return "AppleTV"
        #else
        return LaunchHeader.deviceModel().hasPrefix("iPad") ? "iPad" : "iPhone"
        #endif
    }

    private static func currentPlatform(deviceClass: String) -> Platform {
        #if os(macOS)
        return .macos
        #elseif os(tvOS)
        return .tvos
        #else
        return deviceClass == "iPad" ? .ipados : .ios
        #endif
    }
}
