//
//  HuyaUrl.swift
//  HuyaKit
//
//  .slice URL signing (reworked from iina-plus HuyaUrl.format FLV signing).
//  - CryptoSwift: MD5 wsSecret
//

import Foundation
import CryptoSwift

// MARK: - Constants

/// cdnBrand (official D.a.appid, L2579)
let CDN_BRAND = 2
/// appId
let APP_ID = 66

/// codec families (official _getCodec L21395-21398)
let CODEC_FAMILY_H264 = 3
let CODEC_FAMILY_H265 = 2

// MARK: - HuyaUrl

enum HuyaUrl {

    /// Compute wsSecret
    ///
    /// fm template: `DWq8BcJ3h6DJt6TY_$0_$1_$2_$3`
    /// - $0 = streamName
    /// - $1 = wsTime
    /// - $2 = serialId (fixed 0)
    /// - $3 = wsTime
    static func calcWsSecret(fmTemplate: String, streamName: String, wsTime: String) -> String {
        var filled = fmTemplate.replacingOccurrences(of: "$0", with: streamName)
        filled = filled.replacingOccurrences(of: "$1", with: wsTime)
        filled = filled.replacingOccurrences(of: "$2", with: "0")
        filled = filled.replacingOccurrences(of: "$3", with: wsTime)
        let digest = Data(filled.utf8).md5()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Official _getCodec (vplayer.js L21395-21398)
    ///
    /// Maps iBitRate to the codecType used in the URL
    /// - codec_family: 3=H.264, 2=H.265, 1=AV1
    static func getCodec(codecFamily: Int, bitrate: Int) -> Int {
        var i = bitrate
        if i == 0 {
            switch codecFamily {
            case CODEC_FAMILY_H264: i = 0
            case CODEC_FAMILY_H265: i = 2
            default: i = 4 // AV1
            }
        } else if i % 100 == 0 {
            switch codecFamily {
            case CODEC_FAMILY_H264:
                i = i > 8000 ? 1000 + (i / 100) : 400 + (i / 100)
            case CODEC_FAMILY_H265:
                i = i > 8000 ? 4000 + (i / 100) : 500 + (i / 100)
            default:
                i = 9000 + (i / 100)
            }
        } else if i % 10 == 0 {
            switch codecFamily {
            case CODEC_FAMILY_H264:
                i = 20000 + (i / 10)
            case CODEC_FAMILY_H265:
                i = 30000 + (i / 10)
            default:
                i = 40000 + (i / 10)
            }
        }
        return i
    }

    /// Official isH265CodecType (vplayer.js L100082-100084): 1/4/6/8 are H.265
    static func isH265CodecType(_ codecType: Int) -> Bool {
        return codecType == 1 || codecType == 4 || codecType == 6 || codecType == 8
    }

    /// Pick the highest-quality codecType from vMultiStreamInfo
    ///
    /// Official createStreamId (vplayer.js L43841-43858):
    /// - isH265 from top-level codecType
    /// - codecType = _getCodec(isH265 ? 2 : 3, picked entry's iBitRate)
    ///
    /// Page bitRate matches no tier (nominal); using it 404s. `srcBitrate`
    /// is only a fallback when no matching family entry exists.
    static func selectBestCodecType(
        vMultiStreamInfo: [HuyaStream.StreamInfo],
        srcBitrate: Int = 0,
        topCodecType: Int = 0
    ) -> (codecType: Int, codecFamily: Int, displayName: String) {
        if vMultiStreamInfo.isEmpty {
            return (getCodec(codecFamily: CODEC_FAMILY_H264, bitrate: 4000), CODEC_FAMILY_H264, "蓝光4M")
        }

        // official createStreamId logic
        let isH265 = isH265CodecType(topCodecType)
        let family = isH265 ? CODEC_FAMILY_H265 : CODEC_FAMILY_H264
        let picked = vMultiStreamInfo.first { isH265CodecType($0.iCodecType) == isH265 }
        let ct = getCodec(codecFamily: family, bitrate: picked?.iBitRate ?? srcBitrate)
        let displayName = picked?.sDisplayName ?? (isH265 ? "H.265" : "H.264")
        return (ct, family, displayName)
    }

    /// Build the .slice URL
    ///
    /// Official URL format (vplayer.js LoaderMgr.getUrl L18520):
    /// ```
    /// {sP2pUrl}/{streamName}.slice?{antiCode}&ex1=0&dMod=mseh-25&baseIndex=0&quickTime=5000
    /// ```
    /// where `streamName = sStreamName + "_" + codecType + "_" + cdnBrand + "_" + appid`
    ///
    /// antiCode parameter order is significant; kept as an array
    /// (a Dictionary would produce 404s)
    static func buildSliceUrl(
        stream: HuyaStream,
        codecType: Int? = nil
    ) throws -> (url: String, codecType: Int, displayName: String) {
        guard let gsi = stream.primaryStream else {
            throw HuyaError.parseError("no gameStreamInfo in stream data")
        }

        let selected: (codecType: Int, displayName: String)
        if let ct = codecType {
            let displayName = stream.vMultiStreamInfo
                .first { isH265CodecType($0.iCodecType) == isH265CodecType(ct) }?
                .sDisplayName ?? (isH265CodecType(ct) ? "H.265" : "H.264")
            selected = (ct, displayName)
        } else {
            let result = selectBestCodecType(
                vMultiStreamInfo: stream.vMultiStreamInfo,
                srcBitrate: stream.bitRate,
                topCodecType: stream.codecType
            )
            selected = (result.codecType, result.displayName)
        }

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

        let newWsTime = String(Int(Date().timeIntervalSince1970) + 3600, radix: 16)
        let newWsSecret = calcWsSecret(fmTemplate: fmTemplate, streamName: gsi.sStreamName, wsTime: newWsTime)

        // Rebuild antiCode (original order, updated wsSecret/wsTime/ctype)
        var seenKeys: Set<String> = []
        var newAntiParts: [String] = []
        for (k, v) in params {
            let value: String
            switch k {
            case "wsSecret": value = newWsSecret
            case "wsTime": value = newWsTime
            case "ctype": value = "huya_webh5"
            default: value = v
            }
            newAntiParts.append("\(k)=\(value)")
            seenKeys.insert(k)
        }
        // Append params required but missing from the original antiCode
        if !seenKeys.contains("wsSecret") { newAntiParts.append("wsSecret=\(newWsSecret)") }
        if !seenKeys.contains("wsTime") { newAntiParts.append("wsTime=\(newWsTime)") }
        if !seenKeys.contains("ctype") { newAntiParts.append("ctype=huya_webh5") }

        let newAnti = newAntiParts.joined(separator: "&")

        let url = "\(gsi.sP2pUrl.https())/\(gsi.sStreamName)_\(selected.codecType)_\(CDN_BRAND)_\(APP_ID).slice?\(newAnti)"
            + "&ex1=0&dMod=mseh-25&baseIndex=0&quickTime=5000"

        return (url, selected.codecType, selected.displayName)
    }
}
