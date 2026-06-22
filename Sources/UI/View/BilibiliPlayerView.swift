#if canImport(SwiftUI) && canImport(UIKit) && canImport(WebKit)
import SwiftUI
import UIKit

public struct BilibiliPlayerView<Overlay: View>: View {
    @ObservedObject private var player: BilibiliPlayer
    private let overlay: (BilibiliPlayer.State) -> Overlay

    public init(
        _ player: BilibiliPlayer,
        @ViewBuilder overlay: @escaping (BilibiliPlayer.State) -> Overlay
    ) {
        self.player = player
        self.overlay = overlay
    }

    public var body: some View {
        ZStack {
            BilibiliPlayerRepresentable(player: player)
            overlay(player.state)
        }
    }
}

public extension BilibiliPlayerView where Overlay == EmptyView {
    init(_ player: BilibiliPlayer) {
        self.init(player) { _ in EmptyView() }
    }

    init?(_ urlString: String) {
        guard let player = BilibiliPlayer(urlString: urlString) else { return nil }
        self.init(player)
    }
}

private struct BilibiliPlayerRepresentable: UIViewRepresentable {
    let player: BilibiliPlayer

    func makeUIView(context: Context) -> BilibiliPlayerHostingView {
        BilibiliPlayerHostingView(player: player)
    }

    func updateUIView(_ uiView: BilibiliPlayerHostingView, context: Context) {
        uiView.reload()
    }
}
#endif
