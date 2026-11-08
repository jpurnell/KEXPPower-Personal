import Foundation
import Testing
@testable import KEXPPowerExampleSwiftUI

@Suite("ListeningSettings")
struct ListeningSettingsTests {
    /// A throwaway store, so a test never reads or writes the app's own settings.
    private func defaults(_ name: String) -> UserDefaults {
        let suite = "ListeningSettingsTests.\(name)"
        let store = UserDefaults(suiteName: suite) ?? .standard
        store.removePersistentDomain(forName: suite)
        return store
    }

    @Test("With nothing stored the settings are the defaults: standard quality and a ten-minute window")
    func defaultsWhenEmpty() {
        let settings = ListeningSettings.current(defaults: defaults("empty"))
        #expect(settings == ListeningSettings(quality: .standard, window: .tenMinutes))
    }

    @Test("Stored values are read through the same keys Settings writes")
    func readsStoredValues() {
        let store = defaults("stored")
        store.set(StreamQuality.dataSaver.rawValue, forKey: StreamQuality.storageKey)
        store.set(RewindWindow.fiveMinutes.rawValue, forKey: RewindWindow.storageKey)
        #expect(ListeningSettings.current(defaults: store) == ListeningSettings(quality: .dataSaver, window: .fiveMinutes))
    }

    @Test("A value that is not one of the choices reads as the default")
    func unknownValues() {
        let store = defaults("unknown")
        store.set("320", forKey: StreamQuality.storageKey)
        store.set("", forKey: RewindWindow.storageKey)
        #expect(ListeningSettings.current(defaults: store) == ListeningSettings(quality: .standard, window: .tenMinutes))
    }

    @Test("The live stream is rebuilt when the window or the quality changes, and not otherwise")
    func restartRule() {
        let base = ListeningSettings(quality: .standard, window: .tenMinutes)
        #expect(!ListeningSettings.restartsLive(from: base, to: base))
        #expect(ListeningSettings.restartsLive(from: base, to: ListeningSettings(quality: .standard, window: .fiveMinutes)))
        #expect(ListeningSettings.restartsLive(from: base, to: ListeningSettings(quality: .dataSaver, window: .tenMinutes)))
        #expect(ListeningSettings.restartsLive(from: base, to: ListeningSettings(quality: .dataSaver, window: .off)))
    }

    @Test("The window's size on disk is its seconds times the stream's bytes a second")
    func approximateBytes() {
        // 160 kbps is 20,000 bytes a second; 64 kbps is 8,000.
        #expect(ListeningSettings.approximateBytes(window: .tenMinutes, quality: .standard) == 12_000_000)
        #expect(ListeningSettings.approximateBytes(window: .fiveMinutes, quality: .standard) == 6_000_000)
        #expect(ListeningSettings.approximateBytes(window: .fiveMinutes, quality: .dataSaver) == 2_400_000)
        #expect(ListeningSettings.approximateBytes(window: .tenMinutes, quality: .dataSaver) == 4_800_000)
    }

    @Test("With the window off nothing is kept")
    func offKeepsNothing() {
        #expect(ListeningSettings.approximateBytes(window: .off, quality: .standard) == 0)
        #expect(ListeningSettings.approximateBytes(window: .off, quality: .dataSaver) == 0)
    }
}
