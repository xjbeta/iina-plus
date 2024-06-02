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
		
		var parameters = [String: String]()
		
		sFlvAntiCode.split(separator: "&").map {
			$0.split(separator: "=", maxSplits: 1).map(String.init)
		}.filter {
			$0.count == 2
		}.forEach {
			parameters[$0[0]] = $0[1]
		}
		
		// (seqid - uid) > sid
		let seqid = uid + now()
		
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
		
		let example = "https://hw.flv.huya.com/src/1394575534-1394575534-5989656310331736064-2789274524-10057-A-0-1.flv?wsSecret=4b1ac7c8b5b3792b756f419bd6db09f8&wsTime=665aeff5&seqid=1750435781966&ctype=huya_webh5&ver=1&txyp=o%3An4%3B&fs=bgct&sphdcdn=al_7-tx_3-js_3-ws_7-bd_2-hw_2&sphdDC=huya&sphd=264_*-265_*&exsphd=264_500,264_2000,264_4000,264_6000,264_8000,&ratio=2000&dMod=mseh-32&sdkPcdn=1_1&u=33818100666&t=100&sv=2405220949&sdk_sid=1717235700093&a_block=0"
		
		var url = sFlvUrl.https()
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
		
		guard var u = d["fm"]?.removingPercentEncoding?.base64Decode(),
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
