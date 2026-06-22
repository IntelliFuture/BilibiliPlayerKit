import BilibiliPlayerKit
import SwiftUI

@MainActor
struct ContentView: View {
    @State private var player: BilibiliPlayer
    @State private var selectedSample: BilibiliSampleVideo
    @State private var urlString: String
    @State private var errorMessage: String?
    @State private var preferAVCPlayback = true
    @State private var useDesktopUserAgent = false

    private let qualities: [BilibiliPlayer.Quality] = [
        .automatic,
        .lowest,
        .low,
        .medium,
        .high
    ]

    init() {
        let sample = BilibiliSampleVideo.crayonShinChanPart8
        let source = BilibiliPlayer.Source(urlString: sample.urlString) ?? .video(id: "BV1ajb3zGEi3", page: 8)
        _player = State(initialValue: BilibiliPlayer(
            source: source,
            configuration: .init(
                customUserAgent: BilibiliPlayer.Configuration.desktopSafariUserAgent,
                preferAVCPlayback: true
            )
        ))
        _selectedSample = State(initialValue: sample)
        _urlString = State(initialValue: sample.urlString)
        _useDesktopUserAgent = State(initialValue: true)
    }

    var body: some View {
        NavigationStack {
            List {
                playerSection
                sourceSection
                parametersSection
                controlsSection
                stateSection
            }
            .navigationTitle("BilibiliPlayerKit")
            .headerProminence(.increased)
        }
    }
}

private extension ContentView {
    var playerSection: some View {
        Section {
            BilibiliPlayerView(player) { state in
                switch state {
                case .idle, .loading:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.35))
                case .ready:
                    EmptyView()
                case .error(let error):
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                        Text(error.localizedDescription)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.55))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .listRowInsets(.init())
            .listRowBackground(Color.black)
        }
    }

    var sourceSection: some View {
        Section("Source") {
            Picker("Sample", selection: $selectedSample) {
                ForEach(BilibiliSampleVideo.all) { sample in
                    Text(sample.title).tag(sample)
                }
            }
            .onChange(of: selectedSample) { _, sample in
                urlString = sample.urlString
                loadURLString(sample.urlString)
            }

            TextField("https://www.bilibili.com/video/...", text: $urlString, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Load URL", systemImage: "play.rectangle") {
                loadURLString(urlString)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    var parametersSection: some View {
        Section {
            Toggle("Autoplay", isOn: Binding(
                get: { player.parameters.autoPlay },
                set: { player.parameters.autoPlay = $0 }
            ))
            Toggle("Danmaku", isOn: Binding(
                get: { player.parameters.danmaku },
                set: { player.parameters.danmaku = $0 }
            ))
            Toggle("Prefer AVC", isOn: Binding(
                get: { preferAVCPlayback },
                set: { value in
                    preferAVCPlayback = value
                    rebuildPlayer()
                }
            ))
            Toggle("Desktop UA", isOn: Binding(
                get: { useDesktopUserAgent },
                set: { value in
                    useDesktopUserAgent = value
                    rebuildPlayer()
                }
            ))
            Picker("Quality", selection: Binding(
                get: { player.parameters.quality },
                set: { player.parameters.quality = $0 }
            )) {
                ForEach(qualities, id: \.rawValue) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            Picker("Embed Mode", selection: Binding(
                get: { player.parameters.embedMode },
                set: { player.parameters.embedMode = $0 }
            )) {
                ForEach(BilibiliPlayer.EmbedMode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Picker("Part Param", selection: Binding(
                get: { player.parameters.partParameter },
                set: { player.parameters.partParameter = $0 }
            )) {
                ForEach(BilibiliPlayer.PartParameter.allCases, id: \.rawValue) { parameter in
                    Text(parameter.rawValue).tag(parameter)
                }
            }
            LabeledContent("Embed URL", value: player.embedURL?.absoluteString ?? "")
        } header: {
            Text("Parameters")
        } footer: {
            Text("Changing parameters reloads the Bilibili iframe player.")
        }
    }

    var controlsSection: some View {
        Section {
            Button("Reload", systemImage: "arrow.clockwise") {
                player.reload()
            }
            Button("Stop", systemImage: "stop.fill") {
                player.stop()
            }
        } header: {
            Text("Controls")
        } footer: {
            Text("Playback uses the controls inside Bilibili's official iframe player. External play, pause, and seek are not exposed by a public Bilibili iframe API.")
        }
    }

    var stateSection: some View {
        Section("State") {
            LabeledContent("Player", value: player.state.title)
        }
    }

    func loadURLString(_ value: String) {
        guard let source = BilibiliPlayer.Source(urlString: value) else {
            errorMessage = "Invalid Bilibili video URL"
            return
        }
        errorMessage = nil
        player.source = source
    }

    func rebuildPlayer() {
        guard let source = BilibiliPlayer.Source(urlString: urlString) else { return }
        let parameters = player.parameters
        let configuration = BilibiliPlayer.Configuration(
            customUserAgent: useDesktopUserAgent ? BilibiliPlayer.Configuration.desktopSafariUserAgent : nil,
            preferAVCPlayback: preferAVCPlayback
        )
        player.stop()
        let replacement = BilibiliPlayer(
            source: source,
            parameters: parameters,
            configuration: configuration
        )
        player = replacement
    }
}

private extension BilibiliPlayer.State {
    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading"
        case .ready:
            return "Ready"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

private extension BilibiliPlayer.Quality {
    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .lowest:
            return "Lowest"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

private extension BilibiliPlayer.EmbedMode {
    var title: String {
        switch self {
        case .iframeHTML:
            return "Iframe HTML"
        case .directPlayerURL:
            return "Direct URL"
        }
    }
}

#Preview {
    ContentView()
}
