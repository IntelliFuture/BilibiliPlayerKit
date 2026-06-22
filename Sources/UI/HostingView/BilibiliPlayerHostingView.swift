#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

@MainActor
public final class BilibiliPlayerHostingView: UIView {
    public let player: BilibiliPlayer
    public let webView: WKWebView

    private var loadedURL: URL?
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
                source: BilibiliPlayer.UserScript.playbackBridge(showsNativeControls: player.configuration.showsNativeControls),
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

        scriptMessageHandler.onSnapshot = { [weak player] snapshot in
            player?.setPlaybackSnapshot(snapshot)
            if player?.state == .loading {
                player?.setState(.ready)
            }
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

        navigationDelegate.onReady = { [weak player] in
            player?.setState(.ready)
        }
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
        }
        player.evaluateJavaScriptHandler = { [weak self] script in
            guard let self else {
                throw BilibiliPlayer.PlayerError.webViewUnavailable
            }
            return try await self.webView.evaluateJavaScript(script)
        }
    }

    private func load(_ url: URL) {
        guard loadedURL != url else {
            player.setState(.ready)
            return
        }
        loadedURL = url
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

    var onSnapshot: ((BilibiliPlayer.PlaybackSnapshot) -> Void)?

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
            readyState: readyState
        ))
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
