import Foundation

extension BilibiliPlayer {
    public struct Configuration: Equatable, Hashable, Sendable {
        public var allowsInlineMediaPlayback: Bool
        public var allowsPictureInPictureMediaPlayback: Bool
        public var requiresUserActionForMediaPlayback: Bool
        public var customUserAgent: String?
        public var preferAVCPlayback: Bool
        public var showsNativeControls: Bool
        public var allowsFullscreen: Bool

        public init(
            allowsInlineMediaPlayback: Bool = true,
            allowsPictureInPictureMediaPlayback: Bool = true,
            requiresUserActionForMediaPlayback: Bool = false,
            customUserAgent: String? = nil,
            preferAVCPlayback: Bool = true,
            showsNativeControls: Bool = false,
            allowsFullscreen: Bool = false
        ) {
            self.allowsInlineMediaPlayback = allowsInlineMediaPlayback
            self.allowsPictureInPictureMediaPlayback = allowsPictureInPictureMediaPlayback
            self.requiresUserActionForMediaPlayback = requiresUserActionForMediaPlayback
            self.customUserAgent = customUserAgent
            self.preferAVCPlayback = preferAVCPlayback
            self.showsNativeControls = showsNativeControls
            self.allowsFullscreen = allowsFullscreen
        }
    }
}

extension BilibiliPlayer.Configuration {
    public static let desktopSafariUserAgent = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.0 Safari/605.1.15"
    ].joined(separator: " ")
}
