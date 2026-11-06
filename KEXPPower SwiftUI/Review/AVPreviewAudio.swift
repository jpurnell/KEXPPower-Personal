//
//  AVPreviewAudio.swift
//  KEXPPowerExampleSwiftUI
//

import AVFoundation
import Foundation

/// Plays a preview with AVPlayer.
@MainActor
final class AVPreviewAudio: PreviewAudio {
    var onFinish: (@MainActor () -> Void)?

    private let player = AVPlayer()
    private let observer = EndObserver()

    func play(_ url: URL) {
        let item = AVPlayerItem(url: url)
        observer.watch(item) { [weak self] in self?.onFinish?() }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        observer.clear()
    }
}

/// Holds the end-of-item observer and removes it when the audio goes away.
private final class EndObserver {
    private var token: NSObjectProtocol?

    /// Calls `handler` on the main actor when the item plays to its end; the notification is delivered on the main queue.
    func watch(_ item: AVPlayerItem, _ handler: @escaping @MainActor () -> Void) {
        clear()
        token = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
    }

    func clear() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    deinit {
        clear()
    }
}
