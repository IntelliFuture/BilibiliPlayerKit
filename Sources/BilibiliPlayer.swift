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

    private(set) var controlSessionID = UUID().uuidString
    private var controlRevision = 0
    private var latestTransportRequestID: String?
    private var lastSnapshotSequence = -1
    private var configuredLoopRange: PlaybackRange?
    private var hasConfiguredLoopRange = false

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
        controlSessionID = UUID().uuidString
        controlRevision = 0
        configuredLoopRange = nil
        hasConfiguredLoopRange = false
        latestTransportRequestID = nil
        lastSnapshotSequence = -1
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
        guard seconds.isFinite, seconds >= 0 else { throw PlayerError.invalidPlaybackRange }
        try await sendControlCommand(name: "seek", value: seconds)
    }

    /// Configures a page-owned loop. Nil restores continuous playback.
    public func setLoopRange(_ range: PlaybackRange?) async throws {
        try Task.checkCancellation()
        guard !hasConfiguredLoopRange || configuredLoopRange != range else { return }
        // An interrupted configuration may have reached the page, so leave the
        // cache invalid until acknowledgement, including when clearing a range.
        hasConfiguredLoopRange = false
        let value: Any
        if let range { value = ["start": range.start, "end": range.end] }
        else { value = NSNull() }
        try await sendControlCommand(name: "setLoopRange", value: value)
        configuredLoopRange = range
        hasConfiguredLoopRange = true
    }

    public func stop() {
        configuredLoopRange = nil
        hasConfiguredLoopRange = false
        controlRevision += 1
        let sessionID = controlSessionID
        let script: String
        do {
            script = try Self.controlCommandJavaScript(name: "stop", value: nil,
                sessionID: sessionID, revision: controlRevision)
        } catch {
            setState(.error(.controlFailed(error.localizedDescription)))
            return
        }
        let evaluate = evaluateJavaScriptHandler
        latestTransportRequestID = nil
        setPlaybackSnapshot(.init())
        setState(.idle)
        Task { [weak self] in
            _ = try? await evaluate?(script)
            guard let self, self.controlSessionID == sessionID, self.state == .idle else { return }
            self.stopLoadingHandler?()
        }
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

    /// Accept only this content's current command stream, in monotonically increasing order.
    @discardableResult
    func receivePlaybackSnapshot(_ snapshot: PlaybackSnapshot) -> Bool {
        guard state != .idle, snapshot.sessionID == controlSessionID,
              snapshot.commandRevision >= controlRevision,
              snapshot.sequence > lastSnapshotSequence else { return false }
        lastSnapshotSequence = snapshot.sequence
        setPlaybackSnapshot(snapshot)
        if let error = snapshot.playbackError {
            setState(.error(.controlFailed(error)))
        } else if snapshot.readyState >= 1, state != .ready {
            setState(.ready)
        }
        return true
    }

    private func sendControlCommand(name: String, value: Any? = nil) async throws {
        try Task.checkCancellation()
        let isTransport = ["play", "pause", "seek", "setLoopRange"].contains(name)
        let requestID = UUID().uuidString
        if isTransport {
            controlRevision += 1
            latestTransportRequestID = requestID
        }
        let revision = controlRevision
        let sessionID = controlSessionID
        let script = try Self.controlCommandJavaScript(name: name, value: value,
            sessionID: sessionID, revision: revision)
        try await withTaskCancellationHandler {
            guard let evaluateJavaScriptHandler else { throw PlayerError.webViewUnavailable }
            do {
                _ = try await evaluateJavaScriptHandler(script)
            } catch {
                guard controlSessionID == sessionID,
                      !isTransport || controlRevision == revision else { throw CancellationError() }
                throw error
            }
            try Task.checkCancellation()
            guard controlSessionID == sessionID,
                  !isTransport || controlRevision == revision else { throw CancellationError() }
        } onCancel: {
            guard isTransport else { return }
            Task { @MainActor [weak self] in
                guard let self, self.controlSessionID == sessionID,
                      self.latestTransportRequestID == requestID else { return }
                // Pause invalidates page-side waits and prevents a cancelled seek from resuming.
                try? await self.sendControlCommand(name: "pause")
            }
        }
    }

    private static func controlCommandJavaScript(name: String, value: Any?,
        sessionID: String, revision: Int) throws -> String {
        var command: [String: Any] = [
            "command": name, "sessionID": sessionID, "revision": revision
        ]
        if let value { command["value"] = value }
        let data = try JSONSerialization.data(withJSONObject: command)
        let json = String(decoding: data, as: UTF8.self)
        return """
        if (!window.__bilibiliPlayerKitControl) {
            throw new Error('Bilibili media bridge is unavailable');
        }
        return await window.__bilibiliPlayerKitControl(\(json));
        """
    }
}
