import Foundation

extension BilibiliPlayer {
    public struct PlaybackSnapshot: Equatable, Sendable {
        public var currentTime: TimeInterval
        public var duration: TimeInterval
        public var isPaused: Bool
        public var isEnded: Bool
        public var readyState: Int
        public var rawCurrentTime: TimeInterval?
        public var loopBoundaryTime: TimeInterval?
        public var isSeeking: Bool
        public var isLoopTransition: Bool
        public var playbackError: String?
        public var sessionID: String?
        public var commandRevision: Int
        public var sequence: Int

        public init(
            currentTime: TimeInterval = 0,
            duration: TimeInterval = 0,
            isPaused: Bool = true,
            isEnded: Bool = false,
            readyState: Int = 0,
            rawCurrentTime: TimeInterval? = nil,
            loopBoundaryTime: TimeInterval? = nil,
            isSeeking: Bool = false,
            isLoopTransition: Bool = false,
            playbackError: String? = nil,
            sessionID: String? = nil,
            commandRevision: Int = 0,
            sequence: Int = 0
        ) {
            self.currentTime = currentTime
            self.duration = duration
            self.isPaused = isPaused
            self.isEnded = isEnded
            self.readyState = readyState
            self.rawCurrentTime = rawCurrentTime
            self.loopBoundaryTime = loopBoundaryTime
            self.isSeeking = isSeeking
            self.isLoopTransition = isLoopTransition
            self.playbackError = playbackError
            self.sessionID = sessionID
            self.commandRevision = commandRevision
            self.sequence = sequence
        }
    }

    public struct PlaybackRange: Equatable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval

        public init(start: TimeInterval, end: TimeInterval) throws {
            guard start.isFinite, end.isFinite, start >= 0, end > start else {
                throw PlayerError.invalidPlaybackRange
            }
            self.start = start
            self.end = end
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case loading
        case ready
        case error(PlayerError)
    }

    public enum PlayerError: Error, Equatable, Sendable {
        case invalidPlaybackRange
        case controlFailed(String)
        case invalidSource
        case webViewUnavailable
        case unsupportedIframeControl
        case navigationFailed(String)
    }
}

extension BilibiliPlayer.PlayerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPlaybackRange:
            return "Playback range must have a finite nonnegative start and a later end."
        case .controlFailed(let message):
            return message
        case .invalidSource:
            return "Invalid Bilibili video source."
        case .webViewUnavailable:
            return "Bilibili player WebView is unavailable."
        case .unsupportedIframeControl:
            return "Bilibili iframe playback does not expose this external control."
        case .navigationFailed(let message):
            return message
        }
    }
}
