//
//  APIFailure.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import KEXPPower
import StationKitAdapterKEXP

/// Which of KEXP's services a failed call was made to.
enum APIEndpoint: String, Sendable, CaseIterable {
    /// The live playlist and show poll.
    case live
    /// The archive of past shows.
    case archive
}

/// How a call to KEXP's API failed, in terms that hold no message and nothing a person or a station wrote.
struct APIFailure: Sendable, Equatable {
    /// The kind of failure.
    enum Outcome: String, Sendable, CaseIterable {
        /// The server answered with an HTTP error.
        case badStatus
        /// The server answered with something that was not what was asked for, such as an error page where data was expected.
        case badResponse
        /// There was no connection, or it was lost.
        case offline
        /// The server took too long.
        case timeout
        /// Anything else.
        case other
    }

    /// What happened.
    let outcome: Outcome
    /// The HTTP status, when the app knows it and it is a client or server error (400 to 599).
    let status: Int?

    /// What an error means for a report, or `nil` when it is not a failure at all (a cancelled request).
    ///
    /// Both services report an HTTP error as ``Outcome/badStatus`` with its status: the archive always did, and the live poll
    /// does since KEXPPowerKit 4.2 (before, an error page failed to decode and arrived here as ``Outcome/badResponse`` with no
    /// status; that outcome remains for a body that is not what was asked for).
    static func classify(_ error: any Error) -> APIFailure? {
        if error is CancellationError { return nil }
        if let live = error as? KEXPNetworkError {
            guard case .badStatus(let code) = live else { return APIFailure(outcome: .other, status: nil) }
            return APIFailure(outcome: .badStatus, status: (400...599).contains(code) ? code : nil)
        }
        if let archive = error as? KEXPArchiveError {
            guard case .badStatus(let code) = archive else { return APIFailure(outcome: .other, status: nil) }
            return APIFailure(outcome: .badStatus, status: (400...599).contains(code) ? code : nil)
        }
        if error is DecodingError { return APIFailure(outcome: .badResponse, status: nil) }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return nil
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return APIFailure(outcome: .offline, status: nil)
            case .timedOut: return APIFailure(outcome: .timeout, status: nil)
            default: return APIFailure(outcome: .other, status: nil)
            }
        }
        return APIFailure(outcome: .other, status: nil)
    }
}
