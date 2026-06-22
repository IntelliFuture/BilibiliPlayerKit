import Foundation

extension BilibiliPlayer {
    public enum Source: Equatable, Hashable, Sendable {
        case video(id: String, page: Int = 1)

        public init?(urlString: String) {
            guard let url = URL(string: urlString) else { return nil }
            self.init(url: url)
        }

        public init?(url: URL) {
            let pathParts = url.path.split(separator: "/")
            guard let rawBVID = pathParts.first(where: { $0.hasPrefix("BV") }) else { return nil }
            let bvid = String(rawBVID).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bvid.isEmpty else { return nil }
            self = .video(id: bvid, page: Self.page(from: url))
        }

        func embedURL(parameters: BilibiliPlayer.Parameters) -> URL? {
            switch self {
            case .video(let id, let page):
                var components = URLComponents()
                components.scheme = "https"
                components.host = "player.bilibili.com"
                components.path = "/player.html"
                var queryItems = [
                    URLQueryItem(name: "bvid", value: id),
                    URLQueryItem(name: parameters.partParameter.rawValue, value: String(max(1, page))),
                    URLQueryItem(name: "autoplay", value: parameters.autoPlay ? "true" : "false"),
                    URLQueryItem(name: "danmaku", value: parameters.danmaku ? "1" : "0"),
                ]
                if parameters.quality != .automatic {
                    queryItems.append(URLQueryItem(name: "high_quality", value: parameters.quality.prefersHighQuality ? "1" : "0"))
                    queryItems.append(URLQueryItem(name: "qn", value: String(parameters.quality.rawValue)))
                }
                components.queryItems = queryItems
                return components.url
            }
        }

        private static func page(from url: URL) -> Int {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let rawValue = components.queryItems?.first(where: { $0.name == "p" })?.value,
                  let value = Int(rawValue),
                  value > 0 else {
                return 1
            }
            return value
        }
    }
}
