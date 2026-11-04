//
//  NowPlayingWidgetViews.swift
//  KEXPPowerExampleSwiftUI
//

import AppIntents
import SwiftUI

/// The play/pause control on the larger sizes. It runs ``PlayPauseIntent``; the icon follows the playing flag the
/// app keeps current.
struct WidgetPlayPauseButton: View {
    let isPlaying: Bool
    var size: CGFloat = 36

    var body: some View {
        Button(intent: PlayPauseIntent()) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .resizable()
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// Small: the artwork, with the title and artist over its lower edge.
struct SmallNowPlayingView: View {
    let content: NowPlayingWidgetContent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WidgetArtwork(data: content.artwork)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.snapshot.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text(content.snapshot.artist)
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(content.snapshot.title) by \(content.snapshot.artist)")
    }
}

/// Medium: the now-playing row: art, details, and play/pause.
struct MediumNowPlayingView: View {
    let content: NowPlayingWidgetContent

    var body: some View {
        HStack(spacing: 12) {
            WidgetArtwork(data: content.artwork)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(content.timeLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(content.snapshot.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(content.snapshot.artist)
                    .font(.subheadline)
                    .lineLimit(1)
                if !content.snapshot.album.isEmpty {
                    Text(content.snapshot.album)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !content.releaseLine.isEmpty {
                    Text(content.releaseLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            WidgetPlayPauseButton(isPlaying: content.isPlaying)
        }
    }
}

/// Large: the expanded view: show, art, details, links, the start of the DJ's comment, and play/pause.
struct LargeNowPlayingView: View {
    let content: NowPlayingWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let show = content.snapshot.showName {
                Text([show, content.snapshot.host].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .top, spacing: 12) {
                WidgetArtwork(data: content.artwork)
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.snapshot.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                    Text(content.snapshot.artist)
                        .font(.subheadline)
                        .lineLimit(2)
                    if !content.snapshot.album.isEmpty {
                        Text(content.snapshot.album)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if !content.releaseLine.isEmpty {
                        Text(content.releaseLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 14) {
                        if let url = content.snapshot.spotifyURL { Link("Spotify", destination: url) }
                        if let url = content.snapshot.bandcampURL { Link("Bandcamp", destination: url) }
                    }
                    .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            }
            if let comment = content.snapshot.commentExcerpt {
                Text(comment)
                    .font(.caption)
                    .lineLimit(6)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                Text(content.timeLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                WidgetPlayPauseButton(isPlaying: content.isPlaying, size: 44)
            }
        }
    }
}
