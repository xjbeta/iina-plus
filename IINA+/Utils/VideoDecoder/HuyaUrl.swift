//
//  HuyaUrl.swift
//  IINA+
//
//  Created by xjbeta on 2024/2/11.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

class HuyaUrl: NSObject {
    
    static func format(_ uid: Int,
                       sStreamName: String,
                       sFlvUrl: String,
                       sFlvUrlSuffix: String,
                       sFlvAntiCode: String) -> String {
        
        func now() -> Int {
            Int(Date().timeIntervalSince1970 * 1000)
        }
        
        let sid = now()
        
        var antiCodes = antiCodeDic(sFlvAntiCode)
        
        let seqid = uid + now()
        
        guard let convertUid = rotUid(uid),
              let wsSecret = wsSecret(antiCodes, convertUid: convertUid, seqid: seqid, streamName: sStreamName) else { return "" }
        
        antiCodes["u"] = "\(convertUid)"
        antiCodes["wsSecret"] = wsSecret
        
        antiCodes["seqid"] = "\(seqid)"
        antiCodes["sdk_sid"] = "\(sid)"
        
        antiCodes["ratio"] = "0"
        
        let example = "https://tx.flv.huya.com/huyalive/1099531627955-1099531627955-85900114719145984-2199063379366-10057-A-0-1.flv?wsSecret=42a9adedc7011adc1dbc20628eaa503f&wsTime=67b6c60d&seqid=1742352165582&ctype=huya_live&ver=1&fs=bgct&ratio=2000&dMod=mseh-8&sdkPcdn=1_1&u=1451203978&t=100&sv=2407051433&sdk_sid=1740031240996&a_block=0&sf=1"
        
        
        var url = sFlvUrl.https()
        + "/"
        + sStreamName
        + "."
        + sFlvUrlSuffix
        + "?"
        
        let pars = URLComponents(string: example)!.queryItems!.compactMap {
            let key = $0.name
            let newValue = antiCodes[key] ?? $0.value
            if let newValue {
                return key + "=" + newValue
            } else {
                Log("Huya parameters missing value, \($0.description)")
                return nil
            }
        }
        
        url += pars.joined(separator: "&")
        
        return url
    }
    
    private static func turnStr(_ e: Int, _ t: Int, _ i: Int) -> String {
        var s = String(e, radix: t)
        while s.count < i {
            s = "0" + s
        }
        return s
    }
    
    private static func rotUid(_ t: Int) -> Int? {
        let i = 8
        
        let s = turnStr(t, 2, 64)
        let si = s.index(s.startIndex, offsetBy: 32)
        let a = s[s.startIndex..<si]
        let r = s[si..<s.endIndex]
        
        let ri = r.index(r.startIndex, offsetBy: i)
        let n1 = r[ri..<r.index(ri, offsetBy: 32 - i)]
        let n2 = r[r.startIndex..<ri]
        
        let n = n1 + n2
        
        return Int(a + n, radix: 2)
    }
    
    private static func wsSecret(_ antiCodes: [String: String],
                                 convertUid: Int,
                                 seqid: Int,
                                 streamName: String) -> String? {
        guard var u = antiCodes["fm"]?.removingPercentEncoding?.base64Decode(),
              let l = antiCodes["wsTime"],
              let ctype = antiCodes["ctype"] else { return nil }
        let t = antiCodes["t"] ?? "100"
        let s = "\(seqid)|\(ctype)|\(t)".md5()
        
        //		let o = this[Mt].replace(Xt, r).replace($t, this[Kt]).replace(Zt, s).replace(te, this[Bt]);
        u = u.replacingOccurrences(of: "$0", with: "\(convertUid)")
        u = u.replacingOccurrences(of: "$1", with: streamName)
        u = u.replacingOccurrences(of: "$2", with: s)
        u = u.replacingOccurrences(of: "$3", with: l)
        
        return u.md5()
    }
    
    private static func antiCodeDic(_ antiCode: String) -> [String: String] {
        var dic = [String: String]()
        
        antiCode.split(separator: "&").map {
            $0.split(separator: "=", maxSplits: 1).map(String.init)
        }.filter {
            $0.count == 2
        }.forEach {
            dic[$0[0]] = $0[1]
        }
        return dic
    }
}

