//
//  LaunchHeader.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation

/// The first line of each launch in the diagnostic log: which build this is, what it is running on, and how the last run
/// ended, so a log read later says what produced it.
enum LaunchHeader {
    /// The header line.
    /// - Parameters:
    ///   - version: The marketing version.
    ///   - build: The build number.
    ///   - system: The operating system and its version.
    ///   - device: The hardware model identifier.
    ///   - previous: How the run before this one ended.
    static func line(version: String, build: String, system: String, device: String, previous: PreviousRun) -> String {
        "launched \(version) (\(build)) on \(system), \(device); previous run: \(previous.sentence)"
    }

    /// The header for this running app.
    static func current(previous: PreviousRun) -> String {
        let info = Bundle.main.infoDictionary
        return line(
            version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown",
            system: systemName(),
            device: deviceModel(),
            previous: previous)
    }

    /// The operating system and its version, such as `iOS 27.3`.
    static func systemName() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let name = "iOS"
        #elseif os(macOS)
        let name = "macOS"
        #elseif os(tvOS)
        let name = "tvOS"
        #elseif os(watchOS)
        let name = "watchOS"
        #elseif os(visionOS)
        let name = "visionOS"
        #else
        let name = "OS"
        #endif
        return "\(name) \(version.majorVersion).\(version.minorVersion)"
    }

    /// The hardware model identifier, such as `iPhone16,1` or `arm64` on a Mac.
    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        // `machine` is a fixed-size C character array, which Swift imports as a tuple: read it by reflection, so no
        // pointer to it is ever taken.
        let bytes = Mirror(reflecting: info.machine).children.compactMap { child in
            (child.value as? Int8).map { UInt8(bitPattern: $0) }
        }
        let model = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return model.isEmpty ? "unknown" : model
    }
}
