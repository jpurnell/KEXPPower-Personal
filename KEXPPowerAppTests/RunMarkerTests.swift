import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

/// How the previous run of the app ended, as far as the app can tell, so a bug report can say whether the last run was
/// cut short. It knows what it saw (active, in the background, quit) and no more: it does not claim a crash.
@Suite("RunMarker")
struct RunMarkerTests {
    private func makeMarker(in directory: URL? = nil) -> (RunMarker, URL) {
        let folder = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-\(UUID().uuidString)", isDirectory: true)
        return (RunMarker(fileURL: folder.appendingPathComponent("run-state")), folder)
    }

    @Test("The very first launch has no previous run")
    func firstLaunch() {
        let (marker, _) = makeMarker()
        #expect(marker.begin() == .firstLaunch)
    }

    @Test("A run that never left the foreground ended while active")
    func endedWhileActive() {
        let (first, folder) = makeMarker()
        _ = first.begin()
        #expect(makeMarker(in: folder).0.begin() == .endedWhileActive)
    }

    @Test("A run last seen in the background ended in the background")
    func endedInBackground() {
        let (first, folder) = makeMarker()
        _ = first.begin()
        first.markBackground()
        #expect(makeMarker(in: folder).0.begin() == .endedInBackground)
    }

    @Test("Coming back to the foreground makes a later end 'while active' again")
    func backAgain() {
        let (first, folder) = makeMarker()
        _ = first.begin()
        first.markBackground()
        first.markActive()
        #expect(makeMarker(in: folder).0.begin() == .endedWhileActive)
    }

    @Test("A run that quit says so")
    func quit() {
        let (first, folder) = makeMarker()
        _ = first.begin()
        first.markQuit()
        #expect(makeMarker(in: folder).0.begin() == .quit)
    }

    @Test("Beginning a run marks it active, so two launches in a row each see the one before")
    func chain() {
        let (first, folder) = makeMarker()
        #expect(first.begin() == .firstLaunch)
        #expect(makeMarker(in: folder).0.begin() == .endedWhileActive)
        #expect(makeMarker(in: folder).0.begin() == .endedWhileActive)
    }

    @Test("An unreadable or unknown state counts as a first launch, never a crash of the app")
    func garbage() throws {
        let (_, folder) = makeMarker()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("???".utf8).write(to: folder.appendingPathComponent("run-state"))
        #expect(makeMarker(in: folder).0.begin() == .firstLaunch)
    }

    @Test("A folder that cannot be written never crashes the app")
    func unwritable() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-folder-\(UUID().uuidString)")
        try Data("x".utf8).write(to: file)
        let marker = RunMarker(fileURL: file.appendingPathComponent("run-state"))
        #expect(marker.begin() == .firstLaunch)
        marker.markBackground()
        marker.markActive()
        marker.markQuit()
    }

    @Test("Each ending reads as a plain sentence for the log")
    func sentences() {
        #expect(PreviousRun.firstLaunch.sentence == "first launch")
        #expect(PreviousRun.endedWhileActive.sentence == "ended while the app was in use")
        #expect(PreviousRun.endedInBackground.sentence == "ended in the background")
        #expect(PreviousRun.quit.sentence == "quit")
    }
}
