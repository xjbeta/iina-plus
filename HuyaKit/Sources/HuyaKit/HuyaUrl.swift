//
//  HuyaUrl.swift
//  HuyaKit
//
//  .slice URL 拼装 —— **我们自己的逻辑**。
//  官方移植部分（codecType 翻译 / 签名 / 分片结构 / FLV 重封装）全在 HuyaOfficialPort.swift，
//  上游改版只需改那个文件，本文件不动。
//

import Foundation
import CryptoSwift

// MARK: - Constants

/// appId（官方 `Rr.userInfo.appid`）
let APP_ID = 66

// MARK: - HuyaUrl

enum HuyaUrl {

    /// 自动档（调用方没给档位）该用哪个 codecType：取 `playableStreamInfo` 里**最高的一条第三方可解档**。
    /// `iBitRate == 0` 的原画占位视为最大 rank；私有胶囊档跳过。
    /// 挑不出可解档返回 **nil** 让调用方报错 —— 绝不硬编码兜底、绝不静默降档（MEMORY.md §4.2）。
    static func selectBestCodecType(
        stream: HuyaStream
    ) -> (codecType: Int, codecFamily: Int, displayName: String)? {
        let support = stream.primaryStream?.iIsHEVCSupport ?? 0
        var best: (codecType: Int, codecFamily: Int, displayName: String)?
        var bestRank = Int.min
        for entry in stream.playableStreamInfo {
            let isH265 = HuyaOfficialCodec.isH265Gear(
                iBitRate: entry.iBitRate,
                iCodecType: entry.iCodecType,
                iHEVCBitRate: entry.iHEVCBitRate,
                isHEVCSupport: support
            )
            let family = isH265 ? HuyaOfficialCodec.familyH265 : HuyaOfficialCodec.familyH264
            let ct = HuyaOfficialCodec.getCodec(codecFamily: family, bitrate: entry.iBitRate)
            guard ct != HuyaOfficialCodec.h265Capsule else { continue }
            let rank = entry.iBitRate == 0 ? Int.max : entry.iBitRate
            if rank > bestRank {
                bestRank = rank
                best = (ct, family, entry.sDisplayName)
            }
        }
        return best
    }

    /// 拼 `.slice` URL
    ///
    /// 官方形状（**权威拼接在 `pcore`**，搜 `hxtype`）：
    /// `{sP2pUrl}/{sStreamName}_{codecType}_{cdnBrand}_{appid}.slice?{antiCode}&ex1=…&dMod=…&hxtype=0&baseIndex=n`
    /// - `cdnBrand = iIsP2PSupport > 1 ? iIsP2PSupport : 0`（**线路相关值，不是常量**）
    /// - `antiCode` 按页面参数**原顺序**重建并塞入 `wsSecret`/`wsTime`/`seqid`（顺序有意义 ⇒ 用数组，字典会 404）
    /// - 我们另加 `&quickTime=5000`；不发 `hxtype`
    ///
    /// `codecType` 必填：调用方先从 `stream.playableStreamInfo` 翻译好再传进来，这里不兜底挑档。
    static func buildSliceUrl(
        stream: HuyaStream,
        codecType: Int,
        officialParams: Bool = false
    ) throws -> (url: String, codecType: Int, displayName: String) {
        guard let gsi = stream.primaryStream else {
            throw HuyaError.parseError("no gameStreamInfo in stream data")
        }

        // 显示名按**逐档反查**精确匹配：哪个档算出来的 codecType 等于 codecType，就用它的名字
        // （不能只按 isH265CodecType 粗筛，同族多个档会取错名字）
        let matched = stream.playableStreamInfo.first { entry in
            let isH265 = HuyaOfficialCodec.isH265Gear(
                iBitRate: entry.iBitRate,
                iCodecType: entry.iCodecType,
                iHEVCBitRate: entry.iHEVCBitRate,
                isHEVCSupport: gsi.iIsHEVCSupport
            )
            let family = isH265 ? HuyaOfficialCodec.familyH265 : HuyaOfficialCodec.familyH264
            return HuyaOfficialCodec.getCodec(codecFamily: family, bitrate: entry.iBitRate) == codecType
        }
        // 反查不到（如私有胶囊档退回的同名 H.264 codecType）只影响显示名
        let displayName = matched?.sDisplayName
            ?? (HuyaOfficialCodec.isH265CodecType(codecType) ? "H.265" : "H.264")

        // Parse antiCode (keep original parameter order)
        var params: [(String, String)] = []
        var paramDict: [String: String] = [:]
        for pair in gsi.sP2pAntiCode.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let k = String(kv[0])
                let v = String(kv[1])
                params.append((k, v))
                paramDict[k] = v
            }
        }

        // Compute wsSecret
        let fm = paramDict["fm"] ?? ""
        let fmDecoded = fm.removingPercentEncoding ?? fm
        let fmTemplate: String
        if let data = Data(base64Encoded: fmDecoded), let s = String(data: data, encoding: .utf8) {
            fmTemplate = s
        } else {
            fmTemplate = fmDecoded
        }

        // cdnBrand 是线路相关值（官方 `createStreamId` 首行 `e = e > 1 ? e : 0`）；实测 0/1 直接连不上
        let cdnBrand = gsi.iIsP2PSupport > 1 ? gsi.iIsP2PSupport : 0

        let newWsTime = String(Int(Date().timeIntervalSince1970) + 3600, radix: 16)
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let seqid = HuyaOfficialSign.guestUid + nowMs
        let newWsSecret = HuyaOfficialSign.calcWsSecret(
            fmTemplate: fmTemplate,
            streamName: gsi.sStreamName,
            wsTime: newWsTime,
            nowMs: nowMs
        )

        // Rebuild antiCode (original order, updated wsSecret/wsTime/ctype)
        var seenKeys: Set<String> = []
        var newAntiParts: [String] = []
        for (k, v) in params {
            let value: String
            switch k {
            case "wsSecret": value = newWsSecret
            case "wsTime": value = newWsTime
            case "ctype": value = HuyaOfficialSign.ctype
            default: value = v
            }
            newAntiParts.append("\(k)=\(value)")
            seenKeys.insert(k)
        }
        // Append params required but missing from the original antiCode
        if !seenKeys.contains("wsSecret") { newAntiParts.append("wsSecret=\(newWsSecret)") }
        if !seenKeys.contains("wsTime") { newAntiParts.append("wsTime=\(newWsTime)") }
        if !seenKeys.contains("ctype") { newAntiParts.append("ctype=\(HuyaOfficialSign.ctype)") }
        // 官方 getAnticode 会把 seqid 一并放进 anticode
        if !seenKeys.contains("seqid") { newAntiParts.append("seqid=\(seqid)") }

        let newAnti = newAntiParts.joined(separator: "&")

        // `officialParams`：当年为让 CDN 下发超分私有胶囊而试的官方参数变体，方向已废弃（MEMORY.md §4.3），
        // 当前无调用方传 true，保留作将来若要再试的钩子。
        var extra = "&ex1=0&dMod=mseh-25&baseIndex=0&quickTime=5000"
        if officialParams {
            let seqidForOfficial = "\(Int(Date().timeIntervalSince1970 * 1000))000"
            extra = "&ex1=0&dMod=mseh-57&baseIndex=0&quickTime=5000&seqid=\(seqidForOfficial)&ver=1&hxtype=0"
        }

        let url = "\(gsi.sP2pUrl.https())/\(gsi.sStreamName)_\(codecType)_\(cdnBrand)_\(APP_ID).slice?\(newAnti)\(extra)"

        return (url, codecType, displayName)
    }
}
