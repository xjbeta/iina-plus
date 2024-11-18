//
//  Danmaku.swift
//  iina+
//
//  Created by xjbeta on 2018/10/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Marshal
import SocketRocket
import Gzip
@preconcurrency import JavaScriptCore
import CryptoSwift
import Marshal
import SDWebImage

protocol DanmakuDelegate {
    @MainActor func send(_ event: DanmakuEvent, sender: Danmaku)
}

protocol DanmakuSubDelegate {
    @MainActor func send(_ event: DanmakuEvent)
}

@MainActor
class Danmaku: NSObject {
    var socket: SRWebSocket? = nil
    var liveSite: SupportSites = .unsupported
    var url = ""
    var id = ""
    var delegate: DanmakuDelegate?
    
    private var heartBeatCount = 0
    
    let biliLiveServer = URL(string: "wss://broadcastlv.chat.bilibili.com:443/sub")
	var biliLiveIDs = (rid: "", token: "", uid: 1)
    var bililiveEmoticons = [BiliLiveEmoticon]()
    
    let douyuBlockList = [
        "#挑战666#",
        "#签到",
        "#超管来了#",
        "#让火箭飞#",
        "#消消乐#"
    ]
    
    let douyuServer = URL(string: "wss://danmuproxy.douyu.com:8506")
    var douyuRoomID = ""
    var douyuSavedData = Data()
    
    let huyaBlockList = [
        "分享了直播间，房间号",
        "录制并分享了小视频",
        "进入直播间",
        "刚刚在打赏君活动中",
        "竟然抽出了",
        "车队召集令在此",
        "微信公众号“虎牙志愿者”",
    ]
    let huyaServer = URL(string: "wss://wsapi.huya.com")
    var huyaAnchorUid = -1
    let huyaJSContext = JSContext()
    
    struct HuYaDanmuMsg: Decodable {
        let ePushType: Int
        let iUri: Int
        let sMsg: String
        let iProtocolType: Int
        let sGroupId: String
        let lMsgId: String
    }

    let cc163Server = URL(string: "wss://weblink.cc.163.com")
    
    var socketClosed = false
    
    var douyinDM: DouYinDM?
    
    
    init(_ url: String) {
        liveSite = .init(url: url)
        self.url = url
        
        switch liveSite {
        case .huya:
            if let huyaFilePath = Bundle.main.path(forResource: "huya", ofType: "js") {
                huyaJSContext?.evaluateScript(try? String(contentsOfFile: huyaFilePath))
            } else {
                Log("Not found huya.js.")
            }
        default:
            break
        }
    }
    
    func stop() {
		Log("Stop Danmaku")
		
        socket?.close()
        socket = nil
        timer?.cancel()
        douyuSavedData = Data()
        heartBeatCount = 0
        
		Task {
			douyinDM?.stop()
			douyinDM = nil
		}
    }

	func loadDM() {
		Task {
			do {
				try await loadDanmaku()
			} catch let error {
				Log("loadDM failed, \(error)")
			}
		}
	}
	
    
    func loadDanmaku() async throws {
        guard let url = URL(string: self.url) else { return }
        let roomID = url.lastPathComponent
        let videoDecoder = Processes.shared.videoDecoder
        switch liveSite {
        case .biliLive:

			let rid = try await self.bililiveRid(roomID)
			let token = try await bililiveToken(rid)
			let emoticons = try await bililiveEmoticons(rid)
			let uid = try await Bilibili().getUid()
			
			await MainActor.run {
				biliLiveIDs.rid = rid
				biliLiveIDs.token = token
				bililiveEmoticons = emoticons
				biliLiveIDs.uid = uid
				socket = .init(url: biliLiveServer!)
				socket?.delegate = self
				socket?.open()
			}
        case .douyu:
            
            Log("Processes.shared.videoDecoder.getDouyuHtml")
			
			let info = try await videoDecoder.douyu.getDouyuHtml(url.absoluteString)
            initDouYuSocket(info.roomId)
			
        case .huya:
			let str = try await AF.request(url.absoluteString).serializingString().value
			let js = str.subString(from: "var TT_ROOM_DATA = ", to: "};")
			let roomData = (js + "}").data(using: .utf8) ?? Data()
			let roomInfo: JSONObject = try JSONParser.JSONObjectWithData(roomData)

			try await MainActor.run {
				if let id: String = try? roomInfo.value(for: "id"),
					let uid = Int(id) {
					self.huyaAnchorUid = uid
				} else {
					self.huyaAnchorUid = try roomInfo.value(for: "id")
				}
				
				self.socket = .init(url: self.huyaServer!)
				self.socket?.delegate = self
				self.socket?.open()
			}

        case .douyin:
			await MainActor.run {
				douyinDM = .init()
				douyinDM?.requestPrepared = { ur in
					self.socket = .init(urlRequest: ur)
					self.socket?.delegate = self
					self.socket?.open()
				}
				douyinDM?.start(self.url)
				socketClosed = false
				startTimer()
			}
        default:
            break
        }
    }
    
    func sendMsg(_ data: Data) {
        do {
            try socket?.send(data: data)
        } catch let error {
            Log("sendMsg error \(error)")
        }
    }
    
    private func sendDM(_ event: DanmakuEvent) {
        if event.method == .sendDM,
           let dms = event.dms,
           dms.count == 0 {
            return
        }
        delegate?.send(event, sender: self)
    }
    
    private func initDouYuSocket(_ roomID: String) {
        Log("initDouYuSocket")
        douyuRoomID = roomID
        socket = .init(url: self.douyuServer!)
        socket?.delegate = self
        socket?.open()
    }
    
    private func douyuSocketFormatter(_ str: String) -> Data {
        let str = str + "\0"
        let data = pack(format: "VVV", values: [str.count + 8, str.count + 8, 689])
        data.append(str.data(using: .utf8) ?? Data())
        return data as Data
    }
    
    
    private var timer: DispatchSourceTimer?
    
    private let timerQueue = DispatchQueue(label: "com.xjbeta.iina+.WebSocketKeepLive")
    
    private func startTimer() {
        timer?.cancel()
        timer = nil
        timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        guard let timer = timer else {
            return
        }
        
        let interval: DispatchTimeInterval = liveSite == .douyin ? .seconds(15) : .seconds(30)
        
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler {
            do {
                switch self.liveSite {
                case .biliLive:
                    let data = self.pack(format: "NnnNN", values: [16, 16, 1, 2, 1]) as Data
                    try self.socket?.send(data: data)
                case .douyu:
                    //                        let keeplive = "type@=keeplive/tick@=\(Int(Date().timeIntervalSince1970))/"
                    let keeplive = "type@=mrkl/"
                    let data = self.douyuSocketFormatter(keeplive)
                    try self.socket?.send(data: data)
                case .huya:
                    let result = self.huyaJSContext?.evaluateScript("new Uint8Array(sendHeartBeat());")
                    let data = Data(result?.toArray() as? [UInt8] ?? [])
                    self.sendMsg(data)
                    
                case .douyin:
                    guard let socket = self.socket else { return }
                    if self.socketClosed {
                        Log("Reconnect douyin dm")
                        self.stop()
                        self.loadDM()
                        return
                    }
                    var pf = DouYinPushFrame()
                    pf.payloadType = "hb"
                    try socket.sendPing(pf.serializedData())
                default:
                    try self.socket?.sendPing(Data())
                }
                self.heartBeatCount += 1
                if self.heartBeatCount > 5 {
                    self.stop()
                    self.loadDM()
                    Log("HeartBeatCount exceed, restart.")
                }
            } catch let error {
                if (error as NSError).code == 2134 {
                    self.stop()
                    self.loadDM()
                    Log("Danmaku Error 2134, restart.")
                } else {
                    Log(error)
                }
            }
        }
        timer.resume()
    }
    
}


extension Danmaku: SRWebSocketDelegate {
    func webSocketDidOpen(_ webSocket: SRWebSocket) {
        Log("webSocketDidOpen")

        switch liveSite {
        case .biliLive:
			let buvid = UUID().uuidString + "\(Int.random(in: 10000...90000))" + "infoc"
			let key = biliLiveIDs.token
			
			let json = "{\"uid\":\(biliLiveIDs.uid),\"roomid\":\(biliLiveIDs.rid),\"protover\":2,\"buvid\":\"\(buvid)\",\"platform\":\"web\",\"type\":2,\"key\":\"\(key)\"}"
						
            //0000 0060 0010 0001 0000 0007 0000 0001
            let data = pack(format: "NnnNN", values: [json.count + 16, 16, 1, 7, 1])
            data.append(json.data(using: .utf8)!)
            sendMsg(data as Data)
            startTimer()
        case .huya:
            let id = huyaAnchorUid
            let result = huyaJSContext?.evaluateScript("""
new Uint8Array(sendRegisterGroups(["live:\(id)", "chat:\(id)"]));
""")

            let data = Data(result?.toArray() as? [UInt8] ?? [])
            sendMsg(data)
            startTimer()
        case .douyu:
            let loginreq = "type@=loginreq/roomid@=\(douyuRoomID)/"
            let joingroup = "type@=joingroup/rid@=\(douyuRoomID)/gid@=-9999/"


            sendMsg(douyuSocketFormatter(loginreq))
            sendMsg(douyuSocketFormatter(joingroup))
            startTimer()
        default:
            break
        }
    }
    
    func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        Log("webSocketdidClose \(reason ?? "")")
        switch liveSite {
        case .biliLive:
            timer?.cancel()
            timer = nil
        case .douyin:
            socketClosed = true
        default:
            break
        }
        delegate?.send(.init(method: .liveDMServer, text: "error"), sender: self)
    }
	
	func webSocket(_ webSocket: SRWebSocket, didReceivePong pongData: Data?) {
		switch liveSite {
		case .douyin:
			guard let data = pongData,
				  let str = String(data: data, encoding: .utf8),
				  str.hasSuffix("hb") else {
				return
			}
			
			heartBeatCount = 0
		default:
			break
		}
	}
    
    func webSocket(_ webSocket: SRWebSocket, didReceiveMessageWith data: Data) {
        switch liveSite {
        case .biliLive:
            //            0000 0234
            //            0-4 json length + head
            if data.count == 20 {
                Log("Danmaku HeartBeatRsp")
                heartBeatCount = 0
                return
            } else if data.count == 26 {
                Log("bililive connect success")
                self.delegate?.send(.init(method: .liveDMServer, text: ""), sender: self)
                return
            }
            
            func checkIntegrity(_ data: Data) -> Data? {
                var d = data
                let head = d.subdata(in: 0..<4)
                let count = Int(CFSwapInt32(head.withUnsafeBytes { $0.load(as: UInt32.self) }))
                guard count == data.count else {
                    Log("BiliLive Checking for integrity failed.")
                    return nil
                }
                d = d.subdata(in: 16..<count)
				
                do {
					return try d.gunzipped()
                } catch let error {
                    if let str = String(data: data, encoding: .utf8), str.contains("cmd") {
                        return nil
                    } else if let str = String(data: d, encoding: .utf8), str.contains("cmd") {
                        return nil
                    } else {
                        Log("decode bililive msg error \(error)")
                    }
                }
                return nil
            }
			
            
            var datas: [Data] = []
            guard var d = checkIntegrity(data) else { return }
            while d.count > 20 {
                let head = d.subdata(in: 0..<4)
                let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { $0.load(as: UInt32.self) }))
                if endIndex <= d.endIndex {
                    datas.append(d.subdata(in: 16..<endIndex))
                    d = d.subdata(in: endIndex..<d.endIndex)
                } else {
                    d.removeAll()
                }
            }
            
            let dms = try? datas.compactMap(decodeBiliLiveDM(_:))
            if let dms, dms.count > 0 {
                sendDM(.init(method: .sendDM, text: "", dms: dms))
            }
        case .huya:
            let bytes = [UInt8](data)
            guard let re = huyaJSContext?.evaluateScript("test(\(bytes));"),
                  re.isString,
                  let str = re.toString() else {
                return
            }
            
            if str == "EWebSocketCommandType.EWSCmdS2C_RegisterGroupRsp" {
                Log("huya connect success")
                self.delegate?.send(.init(method: .liveDMServer, text: ""), sender: self)
                return
            } else if str.starts(with: "EWebSocketCommandType") {
                guard str != "EWebSocketCommandType.EWSCmdS2C_MsgPushReq_V2" else { return }
                Log("huya websocket info \(str)")
                return
            } else if str == "EWebSocketCommandType.EWSCmdS2C_HeartBeatRsp" {
                Log("Danmaku HeartBeatRsp")
                heartBeatCount = 0
                return
            }
            
            guard let data = str.data(using: .utf8),
                  let msg = try? JSONDecoder().decode(HuYaDanmuMsg.self, from: data) else {
                      Log("huya msg unknown \(str)")
                      return
                  }
            
            if msg.ePushType == 5,
               msg.iUri == 1400,
               msg.iProtocolType == 2,
               !huyaBlockList.contains(where: msg.sMsg.contains) {
                let dm = DanmakuComment(text: msg.sMsg)
                sendDM(.init(method: .sendDM, text: "", dms: [dm]))
            }
            
            
            
            //            "/{dx" = "[大笑]",  😆
            //            "/{sh" = "[送花]",  🌹
            //            "/{tx" = "[偷笑]",  🙂
            //            "/{dk" = "[大哭]",  😭
            //            "/{hh" = "[嘿哈]",  😁
            //            "/{66" = "[666]"},  666
            //            "/{gd" = "[感动]",  😹
            //            "/{yw" = "[疑问]",  🤔️
            //            "/{xh" = "[喜欢]",  😍
            //            "/{jx" = "[奸笑]",  😏
            //            "/{zan" = "[赞]",  👍
            //            "/{ka" = "[可爱]",  😋
            //            "/{am" = "[傲慢]",  🧐
            //            "/{kx" = "[开心]",  😀
            //            "/{88" = "[拜拜]",  👋
            //            "/{hx" = "[害羞]",  😳
            //            "/{zs" = "[衰]",  😱
            //            "/{pu" = "[吐血]",
            //            "/{zc" = "[嘴馋]",  😋
            //            "/{sq" = "[生气]",  😠
            //            "/{fe" = "[扶额]",
            //            "/{bz" = "[闭嘴]",  🤐
            //            "/{kw" = "[枯萎]",  🥀
            //            "/{xu" = "[嘘]",  🤫
            //            "/{xk" = "[笑哭]",  😂
            //            "/{lh" = "[流汗]",  💦
            //            "/{bk" = "[不看]",  🙈
            //            "/{hq" = "[哈欠]",
            //            "/{tp" = "[调皮]",  😝
            //            "/{gl" = "[鬼脸]",  😜
            //            "/{cl" = "[戳脸]",
            //            "/{dg" = "[大哥]",
            //            "/{kun" = "[困]",
            //            "/{yb" = "[拥抱]",
            //            "/{zt" = "[猪头]",  🐷
            //            "/{kl" = "[骷髅]",  ☠️
            //            "/{cc" = "[臭臭]",
            //            "/{xd" = "[心动]",
            //            "/{dao" = "[刀]",  🔪
            //            "/{wx" = "[微笑]",
            //            "/{ll" = "[流泪]",
            //            "/{dy" = "[得意]",
            //            "/{jy" = "[惊讶]",
            //            "/{pz" = "[撇嘴]",
            //            "/{yun" = "[晕]",
            //            "/{ng" = "[难过]",
            //            "/{se" = "[色]",
            //            "/{cy" = "[抽烟]",
            //            "/{qd" = "[敲打]"},
            //            "/{mg" = "[玫瑰]",
            //            "/{wen" = "[吻]",
            //            "/{xs" = "[心碎]",
            //            "/{zd" = "[*屏蔽的关键字*]",
            //            "/{sj" = "[睡觉]",
            //            "/{hk" = "[很酷]",
            //            "/{by" = "[白眼]",
            //            "/{ot" = "[呕吐]",
            //            "/{fd" = "[奋斗]",
            //            "/{kz" = "[口罩]",
            //            "/{hp" = "[害怕]",
            //            "/{dai" = "[发呆]",
            //            "/{fn" = "[发怒]",
            //            "/{ruo" = "[弱]",
            //            "/{ws" = "[握手]",
            //            "/{sl" = "[胜利]",
            //            "/{lw" = "[礼物]",
            //            "/{sd" = "[闪电]",
            //            "/{gz" = "[鼓掌]",
            //            "/{qq" = "[亲亲]",
            //            "/{kb" = "[抠鼻]",
            //            "/{wq" = "[委屈]",
            //            "/{yx" = "[阴险]",
            //            "/{kel" = "[可怜]",
            //            "/{bs" = "[鄙视]",
            //            "/{zk" = "[抓狂]",
            //            "/{bq" = "[抱拳]",
            //            "/{ok" = "[OK]"
        case .douyu:
            var d = data
            
            if douyuSavedData.count != 0 {
                douyuSavedData.append(d)
                d = douyuSavedData
                douyuSavedData = Data()
            }
            
            var msgDatas: [Data] = []
            
            while d.count > 12 {
                let head = d.subdata(in: 0..<4)
                let endIndex = Int(CFSwapInt32LittleToHost(head.withUnsafeBytes { $0.load(as: UInt32.self) }))
                if d.count < endIndex+2 {
                    douyuSavedData.append(douyuSavedData)
                    d = Data()
                } else {
                    guard endIndex+2 > 12,
                        endIndex+2 < d.endIndex else {
                            Log("endIndex out of range.")
                            return }
                    let msg = d.subdata(in: 12..<endIndex+2)
                    msgDatas.append(msg)
                    d = d.subdata(in: endIndex+2..<d.endIndex)
                }
            }
            
            var dms = [DanmakuComment]()
            
            msgDatas.forEach {
                guard let msg = String(data: $0, encoding: .utf8) else { return }
                if msg.starts(with: "type@=chatmsg") {
					
					if !msg.contains("dms@=") {
						// filter strange dm
						return
					}
					
                    let dm = msg.split(separator: "/").filter {
                        $0.starts(with: "txt@=")
                    }.filter {
                        !douyuBlockList.contains(where: $0.contains)
                    }.first
                    
                    if let dm = dm {
                        dms.append(.init(text: String(dm.dropFirst("txt@=".count))))
                    }
                } else if msg.starts(with: "type@=error") {
                    Log("douyu socket disconnected: \(msg)")
                    self.delegate?.send(.init(method: .liveDMServer, text: "error"), sender: self)
                    socket?.close()
                } else if msg.starts(with: "type@=loginres") {
                    Log("douyu content success")
                    self.delegate?.send(.init(method: .liveDMServer, text: ""), sender: self)
                } else if msg == "type@=mrkl" {
                    Log("Danmaku HeartBeatRsp")
                    heartBeatCount = 0
                }
            }
            

            sendDM(.init(method: .sendDM, text: "", dms: dms))
        case .douyin:
            do {
				let re = try DouYinResponse(serializedBytes: data)
				let ree = try Douyin_Response(serializedBytes: re.data.gunzipped())
                
				let dms = ree.messagesList.filter {
                    $0.method == "WebcastChatMessage"
                }.compactMap {
					try? Douyin_ChatMessage(serializedBytes: $0.payload)
                }.map {
                    DanmakuComment(text: $0.content)
                }
                
                sendDM(.init(method: .sendDM, text: "", dms: dms))
                
                guard ree.needAck else { return }
                
                var pf = DouYinPushFrame()
                pf.payloadType = "ack"
                pf.logid = re.wssPushLogID
                
                let payload: [UInt8] = {
                    var t = [UInt8]()
                    func push(_ e: UInt32) {
                        t.append(UInt8(e))
                    }
                    
                    ree.internalExt.unicodeScalars.forEach {
                        let e = $0.value
                        switch e {
                        case _ where e < 128:
                            push(e)
                        case _ where e < 2048:
                            push(192 + (e >> 6))
                            push(128 + (63 & e))
                        case _ where e < 65536:
                            push(224 + (e >> 12))
                            push(128 + (e >> 6 & 63))
                            push(128 + (63 & e))
                        default:
                            break
                        }
                    }
                    
                    return t
                }()
                
                pf.data = Data(payload)
                
                try? webSocket.send(data: pf.serializedData())
                
            } catch let error {
                Log("\(error)")
            }
            
        default:
            break
        }   
    }
    
    func webSocket(_ webSocket: SRWebSocket, didFailWithError error: Error) {
        Log(error)

		let err = error as NSError
		
		if err.domain == SRWebSocketErrorDomain,
		err.code == 2133,
		liveSite == .douyin {
			socketClosed = true
		}
    }
    
    func pack(format: String, values: [Int]) -> NSMutableData {
        let data = NSMutableData()
        
        format.enumerated().forEach {
            let value = values[$0.offset]
            switch $0.element {
            case "n":
                let number: UInt16 = UInt16(value)
                var convertedNumber = CFSwapInt16(number)
                data.append(&convertedNumber, length: 2)
            case "N":
                let number: UInt32 = UInt32(value)
                var convertedNumber = CFSwapInt32(number)
                data.append(&convertedNumber, length: 4)
            case "V":
                let number: UInt32 = UInt32(value)
                var convertedNumber = CFSwapInt32LittleToHost(number)
                data.append(&convertedNumber, length: 4)
            default:
                Log("Unrecognized character: \($0.element)")
            }
        }
        return data
    }
}

extension Danmaku: DanmakuSubDelegate {
    func send(_ event: DanmakuEvent) {
        delegate?.send(event, sender: self)
    }
}

fileprivate extension String {
    func kkBase64() -> String {
        let s = self.bytes.toBase64()
        return s.kkFormatterBase64()
    }
    
    func kkFormatterBase64() -> String {
        var s = self
        s = s.replacingOccurrences(of: "=", with: "")
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        return s
    }
}
