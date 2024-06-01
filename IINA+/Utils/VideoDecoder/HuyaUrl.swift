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
	
		let seqid = uid + now()
		let sid = now()
		var parameters = [String: String]()
		
		sFlvAntiCode.split(separator: "&").map {
			$0.split(separator: "=", maxSplits: 1).map(String.init)
		}.filter {
			$0.count == 2
		}.forEach {
			parameters[$0[0]] = $0[1]
		}
		
		guard let convertUid = rotUid(uid),
			  let wsSecret = wsSecret(sFlvAntiCode, convertUid: convertUid, seqid: seqid, streamName: sStreamName) else { return "" }
		
		parameters["u"] = "\(convertUid)"
		parameters["wsSecret"] = wsSecret
		
//		parameters["fm"] = nil
		parameters["seqid"] = "\(seqid)"
		parameters["sdk_sid"] = "\(sid)"
		parameters["sv"] = "2405220949"
		
		parameters["sdkPcdn"] = "1_1"
		parameters["t"] = "100"
		parameters["a_block"] = "0"
		parameters["ver"] = "1"
		parameters["ratio"] = "0"
		parameters["dMod"] = "mseh-32"
		
		let example = "https://qvodlive-va.huya.com/src/1394575534-1394575534-5989656310331736064-2789274524-10057-A-0-1.flv?wsSecret=b9636212d1ad30223c157f5ac678d7c5&wsTime=665aaef2&seqid=7784383132214&ctype=huya_live&ver=1&txyp=o%3An4%3B&fs=bgct&sphdcdn=al_7-tx_3-js_3-ws_7-bd_2-hw_2&sphdDC=huya&sphd=264_*-265_*&exsphd=264_500,264_2000,264_4000,264_6000,264_8000,&ratio=500&&https=1&dMod=mseh-32&sdkPcdn=1_1&u=6065176706463&t=100&sv=2405220949&sdk_sid=1717219065187&a_block=0"
		
		var url = sFlvUrl.replacingOccurrences(of: "http://", with: "https://")
		+ "/"
		+ sStreamName
		+ "."
		+ sFlvUrlSuffix
		+ "?"
		
		let pars = URLComponents(string: example)!.queryItems!.compactMap {
			let key = $0.name
			if let value = parameters[key] {
				return key + "=" + value
			} else {
				Log("Huya parameters missing key, \($0.description)")
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
	
	private static func wsSecret(_ antiCode: String,
						  convertUid: Int,
						  seqid: Int,
						  streamName: String) -> String? {
		
		let d = antiCode.components(separatedBy: "&").reduce([String: String]()) { (re, str) -> [String: String] in
			var r = re
			let kv = str.components(separatedBy: "=")
			guard kv.count == 2 else { return r }
			r[kv[0]] = kv[1]
			return r
		}
		
		guard let fm = d["fm"]?.removingPercentEncoding,
			  let fmData = Data(base64Encoded: fm),
			  var u = String(data: fmData, encoding: .utf8),
			  let l = d["wsTime"],
			  let ctype = d["ctype"] else { return nil }
		
		let s = "\(seqid)|\(ctype)|100".md5()
		
//		let o = this[Mt].replace(Xt, r).replace($t, this[Kt]).replace(Zt, s).replace(te, this[Bt]);
		u = u.replacingOccurrences(of: "$0", with: "\(convertUid)")
		u = u.replacingOccurrences(of: "$1", with: streamName)
		u = u.replacingOccurrences(of: "$2", with: s)
		u = u.replacingOccurrences(of: "$3", with: l)

		return u.md5()
	}
}
