import Foundation

struct BilibiliSampleVideo: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let urlString: String

    static let crayonShinChanPart8 = BilibiliSampleVideo(
        id: "shinchan-p8",
        title: "蜡笔小新合集 P8",
        urlString: "https://www.bilibili.com/video/BV1ajb3zGEi3?p=8"
    )

    static let all: [BilibiliSampleVideo] = [
        .crayonShinChanPart8
    ]
}
