import Combine
import Foundation

@MainActor
public final class BilibiliPlayer: ObservableObject {
    @Published public private(set) var state: State = .idle
    @Published public private(set) var playbackSnapshot = PlaybackSnapshot()

    @Published public var source: Source {
        didSet {
            guard oldValue != source else { return }
            reload()
        }
    }

    @Published public var parameters: Parameters {
        didSet {
            guard oldValue != parameters else { return }
            reload()
        }
    }

    public let configuration: Configuration

    var loadHandler: ((URL) -> Void)?
    var stopLoadingHandler: (() -> Void)?
    var evaluateJavaScriptHandler: ((String) async throws -> Any?)?

    public init(
        source: Source,
        parameters: Parameters = .init(),
        configuration: Configuration = .init()
    ) {
        self.source = source
        self.parameters = parameters
        self.configuration = configuration
    }

    public convenience init?(
        urlString: String,
        parameters: Parameters = .init(),
        configuration: Configuration = .init()
    ) {
        guard let source = Source(urlString: urlString) else { return nil }
        self.init(source: source, parameters: parameters, configuration: configuration)
    }

    public var embedURL: URL? {
        source.embedURL(parameters: parameters)
    }

    public func reload() {
        guard let embedURL else {
            setState(.error(.invalidSource))
            return
        }
        setPlaybackSnapshot(.init())
        setState(.loading)
        loadHandler?(embedURL)
    }

    public func play() async throws {
        try await sendControlCommand(name: "play")
    }

    public func pause() async throws {
        try await sendControlCommand(name: "pause")
    }

    public func seek(to seconds: TimeInterval) async throws {
        guard seconds.isFinite, seconds >= 0 else { return }
        try await sendControlCommand(name: "seek", value: seconds)
    }

    public func stop() {
        Task { try? await sendControlCommand(name: "stop") }
        stopLoadingHandler?()
        setPlaybackSnapshot(.init())
        setState(.idle)
    }

    public func setMuted(_ isMuted: Bool) async throws {
        try await sendControlCommand(name: "setMuted", value: isMuted)
    }

    public func setPlaybackRate(_ rate: Double) async throws {
        guard rate.isFinite, rate > 0 else { return }
        try await sendControlCommand(name: "setRate", value: rate)
    }

    func setState(_ state: State) {
        self.state = state
    }

    func setPlaybackSnapshot(_ snapshot: PlaybackSnapshot) {
        playbackSnapshot = snapshot
    }

    private func sendControlCommand(name: String, value: (any Sendable)? = nil) async throws {
        try await evaluateVideoJavaScript(Self.controlCommandJavaScript(name: name, value: value))
    }

    private func evaluateVideoJavaScript(_ javaScript: String) async throws {
        guard let evaluateJavaScriptHandler else {
            throw PlayerError.webViewUnavailable
        }
        _ = try await evaluateJavaScriptHandler(javaScript)
    }

    private static func controlCommandJavaScript(name: String, value: (any Sendable)?) -> String {
        var command: [String: Any] = [
            "type": "bilibili-player-kit-command",
            "command": name
        ]
        if let value {
            command["value"] = value
        }
        let data = (try? JSONSerialization.data(withJSONObject: command)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return """
        (function () {
            const command = \(json);
            try {
                if (window.__bilibiliPlayerKitControl) {
                    window.__bilibiliPlayerKitControl(command);
                }
            } catch (_) {}
            try {
                window.postMessage(command, '*');
            } catch (_) {}
            try {
                document.querySelectorAll('iframe').forEach(function (frame) {
                    if (frame.contentWindow) {
                        frame.contentWindow.postMessage(command, '*');
                    }
                });
            } catch (_) {}
        })();
        """
    }
}
