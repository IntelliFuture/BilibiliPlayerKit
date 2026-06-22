import Foundation

extension BilibiliPlayer {
    public struct HTMLBuilder: Equatable, Hashable, Sendable {
        public init() {}

        public func html(embedURL: URL, allowsFullscreen: Bool = false) -> String {
            let escapedURL = embedURL.absoluteString
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            let fullscreenAttributes = allowsFullscreen ? """
                    allowfullscreen="true"
                    webkitallowfullscreen="true"
            """ : ""

            return """
            <!doctype html>
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
                <style>
                    html, body {
                        width: 100%;
                        height: 100%;
                        margin: 0;
                        padding: 0;
                        overflow: hidden;
                        background: #000;
                    }
                    iframe {
                        position: absolute;
                        inset: 0;
                        width: 100%;
                        height: 100%;
                        border: 0;
                        background: #000;
                    }
                </style>
            </head>
            <body>
                <iframe
                    src="\(escapedURL)"
                    scrolling="no"
                    frameborder="0"
                    framespacing="0"
                    allow="autoplay; picture-in-picture"
            \(fullscreenAttributes)>
                </iframe>
            </body>
            </html>
            """
        }
    }
}
