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
		
		guard let convertUid = rotUid(uid),
			  let wsSecret = wsSecret(sFlvAntiCode, convertUid: convertUid, seqid: seqid, streamName: sStreamName) else { return "" }
		
		let newAntiCode: String = {
			var s = sFlvAntiCode.split(separator: "&")
				.filter {
					!$0.contains("fm=") &&
					!$0.contains("wsSecret=")
				}
			s.append("wsSecret=\(wsSecret)")
			return s.joined(separator: "&")
		}()
		
		
		return sFlvUrl.replacingOccurrences(of: "http://", with: "https://")
		+ "/"
		+ sStreamName
		+ "."
		+ sFlvUrlSuffix
		+ "?"
		+ newAntiCode
		+ "&ver=1"
		+ "&seqid=\(seqid)"
		+ "&ratio=0"
		+ "&dMod=mseh-32"
		+ "&sdkPcdn=1_1"
		+ "&u=\(convertUid)"
		+ "&t=100"
		+ "&sv=2401310322"
		+ "&sdk_sid=\(sid)"
		+ "&https=1"
//			+ "&codec=av1"
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
		 
		u = u.replacingOccurrences(of: "$0", with: "\(convertUid)")
		u = u.replacingOccurrences(of: "$1", with: streamName)
		u = u.replacingOccurrences(of: "$2", with: s)
		u = u.replacingOccurrences(of: "$3", with: l)

		return u.md5()
	}
}
