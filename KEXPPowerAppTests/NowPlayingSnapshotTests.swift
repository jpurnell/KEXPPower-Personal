import Testing
import UIKit
import MediaPlayer
@testable import KEXPPowerExampleSwiftUI

@Suite("NowPlayingSnapshot")
struct NowPlayingSnapshotTests {
    @Test("Missing fields fall back to Airbreak / KEXP / empty album / the KEXP logo")
    func defaults() {
        let snapshot = NowPlayingSnapshot(song: nil, artist: nil, album: nil, imageURI: nil, state: .paused)
        #expect(snapshot.title == "Airbreak")
        #expect(snapshot.artist == "KEXP")
        #expect(snapshot.album == "")
        #expect(snapshot.artworkURLString == "https://kexp.org/static/assets/img/kexp_logo.jpg")
    }

    @Test("Given fields are used as-is")
    func givenFields() {
        let snapshot = NowPlayingSnapshot(song: "VHS Sex", artist: "Artist", album: "Album",
                                          imageURI: "https://www.kexp.org/a.jpg", state: .playing)
        #expect(snapshot.title == "VHS Sex")
        #expect(snapshot.artworkURLString == "https://www.kexp.org/a.jpg")
    }

    @Test("A live playing snapshot becomes the expected Now Playing dictionary, with no artwork key")
    func playingInfo() {
        let snapshot = NowPlayingSnapshot(song: "Song", artist: "Artist", album: "Album", imageURI: nil, state: .playing)
        let info = snapshot.nowPlayingInfo(artwork: nil)
        #expect(info[MPMediaItemPropertyTitle] as? String == "Song")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Artist")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Album")
        #expect(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(info[MPMediaItemPropertyArtwork] == nil)
    }

    @Test("A paused snapshot has a zero playback rate")
    func pausedRate() {
        let snapshot = NowPlayingSnapshot(song: "Song", artist: "Artist", album: "Album", imageURI: nil, state: .paused)
        #expect(snapshot.nowPlayingInfo(artwork: nil)[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    }

    @Test("Artwork, when supplied, is stored as MPMediaItemArtwork rather than a string")
    func artworkType() {
        let snapshot = NowPlayingSnapshot(song: "Song", artist: "Artist", album: "Album", imageURI: nil, state: .playing)
        let info = snapshot.nowPlayingInfo(artwork: UIImage(systemName: "music.note"))
        #expect(info[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
    }
}
