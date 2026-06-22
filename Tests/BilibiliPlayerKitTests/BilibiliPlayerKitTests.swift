import Foundation
import Testing
@testable import BilibiliPlayerKit

@Test func sourceParsesBVIDAndPageFromBilibiliURL() throws {
    let source = try #require(BilibiliPlayer.Source(urlString: "https://www.bilibili.com/video/BV1ajb3zGEi3?p=8"))

    #expect(source == .video(id: "BV1ajb3zGEi3", page: 8))
}

@Test func sourceParsesBVIDWithoutPageAsFirstPart() throws {
    let source = try #require(BilibiliPlayer.Source(urlString: "https://www.bilibili.com/video/BV1ajb3zGEi3/"))

    #expect(source == .video(id: "BV1ajb3zGEi3", page: 1))
}

@MainActor
@Test func embedURLUsesOfficialPlayerWithCompatibilityParameters() throws {
    let player = BilibiliPlayer(
        source: .video(id: "BV1ajb3zGEi3", page: 8),
        parameters: .init(
            autoPlay: false,
            danmaku: false,
            quality: .lowest
        )
    )

    let url = try #require(player.embedURL)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let pairs: [(String, String)] = (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    }
    let query = Dictionary(uniqueKeysWithValues: pairs)

    #expect(components.scheme == "https")
    #expect(components.host == "player.bilibili.com")
    #expect(components.path == "/player.html")
    #expect(query["bvid"] == "BV1ajb3zGEi3")
    #expect(query["p"] == "8")
    #expect(query["autoplay"] == "false")
    #expect(query["danmaku"] == "0")
    #expect(query["high_quality"] == "0")
    #expect(query["qn"] == "16")
}

@MainActor
@Test func playerHTMLWrapsEmbedURLInResponsiveIframe() throws {
    let player = BilibiliPlayer(source: .video(id: "BV1ajb3zGEi3", page: 8))
    let url = try #require(player.embedURL)
    let html = BilibiliPlayer.HTMLBuilder().html(embedURL: url, allowsFullscreen: true)

    #expect(html.contains("<iframe"))
    #expect(html.contains("src=\"https://player.bilibili.com/player.html?"))
    #expect(html.contains("allowfullscreen=\"true\""))
    #expect(html.contains("width: 100%"))
    #expect(html.contains("height: 100%"))
}

@MainActor
@Test func playerHTMLDisablesFullscreenByDefault() throws {
    let player = BilibiliPlayer(source: .video(id: "BV1ajb3zGEi3", page: 8))
    let url = try #require(player.embedURL)
    let html = BilibiliPlayer.HTMLBuilder().html(embedURL: url)

    #expect(!html.contains("allowfullscreen"))
    #expect(!html.contains("webkitallowfullscreen"))
}

@MainActor
@Test func embedURLCanUsePagePartParameterForCompatibilityTesting() throws {
    let player = BilibiliPlayer(
        source: .video(id: "BV1ajb3zGEi3", page: 8),
        parameters: .init(partParameter: .page)
    )

    let url = try #require(player.embedURL)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })

    #expect(query["page"] == "8")
    #expect(query["p"] == nil)
}

@MainActor
@Test func automaticQualityOmitsQualityQueryItems() throws {
    let player = BilibiliPlayer(
        source: .video(id: "BV1ajb3zGEi3", page: 8),
        parameters: .init(quality: .automatic)
    )

    let url = try #require(player.embedURL)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })

    #expect(query["high_quality"] == nil)
    #expect(query["qn"] == nil)
}

@Test func defaultConfigurationPrefersInlineAVCPlayback() {
    let configuration = BilibiliPlayer.Configuration()

    #expect(configuration.allowsInlineMediaPlayback)
    #expect(configuration.allowsPictureInPictureMediaPlayback)
    #expect(!configuration.requiresUserActionForMediaPlayback)
    #expect(configuration.preferAVCPlayback)
    #expect(!configuration.showsNativeControls)
    #expect(!configuration.allowsFullscreen)
}

@Test func playbackBridgeSuppressesBilibiliUpsellOverlayWhenNativeControlsAreHidden() {
    let script = BilibiliPlayer.UserScript.playbackBridge(showsNativeControls: false)

    #expect(script.contains("suppressPromotionalOverlays"))
    #expect(script.contains("前往哔哩哔哩"))
    #expect(script.contains("观看更高清"))
    #expect(script.contains("elementContainsMedia"))
    #expect(script.contains("movePromotionalOverlayToCorner"))
}

@Test func desktopSafariUserAgentAvoidsMobileToken() {
    let userAgent = BilibiliPlayer.Configuration.desktopSafariUserAgent

    #expect(userAgent.contains("Macintosh"))
    #expect(!userAgent.contains("Mobile"))
}
