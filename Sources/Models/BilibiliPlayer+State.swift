import Foundation

extension BilibiliPlayer {
    public struct PlaybackSnapshot: Equatable, Sendable {
        public var currentTime: TimeInterval
        public var duration: TimeInterval
        public var isPaused: Bool
        public var isEnded: Bool
        public var readyState: Int

        public init(
            currentTime: TimeInterval = 0,
            duration: TimeInterval = 0,
            isPaused: Bool = true,
            isEnded: Bool = false,
            readyState: Int = 0
        ) {
            self.currentTime = currentTime
            self.duration = duration
            self.isPaused = isPaused
            self.isEnded = isEnded
            self.readyState = readyState
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case loading
        case ready
        case error(PlayerError)
    }

    public enum PlayerError: Error, Equatable, Sendable {
        case invalidSource
        case webViewUnavailable
        case unsupportedIframeControl
        case navigationFailed(String)
    }
}

extension BilibiliPlayer.PlayerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
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
