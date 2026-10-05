import Foundation

/// What the Music app is playing.
public struct NowPlaying: Equatable, CustomStringConvertible {
    public var artist: String
    public var title: String
    public var album: String
    /// Track length in seconds, 0 if unknown.
    public var duration: Int
    /// Playback position in seconds.
    public var position: Double
    public var isPlaying: Bool

    public init(artist: String = "", title: String = "", album: String = "", duration: Int = 0, position: Double = 0, isPlaying: Bool = false) {
        self.artist = artist
        self.title = title
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
    }

    public var isValid: Bool { !artist.isEmpty && !title.isEmpty }
    public var description: String { "\(artist) - \(title)" }
}
