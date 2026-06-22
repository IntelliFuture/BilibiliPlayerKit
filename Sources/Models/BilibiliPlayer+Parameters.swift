import Foundation

extension BilibiliPlayer {
    public struct Parameters: Equatable, Hashable, Sendable {
        public var autoPlay: Bool
        public var danmaku: Bool
        public var quality: Quality
        public var asWide: Bool
        public var embedMode: EmbedMode
        public var partParameter: PartParameter

        public init(
            autoPlay: Bool = false,
            danmaku: Bool = false,
            quality: Quality = .automatic,
            asWide: Bool = true,
            embedMode: EmbedMode = .iframeHTML,
            partParameter: PartParameter = .p
        ) {
            self.autoPlay = autoPlay
            self.danmaku = danmaku
            self.quality = quality
            self.asWide = asWide
            self.embedMode = embedMode
            self.partParameter = partParameter
        }
    }

    public enum Quality: Int, Equatable, Hashable, Sendable {
        case automatic = 0
        case lowest = 16
        case low = 32
        case medium = 64
        case high = 80

        var prefersHighQuality: Bool {
            self == .high
        }
    }

    public enum EmbedMode: String, Equatable, Hashable, CaseIterable, Sendable {
        case iframeHTML
        case directPlayerURL
    }

    public enum PartParameter: String, Equatable, Hashable, CaseIterable, Sendable {
        case p
        case page
    }
}
