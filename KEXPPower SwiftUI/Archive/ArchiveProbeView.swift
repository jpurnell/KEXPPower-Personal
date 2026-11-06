//
//  ArchiveProbeView.swift
//  KEXPPowerExampleSwiftUI
//

#if os(iOS) && DEBUG
import AVFoundation
import StationKit
import StationKitAdapterKEXP
import SwiftUI

/// A debug-only panel that plays a real archived show through the app's one player, to find out before the Archive is
/// built whether the offset, seeking by airdate and the end of a file behave as the design assumes.
///
/// Every step is written to the persistent diagnostic log under "Probe", so the result can be read off the phone.
@MainActor
@Observable
final class ArchiveProbeModel {
    private let model: ResultRetriever
    private let catalog = KEXPArchiveCatalog()
    private let diagnostics = DiagnosticLog.app

    private(set) var show: ArchiveShow?
    private(set) var playback: ArchivePlayback?
    private(set) var tracks: [Track] = []
    private(set) var lines: [String] = []
    private(set) var readout = "Nothing playing"

    init(model: ResultRetriever) {
        self.model = model
    }

    /// Finds the newest show that has ended and still has audio kept, with its songs.
    func find() async {
        note("finding a recent show")
        do {
            let now = Date()
            let shows = try await catalog.shows(from: now.addingTimeInterval(-3 * 86_400), to: now)
            // A show is a few hours long: one that began four hours ago has ended, so its file is whole.
            let ended = shows.filter { $0.startTime < now.addingTimeInterval(-4 * 3_600) }
                .sorted { $0.startTime > $1.startTime }
            note("\(shows.count) shows in three days, \(ended.count) ended")
            // Prefer a show whose next file is known, so the boundary between shows can be tried; keep the first
            // show with audio as the fallback.
            var fallback: (ArchiveShow, ArchivePlayback)?
            for candidate in ended.prefix(8) {
                guard let found = try await catalog.playback(for: candidate) else {
                    note("no audio kept for \(candidate.programName) \(candidate.startTime)")
                    continue
                }
                fallback = fallback ?? (candidate, found)
                if found.nextURL != nil {
                    await choose(candidate, found)
                    return
                }
            }
            if let (candidate, found) = fallback {
                note("no show with a next file among the newest; using the newest with audio")
                await choose(candidate, found)
                return
            }
            note("no ended show with audio found")
        } catch {
            note("find failed: \(error.localizedDescription)")
        }
    }

    private func choose(_ candidate: ArchiveShow, _ found: ArchivePlayback) async {
        show = candidate
        playback = found
        do {
            tracks = try await catalog.tracks(of: candidate)
        } catch {
            note("songs failed: \(error.localizedDescription)")
        }
        describe(candidate, found)
    }

    /// When a song aired and where it is in the file, so the list's order can be seen.
    func caption(for track: Track) -> String {
        guard let show, let playback, let airDate = track.airDate else { return track.displayArtist }
        let position = ArchiveTiming.songPosition(airedAt: airDate, in: show, playback: playback)
        return "\(track.displayArtist) · aired \(ArchiveTiming.clock(airDate)) · \(ArchiveTiming.positionText(position)) in file"
    }

    /// Plays the show's file from where the show begins.
    func playFromStart() async {
        guard let playback else { return }
        await model.startIfNeeded()
        note("play from show start, offset \(Int(playback.offset)) s")
        await model.playerController.playArchive(url: playback.url, at: playback.offset)
    }

    /// Plays from where a song aired, by the airdate arithmetic.
    func play(_ track: Track) async {
        guard let show, let playback, let airDate = track.airDate else { return }
        await model.startIfNeeded()
        let position = ArchiveTiming.songPosition(airedAt: airDate, in: show, playback: playback)
        note("jump to \"\(track.title)\" at \(Int(position)) s")
        if model.playerController.isPlayingArchive {
            await model.playerController.seekArchive(to: position)
        } else {
            await model.playerController.playArchive(url: playback.url, at: position)
        }
    }

    /// Seeks to thirty seconds before the end of the file, to see what happens when it runs out.
    func seekNearEnd() async {
        guard let item = model.playerController.player?.currentItem, item.duration.isNumeric else {
            note("no duration yet; start the show first")
            return
        }
        let target = item.duration.seconds - 30
        note("seek to \(Int(target)) s, 30 s before the end")
        await model.playerController.seekArchive(to: target)
    }

    /// Plays the file the station names as the next show's, from its start.
    func playNextFile() async {
        guard let next = playback?.nextURL else {
            note("no next file")
            return
        }
        note("play the next file from 0: \(next.lastPathComponent)")
        await model.playerController.playArchive(url: next, at: 0)
    }

    func goLive() {
        note("return to live")
        model.playerController.returnToLive()
    }

    /// Refreshes the position, state and any error from the player; called every second while the panel is up.
    func refreshReadout() {
        guard let player = model.playerController.player, let item = player.currentItem else {
            readout = "No player"
            return
        }
        let duration = item.duration.isNumeric ? Int(item.duration.seconds) : -1
        let status = ["paused", "waiting", "playing"][min(player.timeControlStatus.rawValue, 2)]
        let failure = item.error.map { " ERROR \($0.localizedDescription)" } ?? ""
        let kind = model.playerController.isPlayingArchive ? "archive" : "live"
        readout = "\(kind) \(status) at \(Int(player.currentTime().seconds)) s of \(duration) s, item status \(item.status.rawValue)\(failure)"
    }

    private func describe(_ show: ArchiveShow, _ playback: ArchivePlayback) {
        let gap = ArchiveTiming.offsetDisagreement(show: show, playback: playback).map { "\(Int($0)) s" } ?? "n/a"
        note("show: \(show.programName), began \(show.startTime)")
        note("file: \(playback.url.lastPathComponent)")
        note("offset \(Int(playback.offset)) s; disagrees with the file name by \(gap)")
        note("next file: \(playback.nextURL?.lastPathComponent ?? "none"); \(tracks.count) songs")
    }

    private func note(_ text: String) {
        lines.append(text)
        diagnostics.record("Probe", text)
    }
}

/// The Archive tab in debug builds: the placeholder's message, and the probe beneath it.
struct ArchiveProbeView: View {
    @State private var probe: ArchiveProbeModel

    init(model: ResultRetriever) {
        _probe = State(initialValue: ArchiveProbeModel(model: model))
    }

    var body: some View {
        List {
            Section {
                Text(AppSection.archive.comingSoonMessage ?? "")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Archive (coming soon)")
            }
            Section("Probe (debug builds only)") {
                Button("Find a recent show") { Task { await probe.find() } }
                Button("Play from the show's start") { Task { await probe.playFromStart() } }
                    .disabled(probe.playback == nil)
                Button("Seek to 30 s before the end") { Task { await probe.seekNearEnd() } }
                Button("Play the next file") { Task { await probe.playNextFile() } }
                    .disabled(probe.playback?.nextURL == nil)
                Button("Back to live") { probe.goLive() }
                Text(probe.readout).font(.caption.monospaced())
            }
            if !probe.tracks.isEmpty {
                Section("Songs: tap to jump") {
                    ForEach(probe.tracks) { track in
                        Button {
                            Task { await probe.play(track) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                Text(probe.caption(for: track)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Log") {
                ForEach(Array(probe.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2.monospaced())
                }
            }
        }
        .task {
            while !Task.isCancelled {
                probe.refreshReadout()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
#endif
