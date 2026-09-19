//
//  Huya.swift
//  HuyaKit
//
//  Live room info: PC webpage fetch + typed stream models.
//  - Marshal: JSON parsing (same model shape as iina-plus Huya.swift)
//  - SwiftSoup: locate the <script> holding the stream JSON
//  - Alamofire: HTTP requests
//

import Foundation
import Alamofire
import Marshal
import SwiftSoup

// MARK: - HuyaStream

public struct HuyaStream: Unmarshaling, Sendable {
    public var data: [InfoData]
    public var vMultiStreamInfo: [StreamInfo]
    /// Top-level bitRate from the page (not part of the stream JSON)
    public var bitRate: Int = 0

    public init(object: any MarshaledObject) throws {
        data = try object.value(for: "data")
        vMultiStreamInfo = try object.value(for: "vMultiStreamInfo")
    }

    /// Fetch stream info from the Huya PC webpage (full URL)
    public static func fetch(url: String) async throws -> HuyaStream {
        let html = try await AF.request(url).serializingString().value

        // Locate the stream JSON inside a <script> via SwiftSoup, then
        // brace-match the value (skips braces inside strings)
        let doc = try SwiftSoup.parse(html)
        for script in try doc.getElementsByTag("script") {
            let content = script.data()
            guard let idx = content.range(of: "stream:") else { continue }

            guard let jsonSubstring = braceMatchedJSON(content, after: idx.upperBound),
                  let jsonData = jsonSubstring.data(using: .utf8) else {
                continue
            }
            let jsonObj: JSONObject = try JSONParser.JSONObjectWithData(jsonData)
            var stream: HuyaStream = try HuyaStream(object: jsonObj)
            stream.bitRate = html.bitRateValue()
            return stream
        }

        throw HuyaError.parseError("stream field not found")
    }

    /// Fetch stream info from the Huya PC webpage (roomId)
    public static func fetch(roomId: String) async throws -> HuyaStream {
        try await fetch(url: "https://www.huya.com/\(roomId)")
    }

    /// 线路择优后的 gameStreamInfo：官方优先级 HS > TX > AL（按下发顺序取最优）。
    ///
    /// 用 `min(by:)` 而非 `sorted(by:).first`：Swift 的 sort 不稳定，同 rank 线路顺序不定，
    /// 会让同一房间两次播放选到不同线路；`min(by:)` 并列时保留靠前的一条。
    public var primaryStream: GameStreamInfo? {
        guard let list = data.first?.streamInfoList, !list.isEmpty else { return nil }
        func rank(_ gsi: GameStreamInfo) -> Int {
            let cdn = gsi.sCdnType.lowercased()
            if cdn.hasPrefix("hs") { return 0 }
            if cdn.hasPrefix("tx") { return 1 }
            if cdn.hasPrefix("al") { return 2 }
            return 3
        }
        return list.min { rank($0) < rank($1) }
    }

    /// Top-level codecType (gameLiveInfo.codecType)
    ///
    /// ⚠️ **不要用它判编码族** —— 它只说"房间有 HEVC 流"，族必须逐档判定（`isH265Gear`）；
    /// 曾当全局覆盖 → 实测 404。见 MEMORY.md §3.3
    public var codecType: Int {
        data.first?.liveInfo.codecType ?? 0
    }

    /// 可播档位列表：官方 `vMultiStreamInfo` 去掉全部 HDR 档。
    ///
    /// 清晰度链路的**唯一**输入源（菜单 / 选档 / 自动档 / 族判定都从这里取），保留官方菜单顺序。
    /// 过滤条件只此一处 —— 历史上散落的 4 处 `iCompatibleFlag != 16384` 写法互相不一致。
    public var playableStreamInfo: [StreamInfo] {
        vMultiStreamInfo.filter { !$0.isHDREntry }
    }

    static func braceMatchedJSON(_ s: String, after: String.Index) -> String? {
        let afterStream = s[after...]
        guard let braceStart = afterStream.firstIndex(of: "{") else { return nil }

        var depth = 0
        var end = braceStart
        var inStr = false
        var escape = false
        var i = braceStart
        while i < afterStream.endIndex {
            let c = afterStream[i]
            if escape { escape = false; i = afterStream.index(after: i); continue }
            if c == "\\" { escape = true; i = afterStream.index(after: i); continue }
            if c == "\"" { inStr.toggle(); i = afterStream.index(after: i); continue }
            if inStr { i = afterStream.index(after: i); continue }
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { end = afterStream.index(after: i); break }
            }
            i = afterStream.index(after: i)
        }
        return String(afterStream[braceStart..<end])
    }

    public struct StreamInfo: Unmarshaling, Sendable {
        public var sDisplayName: String
        public var iBitRate: Int
        public var iCodecType: Int
        public var iCompatibleFlag: Int
        public var iHEVCBitRate: Int

        /// `iCompatibleFlag` 的 HDR 位（官方 `isHDR` = 8192、`isFakeHDR` = 16384）
        public static let compatFlagHDR = 8192
        public static let compatFlagFakeHDR = 16384

        /// 该档是否带 HDR 标记（真 HDR 8192 / 伪 HDR 16384）。本项目策略：**两种一律不播**。
        /// 真 HDR 官方 web 播放器自己也丢；伪 HDR 官方要先用 `mappingFakeHdrBitrate` 重写 `iBitRate`
        /// 才拿去算 codecType，那张配置表我们没还原 ⇒ 留着只会用错的码率拉到错的档。
        ///
        /// ⚠️ 必须位与：写成 `!= 16384` 会漏掉 `24576`（两位都置）这类组合，也保不住 8192。
        /// 决策与依据：MEMORY.md §4.1
        public var isHDREntry: Bool {
            (iCompatibleFlag & (Self.compatFlagHDR | Self.compatFlagFakeHDR)) != 0
        }

        public init(object: any MarshaledObject) throws {
            sDisplayName = try object.value(for: "sDisplayName")
            iBitRate = try object.value(for: "iBitRate")
            iCodecType = try object.value(for: "iCodecType")
            iCompatibleFlag = try object.value(for: "iCompatibleFlag")
            iHEVCBitRate = (try? object.value(for: "iHEVCBitRate")) ?? -1
        }
    }

    public struct InfoData: Unmarshaling, Sendable {
        public var liveInfo: GameLiveInfo
        public var streamInfoList: [GameStreamInfo]

        public init(object: any MarshaledObject) throws {
            liveInfo = try object.value(for: "gameLiveInfo")
            streamInfoList = try object.value(for: "gameStreamInfoList")
        }
    }

    public struct GameLiveInfo: Unmarshaling, Sendable {
        public var title: String = ""
        public var name: String = ""
        public var isLiving = false
        public var avatar: String
        public var rid: Int
        public var cover: String = ""
        public let uid: Int
        public var isSeeTogetherRoom = false
        public let isSecret: Int
        /// Top-level codecType, basis of official isH265CodecType()
        public var codecType: Int = 0

        public init(object: any MarshaledObject) throws {
            let name1: String = try object.value(for: "roomName")
            let name2: String = try object.value(for: "introduction")

            title = name1 == "" ? name2 : name1
            name = try object.value(for: "nick")

            avatar = try object.value(for: "avatar180")
            avatar = avatar.https()
            rid = try object.value(for: "profileRoom")
            cover = try object.value(for: "screenshot")
            cover = cover.https()

            if let uid: Int = try? object.value(for: "uid") {
                self.uid = uid
            } else if let uid: String = try? object.value(for: "uid"),
                      let iuid = Int(uid) {
                self.uid = iuid
            } else {
                throw MarshalError.keyNotFound(key: "huya.GameLiveInfo.uid")
            }

            isSecret = try object.value(for: "isSecret")
            let gameHostName: String = try object.value(for: "gameHostName")
            isSeeTogetherRoom = gameHostName == "seeTogether"
            codecType = (try? object.value(for: "codecType")) ?? 0
        }
    }

    public struct GameStreamInfo: Unmarshaling, Sendable {
        public var sStreamName: String
        public var sP2pUrl: String
        public var sP2pAntiCode: String
        /// CDN 类型（AL/TX/HS），线路择优依据（HS > TX > AL）
        public var sCdnType: String = ""
        /// 该线路是否支持 HEVC（官方 `isSupportedH265` 的第一个与项，缺它会把只有 H.264 的
        /// 档误判成 HEVC，拉出 404）；0 = 不支持
        public var iIsHEVCSupport: Int = 0
        /// 该线路的 P2P 支持等级。官方 `createStreamId` 用它算 **cdnBrand**：
        /// `cdnBrand = iIsP2PSupport > 1 ? iIsP2PSupport : 0`（是线路相关值，不是常量）。
        /// `iIsP2PSupport = 0` 的老房不支持 slice（官方走 FLV 直链）。
        public var iIsP2PSupport: Int = 0

        // MARK: FLV 直链字段（保留解析；主路径为 slice，见 HuyaUrl.buildSliceUrl）
        /// e.g. "http://al.flv.huya.com/src"
        public var sFlvUrl: String
        /// 通常为 "flv"
        public var sFlvUrlSuffix: String
        public var sFlvAntiCode: String

        public var flvSuffix: String { sFlvUrlSuffix.isEmpty ? "flv" : sFlvUrlSuffix }

        public init(object: any MarshaledObject) throws {
            sStreamName = try object.value(for: "sStreamName")
            sP2pUrl = try object.value(for: "sP2pUrl")
            sP2pAntiCode = try object.value(for: "sP2pAntiCode")
            sCdnType = (try? object.value(for: "sCdnType")) ?? ""
            iIsHEVCSupport = (try? object.value(for: "iIsHEVCSupport")) ?? 0
            iIsP2PSupport = (try? object.value(for: "iIsP2PSupport")) ?? 0
            sFlvUrl = (try? object.value(for: "sFlvUrl")) ?? ""
            sFlvUrlSuffix = (try? object.value(for: "sFlvUrlSuffix")) ?? ""
            sFlvAntiCode = (try? object.value(for: "sFlvAntiCode")) ?? ""
        }
    }
}

extension String {
    func https() -> String {
        replacingOccurrences(of: "http://", with: "https://")
    }

    /// Page-level bitRate (official page layout, e.g. "bitRate":4000)
    func bitRateValue() -> Int {
        guard let range = range(of: #""bitRate":(\d+)"#, options: .regularExpression),
              let num = self[range].split(separator: ":").last else {
            return 0
        }
        return Int(num) ?? 0
    }
}
