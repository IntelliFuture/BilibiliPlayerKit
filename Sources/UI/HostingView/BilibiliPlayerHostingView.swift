#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

@MainActor
public final class BilibiliPlayerHostingView: UIView {
    public let player: BilibiliPlayer
    public let webView: WKWebView

    private var loadedURL: URL?
    private var mediaFrame: WKFrameInfo?
    private let navigationDelegate = BilibiliPlayerNavigationDelegate()
    private let scriptMessageHandler: BilibiliPlayerScriptMessageHandler

    public init(player: BilibiliPlayer) {
        self.player = player
        self.scriptMessageHandler = BilibiliPlayerScriptMessageHandler()

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = player.configuration.allowsInlineMediaPlayback
        configuration.allowsPictureInPictureMediaPlayback = player.configuration.allowsPictureInPictureMediaPlayback
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = player.configuration.requiresUserActionForMediaPlayback ? .all : []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: BilibiliPlayer.UserScript.playbackBridge(showsNativeControls: player.configuration.showsNativeControls, sessionID: player.controlSessionID),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        if player.configuration.preferAVCPlayback {
            let script = WKUserScript(
                source: BilibiliPlayer.UserScript.preferAVCPlayback,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(script)
        }
        configuration.userContentController.add(
            scriptMessageHandler,
            name: BilibiliPlayerScriptMessageHandler.name
        )

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)

        scriptMessageHandler.onSnapshot = { [weak self, weak player] snapshot, frame in
            guard let self, let player, snapshot.sessionID == player.controlSessionID else { return }
            if snapshot.readyState >= 1 { self.mediaFrame = frame }
            guard player.receivePlaybackSnapshot(snapshot) else { return }
            if player.state == .loading, snapshot.readyState >= 1 { player.setState(.ready) }
        }
        setUpWebView()
        bindPlayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: BilibiliPlayerScriptMessageHandler.name
        )
    }

    public func reload() {
        player.reload()
    }

    private func setUpWebView() {
        backgroundColor = .black
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        if let customUserAgent = player.configuration.customUserAgent {
            webView.customUserAgent = customUserAgent
        }

        // Navigation completion is not media readiness. Metadata from the actual
        // video frame confirms readiness through onSnapshot above.
        navigationDelegate.onError = { [weak player] error in
            player?.setState(.error(.navigationFailed(error.localizedDescription)))
        }
        webView.navigationDelegate = navigationDelegate

        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func bindPlayer() {
        player.loadHandler = { [weak self] url in
            self?.load(url)
        }
        player.stopLoadingHandler = { [weak self] in
            self?.webView.stopLoading()
            self?.loadedURL = nil
            self?.mediaFrame = nil
        }
        player.evaluateJavaScriptHandler = { [weak self, weak player] script in
            guard let self, let player else {
                throw BilibiliPlayer.PlayerError.webViewUnavailable
            }
            let sessionID = player.controlSessionID
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while self.mediaFrame == nil {
                try Task.checkCancellation()
                guard player.controlSessionID == sessionID else { throw CancellationError() }
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    throw BilibiliPlayer.PlayerError.unsupportedIframeControl
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            guard player.controlSessionID == sessionID else { throw CancellationError() }
            return try await self.webView.callAsyncJavaScript(script, arguments: [:],
                in: self.mediaFrame, contentWorld: .page)
        }
    }

    private func load(_ url: URL) {
        loadedURL = url
        mediaFrame = nil
        // Every document/frame carries this load's identity, so old messages
        // cannot configure or publish progress into a replacement source.
        let scripts = webView.configuration.userContentController
        scripts.removeAllUserScripts()
        scripts.addUserScript(WKUserScript(
            source: BilibiliPlayer.UserScript.playbackBridge(
                showsNativeControls: player.configuration.showsNativeControls,
                sessionID: player.controlSessionID),
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if player.configuration.preferAVCPlayback {
            scripts.addUserScript(WKUserScript(source: BilibiliPlayer.UserScript.preferAVCPlayback,
                injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        switch player.parameters.embedMode {
        case .iframeHTML:
            let html = BilibiliPlayer.HTMLBuilder().html(
                embedURL: url,
                allowsFullscreen: player.configuration.allowsFullscreen
            )
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.bilibili.com"))
        case .directPlayerURL:
            webView.load(URLRequest(url: url))
        }
    }
}

@MainActor
private final class BilibiliPlayerScriptMessageHandler: NSObject, WKScriptMessageHandler {
    nonisolated static let name = "bilibiliPlayerKit"

    var onSnapshot: ((BilibiliPlayer.PlaybackSnapshot, WKFrameInfo) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.name,
              let body = message.body as? [String: Any],
              body["kind"] as? String == "status" else {
            return
        }
        let currentTime = Self.doubleValue(body["currentTime"])
        let duration = Self.doubleValue(body["duration"])
        let isPaused = Self.boolValue(body["paused"], defaultValue: true)
        let isEnded = Self.boolValue(body["ended"], defaultValue: false)
        let readyState = Self.intValue(body["readyState"])

        onSnapshot?(.init(
            currentTime: currentTime,
            duration: duration,
            isPaused: isPaused,
            isEnded: isEnded,
            readyState: readyState,
            rawCurrentTime: (body["rawCurrentTime"] as? NSNumber)?.doubleValue,
            loopBoundaryTime: (body["loopBoundaryTime"] as? NSNumber)?.doubleValue,
            isSeeking: Self.boolValue(body["seeking"], defaultValue: false),
            isLoopTransition: Self.boolValue(body["loopTransition"], defaultValue: false),
            playbackError: body["playbackError"] as? String,
            sessionID: body["sessionID"] as? String,
            commandRevision: Self.intValue(body["revision"]),
            sequence: Self.intValue(body["sequence"])
        ), message.frameInfo)
    }

    private static func doubleValue(_ value: Any?) -> Double {
        switch value {
        case let number as NSNumber:
            return number.doubleValue.isFinite ? number.doubleValue : 0
        case let double as Double:
            return double.isFinite ? double : 0
        case let string as String:
            let value = Double(string) ?? 0
            return value.isFinite ? value : 0
        default:
            return 0
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        case let string as String:
            return Int(string) ?? 0
        default:
            return 0
        }
    }

    private static func boolValue(_ value: Any?, defaultValue: Bool) -> Bool {
        switch value {
        case let number as NSNumber:
            return number.boolValue
        case let bool as Bool:
            return bool
        case let string as String:
            return (string as NSString).boolValue
        default:
            return defaultValue
        }
    }
}

@MainActor
private final class BilibiliPlayerNavigationDelegate: NSObject, WKNavigationDelegate {
    var onReady: (() -> Void)?
    var onError: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onReady?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError?(error)
    }
}
#endif
