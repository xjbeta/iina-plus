//
//  BilibiliDash.swift
//  IINA+
//
//  Created by xjbeta on 2024/7/23.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa
import Marshal

struct BilibiliDash: Unmarshaling {
	
	var duration: Int
	var minBufferTime: Double
	let video: [AVObject]
	let audio: [AVObject]
	
	init(object: MarshaledObject) throws {
		duration = try object.value(for: "duration")
		minBufferTime = try object.value(for: "minBufferTime")
		video = try object.value(for: "video")
		audio = (try? object.value(for: "audio")) ?? []
	}
	
	
	struct AVObject: Unmarshaling {
		var index = -1
		var description: String = ""
		
		let id: Int
		let url: String
		let backupUrl: [String]
		let bandwidth: Int
		let mimeType: String
		let codecs: String
		let width: Int
		let height: Int
		let frameRate: String
//		let sar: String
		let startWithSap: Int
		let segmentBase: SegmentBase
		
		init(object: MarshaledObject) throws {
			id = try object.value(for: "id")
			bandwidth = try object.value(for: "bandwidth")
			mimeType = try object.value(for: ["mimeType", "mime_type"])
			codecs = try object.value(for: "codecs")
			width = try object.value(for: "width")
			height = try object.value(for: "height")
			frameRate = try object.value(for: ["frameRate", "frame_rate"])
//			sar = try object.value(for: "sar")
				
			startWithSap = try object.value(for: ["startWithSap", "start_with_sap", "startWithSAP"])
			segmentBase = try object.value(for: ["SegmentBase", "segment_base"])
//			["SegmentBase", "segment_base"]
			
			
			var urls = [String]()
			urls.append(try object.value(for: ["baseUrl", "base_url"]))
			urls.append(contentsOf: (try? object.value(for: ["backupUrl", "backup_url"])) ?? [])
			urls = MBGA.update(urls)
			
			guard urls.count > 0 else {
				throw VideoGetError.invalidLink
			}
			
			url = urls.removeFirst()
			backupUrl = urls
		}
		
		struct SegmentBase: Unmarshaling {
			let initialization: String
			let indexRange: String
			
			init(object: MarshaledObject) throws {
				initialization = try object.value(for: "Initialization")
				indexRange = try object.value(for: "indexRange")
			}
		}
		
		func adaptationSet(forAudio: Bool = false) -> XMLElement {
//			Video
//			<AdaptationSet mimeType="video/mp4" startWithSAP="1" segmentAlignment="true" scanType="progressive">
			
//			Audio
//			<AdaptationSet mimeType="audio/mp4" startWithSAP="1" segmentAlignment="true" lang="und">
					
			let attributes = {
				var attr = [
					"mimeType": mimeType,
					"startWithSAP": startWithSap.description,
					"segmentAlignment": "true"
				]
				if forAudio {
					attr["scanType"] = "progressive"
					
				} else {
					attr["lang"] = "und"
				}
				return attr
			}()
			
			return XMLElement(
				name: "AdaptationSet",
				attributes: attributes
			)
		}
		
		func representation(forAudio: Bool = false) -> XMLElement {
//			Video
//			<Representation bandwidth="1123209" codecs="avc1.640032" frameRate="30.303" height="1080" id="80" width="1920">
//			  <BaseURL>https://....</BaseURL>
//			  <SegmentBase indexRange="997-4928">
//				<Initialization range="0-996"></Initialization>
//			  </SegmentBase>
//			</Representation>
			
//			Audio
//			<Representation audioSamplingRate="44100" bandwidth="127661" codecs="mp4a.40.2" id="30280">
//			  <BaseURL>https://....</BaseURL>
//			  <SegmentBase indexRange="934-4877">
//				<Initialization range="0-933"></Initialization>
//			  </SegmentBase>
//			</Representation>
			
			
			let attributes = {
				if forAudio {
					[
						"id": id.description,
						"audioSamplingRate": "44100",
						"bandwidth": bandwidth.description,
						"codecs": codecs
					]
				} else {
					[
						"id": id.description,
						"bandwidth": bandwidth.description,
						"codecs": codecs,
						"frameRate": frameRate,
						"height": height.description,
						"width": width.description
					]
				}
			}()
			
			
			let representationElement = XMLElement(
				name: "Representation",
				attributes: attributes
			)
			
			let baseURLElement = XMLElement(
				name: "BaseURL",
				stringValue: url.replacingOccurrences(of: "&", with: "&amp;")
			)
			
			representationElement.addChild(baseURLElement)
			
			let segmentBaseElement = XMLElement(
				name: "SegmentBase",
				attributes: ["indexRange": segmentBase.indexRange]
			)
			segmentBaseElement.addChild(XMLElement(
				name: "Initialization",
				attributes: ["range": segmentBase.initialization])
			)
			
			representationElement.addChild(segmentBaseElement)
			
			return representationElement
		}
	}
	
	
	func dashContent(_ id: Int) -> String? {
		dashXML(id)?.xmlString(options: .documentTidyXML)
	}
	
	func dashXML(_ id: Int) -> XMLDocument? {
		let xmlDocument = XMLDocument(rootElement: nil)
		xmlDocument.version = "1.0"
		xmlDocument.characterEncoding = "UTF-8"
		
		//	<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" type="static" mediaPresentationDuration="PT1628S" minBufferTime="PT1.500000S">
		let rootElement = XMLElement(
			name: "MPD",
			attributes: [
				"xmlns": "urn:mpeg:dash:schema:mpd:2011",
				"profiles": "urn:mpeg:dash:profile:isoff-on-demand:2011",
				"type": "static",
				"mediaPresentationDuration": "PT\(duration)S",
				"minBufferTime": "PT\(minBufferTime)S"
			])
		xmlDocument.setRootElement(rootElement)
		
		let periodElement = XMLElement(name: "Period")
		rootElement.addChild(periodElement)
		
		let adaptationSets = adaptationSets(id)
		guard adaptationSets.count > 0 else { return nil }
		
		adaptationSets.forEach {
			periodElement.addChild($0)
		}
		
		return xmlDocument
	}
	
	func preferVideo(_ id: Int) -> AVObject? {
		let preferVideos = video.filter {
			switch Preferences.shared.bilibiliCodec {
			case 0:
				return $0.codecs.starts(with: "av01") || $0.codecs.starts(with: "av1")
			case 1:
				return $0.codecs.starts(with: "hev")
			default:
				return $0.codecs.starts(with: "avc")
			}
		}
		
		let video = preferVideos.first {
			$0.id == id
		} ?? video.filter {
			$0.id == id
		}.first {
			$0.codecs.starts(with: "avc") ||
			$0.codecs.starts(with: "hev") ||
			$0.codecs.starts(with: "av01") ||
			$0.codecs.starts(with: "av1")
		}
		
		return video
	}
	
	func preferAudio() -> AVObject? {
		audio.max(by: { $0.bandwidth > $1.bandwidth })
	}

	private func adaptationSets(_ id: Int) -> [XMLElement] {
		var re = [XMLElement]()
		
		guard let video = preferVideo(id) else {
			return re
		}
		
		let videoAdaptationSet = video.adaptationSet()
		videoAdaptationSet.addChild(video.representation())
		re.append(videoAdaptationSet)
		
		guard let audio = preferAudio() else {
			return re
		}
		
		let audioAdaptationSet = audio.adaptationSet(forAudio: true)
		audioAdaptationSet.addChild(audio.representation(forAudio: true))
		re.append(audioAdaptationSet)
		
		return re
	}

}

extension XMLElement {
	convenience init(name: String, attributes: [String: String]) {
		self.init(name: name)
		self.setAttributesWith(attributes)
	}
}

extension MarshaledObject {
	func value<A: ValueType>(for keys: [KeyType]) throws -> A {
		for key in keys {
			if let any = self.optionalAny(for: key),
			   let re = try? A.value(from: any) as? A {
				return re
			}
		}
		throw MarshalError.keyNotFound(key: keys.map({ $0.stringValue }).joined(separator: "|"))
	}
	
	func value<A: ValueType>(for keys: [KeyType], discardingErrors: Bool = false) throws -> [A] {
		for key in keys {
			if let any = self.optionalAny(for: key),
			   let re = try? Array<A>.value(from: any, discardingErrors: discardingErrors) {
				return re
			}
		}
		throw MarshalError.keyNotFound(key: keys.map({ $0.stringValue }).joined(separator: "|"))
	}
}
