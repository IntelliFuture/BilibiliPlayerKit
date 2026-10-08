#if canImport(WebKit)
import Foundation
import Testing
import WebKit
@testable import BilibiliPlayerKit

@MainActor
@Suite(.serialized)
struct PlaybackControlTests {
    @Test
    func seekWaitsForSeekedBeforeResuming() async throws {
        let fixture = try await MediaFixture.ready()
        try await fixture.player.play()
        _ = try await fixture.webView.evaluateJavaScript("fixture.playCalls = 0")
        var finished = false
        let seek = Task {
            try await fixture.player.seek(to: 4)
            finished = true
        }
        try await fixture.wait("fixture.pendingTarget === 4")
        // HTML currentTime already reports the requested target while seeking.
        #expect(!finished)
        #expect(try await fixture.number("fixture.playCalls") == 0)
        _ = try await fixture.webView.evaluateJavaScript("fixture.completeSeek()")
        try await seek.value
        #expect(finished)
        #expect(try await fixture.number("fixture.playCalls") == 1)
    }

    @Test
    func newerPausePreventsAnInFlightSeekFromResuming() async throws {
        let fixture = try await MediaFixture.ready()
        try await fixture.player.play()
        _ = try await fixture.webView.evaluateJavaScript("fixture.playCalls = 0")
        let seek = Task { try await fixture.player.seek(to: 4) }
        try await fixture.wait("fixture.pendingTarget === 4")
        try await fixture.player.pause()
        _ = try await fixture.webView.evaluateJavaScript("fixture.completeSeek()")
        await #expect(throws: CancellationError.self) { try await seek.value }
        #expect(try await fixture.number("fixture.playCalls") == 0)
        #expect(try await fixture.flag("document.querySelector('video').paused"))
    }

    @Test
    func pageLoopPausesBeforeReturningAndUserPauseCancelsRestart() async throws {
        let fixture = try await MediaFixture.ready()
        try await fixture.player.setLoopRange(.init(start: 0, end: 1))
        try await fixture.player.play()
        _ = try await fixture.webView.evaluateJavaScript("fixture.playCalls = 0; fixture.advanceTo(1.04)")
        try await fixture.wait("fixture.pendingTarget === 0")
        #expect(try await fixture.flag("document.querySelector('video').paused"))
        #expect(try await fixture.number("fixture.playCalls") == 0)
        _ = try await fixture.webView.evaluateJavaScript("fixture.completeSeek()")
        try await fixture.wait("fixture.playCalls === 1")
        _ = try await fixture.webView.evaluateJavaScript("fixture.playCalls = 0; fixture.advanceTo(1.04)")
        try await fixture.wait("fixture.pendingTarget === 0")
        try await fixture.player.pause()
        _ = try await fixture.webView.evaluateJavaScript("fixture.completeSeek()")
        #expect(try await fixture.number("fixture.playCalls") == 0)
        #expect(try await fixture.flag("document.querySelector('video').paused"))
    }
}

@MainActor
private struct MediaFixture {
    let player: BilibiliPlayer
    let webView: WKWebView

    static func ready() async throws -> Self {
        let player = BilibiliPlayer(source: .video(id: "fixture"))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: BilibiliPlayer.UserScript.playbackBridge(
                showsNativeControls: true, sessionID: player.controlSessionID),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("""
        <html><body><video></video><script>
        const video = document.querySelector('video');
        window.fixture = { time: 0, paused: true, seeking: false, playCalls: 0, pendingTarget: null };
        Object.defineProperties(video, {
          currentTime: { get() { return fixture.time; }, set(value) {
            fixture.time = value; fixture.pendingTarget = value; fixture.seeking = true;
            video.dispatchEvent(new Event('seeking'));
          } },
          duration: { get() { return 12; } },
          readyState: { get() { return 4; } },
          paused: { get() { return fixture.paused; } },
          seeking: { get() { return fixture.seeking; } },
          ended: { get() { return false; } }
        });
        video.pause = function () {
          fixture.paused = true; video.dispatchEvent(new Event('pause'));
        };
        video.play = function () {
          fixture.playCalls++; fixture.paused = false;
          video.dispatchEvent(new Event('play')); return Promise.resolve();
        };
        fixture.completeSeek = function () {
          fixture.seeking = false; fixture.pendingTarget = null;
          video.dispatchEvent(new Event('seeked'));
        };
        fixture.advanceTo = function (value) {
          fixture.time = value; video.dispatchEvent(new Event('timeupdate'));
        };
        </script></body></html>
        """, baseURL: nil)
        let fixture = Self(player: player, webView: webView)
        try await fixture.wait("typeof fixture !== 'undefined' && !!window.__bilibiliPlayerKitControl")
        player.evaluateJavaScriptHandler = { [weak webView] script in
            guard let webView else { throw BilibiliPlayer.PlayerError.webViewUnavailable }
            return try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        }
        return fixture
    }

    func wait(_ condition: String) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while ProcessInfo.processInfo.systemUptime < deadline {
            if (try? await flag(condition)) == true { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw BilibiliPlayer.PlayerError.controlFailed("Fixture condition timed out: \(condition)")
    }

    func number(_ expression: String) async throws -> Double {
        try #require(try await webView.evaluateJavaScript(expression) as? NSNumber).doubleValue
    }

    func flag(_ expression: String) async throws -> Bool {
        let value = try await webView.evaluateJavaScript(expression) as? Bool
        return try #require(value as Bool?)
    }
}
#endif
