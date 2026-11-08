//
//  LocalHLSServer.swift
//  KEXPPowerExampleSwiftUI
//

import Foundation
import Network
import os

/// Reading requests and writing responses for the smallest HTTP the player needs: GET, one answer, then close.
enum HTTPMessage {
    private static let headerEnd = Data("\r\n\r\n".utf8)

    static let badRequest = Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)

    /// Whether the request's headers have all arrived.
    static func isComplete(_ request: Data) -> Bool {
        request.range(of: headerEnd) != nil
    }

    /// The path a GET request asks for, without any query; `nil` for anything else.
    static func path(ofRequest request: Data) -> String? {
        guard let text = String(data: request, encoding: .utf8),
            let line = text.split(whereSeparator: \.isNewline).first
        else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    /// A response as it goes on the wire.
    static func bytes(for response: HLSResponse) -> Data {
        let reason = response.status == 200 ? "OK" : "Not Found"
        let head = [
            "HTTP/1.1 \(response.status) \(reason)",
            "Content-Type: \(response.contentType)",
            "Content-Length: \(response.body.count)",
            "Cache-Control: no-cache",
            "Connection: close",
            "", "",
        ].joined(separator: "\r\n")
        return Data(head.utf8) + response.body
    }
}

/// Serves a `LiveRelay` to the player over HTTP on this device's loopback address, so `AVPlayer` can treat the last few
/// minutes of the live stream as an HLS stream with a rewind window.
///
/// It listens on `127.0.0.1` only, on a port the system picks, and serves the playlist and segments the relay holds and
/// nothing else.
final class LocalHLSServer: Sendable {
    private struct State {
        var listener: NWListener?
    }

    private enum StartError: Error { case noPort, cancelled }

    private static let maximumRequest = 16 * 1_024
    private let relay: LiveRelay
    private let queue = DispatchQueue(label: "LocalHLSServer")
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(relay: LiveRelay) {
        self.relay = relay
    }

    /// Starts listening.
    /// - Returns: The address of the playlist.
    func start() async throws -> URL {
        stop()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [relay, queue] connection in
            Self.serve(connection, relay: relay, queue: queue)
        }
        state.withLock { $0.listener = listener }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let pending = OSAllocatedUnfairLock<CheckedContinuation<NWEndpoint.Port, any Error>?>(
                initialState: continuation)
            listener.stateUpdateHandler = { newState in
                let outcome: Result<NWEndpoint.Port, any Error>?
                switch newState {
                case .ready: outcome = listener.port.map { .success($0) } ?? .failure(StartError.noPort)
                case .failed(let error): outcome = .failure(error)
                case .cancelled: outcome = .failure(StartError.cancelled)
                default: outcome = nil
                }
                guard let outcome, let waiting = pending.withLock({ current in current.take() }) else { return }
                waiting.resume(with: outcome)
            }
            listener.start(queue: queue)
        }
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/live.m3u8") else { throw StartError.noPort }
        return url
    }

    /// Stops listening.
    func stop() {
        let listener = state.withLock { state in state.listener.take() }
        listener?.cancel()
    }

    // MARK: Connections

    private static func serve(_ connection: NWConnection, relay: LiveRelay, queue: DispatchQueue) {
        connection.start(queue: queue)
        receive(on: connection, collected: Data(), relay: relay)
    }

    private static func receive(on connection: NWConnection, collected: Data, relay: LiveRelay) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { data, _, isComplete, error in
            let request = collected + (data ?? Data())
            if error != nil {
                connection.cancel()
            } else if HTTPMessage.isComplete(request) {
                respond(to: request, on: connection, relay: relay)
            } else if isComplete || request.count >= maximumRequest {
                connection.send(content: HTTPMessage.badRequest, completion: .contentProcessed { _ in connection.cancel() })
            } else {
                receive(on: connection, collected: request, relay: relay)
            }
        }
    }

    private static func respond(to request: Data, on connection: NWConnection, relay: LiveRelay) {
        guard let path = HTTPMessage.path(ofRequest: request) else {
            connection.send(content: HTTPMessage.badRequest, completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        Task {
            let response = await relay.response(forPath: path)
            connection.send(
                content: HTTPMessage.bytes(for: response), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
