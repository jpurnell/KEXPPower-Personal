//
//  LiveStart.swift
//  KEXPPowerExampleSwiftUI
//

import AVFoundation
import Foundation
import Network
import os

/// How long a live start took, in the coarse steps a report may carry: enough to tell fast from slow, not to say exactly when.
enum StartDuration: String, Sendable, CaseIterable {
    case under2, from2to5, from5to15, from15to40, over40

    /// - Parameter seconds: How long it took; a negative or non-numeric value reads as the fastest step.
    init(seconds: TimeInterval) {
        switch seconds {
        case 40...: self = .over40
        case 15...: self = .from15to40
        case 5...: self = .from5to15
        case 2...: self = .from2to5
        default: self = .under2
        }
    }
}

/// How a live start ended.
enum LiveStartOutcome: String, Sendable, CaseIterable {
    /// Audio began without help.
    case started
    /// The player's item was rebuilt, and audio began.
    case rebuilt
    /// The recording was given up on and the stream played directly, and audio began.
    case fellBackDirect
    /// Audio began only when the network came back.
    case recoveredOnNetwork
    /// No audio came, and the app stopped waiting.
    case gaveUp
}

/// How the phone was connected when live was asked for.
enum NetworkKind: String, Sendable, CaseIterable, Codable {
    case none, wifi, cellular, wired, other

    init(isSatisfied: Bool, usesWiFi: Bool, usesCellular: Bool, usesWired: Bool) {
        guard isSatisfied else { self = .none; return }
        if usesWiFi { self = .wifi } else if usesCellular { self = .cellular } else if usesWired { self = .wired } else { self = .other }
    }
}

/// Where the sound was going: a few kinds, never the name of a device.
enum OutputRoute: String, Sendable, CaseIterable, Codable {
    case carPlay, airPlay, bluetooth, headphones, speaker, other

    /// - Parameter portType: An audio session output port type's raw value; anything not listed, including a name someone gave a device, is `other`.
    init(portType: String?) {
        switch portType {
        case "CarAudio": self = .carPlay
        case "AirPlay": self = .airPlay
        case "BluetoothA2DPOutput", "BluetoothHFP", "BluetoothLE": self = .bluetooth
        case "Headphones", "HeadsetMic", "USBAudio": self = .headphones
        case "Speaker", "Receiver": self = .speaker
        default: self = .other
        }
    }
}

/// One live start, as a report carries it.
struct LiveStart: Sendable, Equatable {
    let outcome: LiveStartOutcome
    let took: StartDuration
    let network: NetworkKind
    let route: OutputRoute
}

/// What the local server and the player's item say about a start that has no audio yet, counted from when the item was made.
///
/// A count is `nil` when there is nothing to ask: the direct stream has no local server.
struct LiveStartEvidence: Sendable, Equatable {
    /// How many times the player asked the local server for the playlist.
    var playlistFetches: Int?
    /// How many segments it has been given.
    var segmentFetches: Int?
    /// Whether the item has failed.
    var itemFailed: Bool

    static let unavailable = LiveStartEvidence(playlistFetches: nil, segmentFetches: nil, itemFailed: false)
}

/// Why the player's item was rebuilt.
enum RebuildReason: String, Sendable, Equatable, CaseIterable {
    /// The player never asked the local server for the playlist.
    case playerNeverConnected = "player never connected"
    /// It fetched the playlist and no segment.
    case noSegmentsFetched = "no segment fetched"
    /// The item failed.
    case itemFailed = "item failed"
    /// There was nothing to ask, so the clock decided.
    case noEvidence = "no evidence available"
}

/// Decides what to do about a live start that is slow, from the seconds elapsed, whether audio is moving, and what the local server and
/// the item say.
///
/// Each step is taken once. Eight seconds in, an item that has not been given the playlist or any segment is rebuilt (one that has been
/// given segments is not: more of the same would not help); a failed item is rebuilt at once. At eighteen seconds the recording is dropped
/// for the stream itself, and at forty-five the app stops waiting.
struct LiveStartWatch: Sendable {
    /// What the caller should do now.
    enum Step: Sendable, Equatable {
        case waiting, started, rebuild(RebuildReason), fallBackDirect, giveUp
    }

    static let rebuildAfter: TimeInterval = 8
    static let fallBackAfter: TimeInterval = 18
    static let giveUpAfter: TimeInterval = 45

    private enum Stage: Int { case none, rebuilt, fellBack, gaveUp }
    private var stage = Stage.none
    private var audioHeard = false

    /// - Parameters:
    ///   - elapsed: Seconds since live was asked for.
    ///   - audioMoving: Whether the player's clock is moving.
    ///   - evidence: What the local server and the item say; none by default.
    mutating func observe(elapsed: TimeInterval, audioMoving: Bool, evidence: LiveStartEvidence = .unavailable) -> Step {
        if audioMoving {
            audioHeard = true
            return .started
        }
        if elapsed >= Self.giveUpAfter, stage != .gaveUp {
            stage = .gaveUp
            return .giveUp
        }
        if elapsed >= Self.fallBackAfter, stage.rawValue < Stage.fellBack.rawValue {
            stage = .fellBack
            return .fallBackDirect
        }
        guard stage == .none else { return .waiting }
        if evidence.itemFailed {
            stage = .rebuilt
            return .rebuild(.itemFailed)
        }
        guard elapsed >= Self.rebuildAfter else { return .waiting }
        guard let playlists = evidence.playlistFetches, let segments = evidence.segmentFetches else {
            stage = .rebuilt
            return .rebuild(.noEvidence)
        }
        if playlists == 0 {
            stage = .rebuilt
            return .rebuild(.playerNeverConnected)
        }
        if segments == 0 {
            stage = .rebuilt
            return .rebuild(.noSegmentsFetched)
        }
        return .waiting
    }

    /// How the start ended, given how far recovery went and whether audio came.
    var outcome: LiveStartOutcome {
        guard audioHeard || stage != .gaveUp else { return .gaveUp }
        switch stage {
        case .none: return .started
        case .rebuilt: return .rebuilt
        case .fellBack: return .fellBackDirect
        case .gaveUp: return .gaveUp
        }
    }
}

extension OutputRoute {
    /// Where the sound is going now, as the audio session reports it; `other` where there is no audio session to ask.
    static func current() -> OutputRoute {
        #if os(macOS)
        return .other
        #else
        OutputRoute(portType: AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue)
        #endif
    }
}

/// Decides when a start that gave up should be tried again: when the network that was missing comes back.
struct NetworkRecovery: Sendable {
    private var wasUnavailable = true

    /// - Parameters:
    ///   - network: The latest report of how the phone is connected.
    ///   - waiting: Whether a start gave up and nothing has played since.
    /// - Returns: `true` once, as a usable network follows a missing one while a start is waiting.
    mutating func shouldRetry(network: NetworkKind, waiting: Bool) -> Bool {
        let was = wasUnavailable
        wasUnavailable = network == .none
        return waiting && was && network != .none
    }
}

/// Watches how the phone is connected and says so to whoever asks or listens.
final class NetworkPathObserver: Sendable {
    static let shared = NetworkPathObserver()

    private struct State {
        var kind = NetworkKind.other
        var continuations: [UUID: AsyncStream<NetworkKind>.Continuation] = [:]
    }

    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {
        monitor.pathUpdateHandler = { [state] path in
            let kind = NetworkKind(
                isSatisfied: path.status == .satisfied, usesWiFi: path.usesInterfaceType(.wifi),
                usesCellular: path.usesInterfaceType(.cellular), usesWired: path.usesInterfaceType(.wiredEthernet))
            let listeners = state.withLock { current -> [AsyncStream<NetworkKind>.Continuation] in
                current.kind = kind
                return Array(current.continuations.values)
            }
            for listener in listeners { listener.yield(kind) }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkPathObserver"))
    }

    /// How the phone is connected at the moment.
    var kind: NetworkKind { state.withLock { $0.kind } }

    /// Every change in how the phone is connected, starting with how it is now.
    func updates() -> AsyncStream<NetworkKind> {
        AsyncStream { continuation in
            let id = UUID()
            let current = state.withLock { state -> NetworkKind in
                state.continuations[id] = continuation
                return state.kind
            }
            continuation.yield(current)
            continuation.onTermination = { [state] _ in
                state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }
}
