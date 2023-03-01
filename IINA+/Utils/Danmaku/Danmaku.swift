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
import JavaScriptCore
import CryptoSwift
import PromiseKit
import PMKAlamofire
import Marshal
import SDWebImage

protocol DanmakuDelegate {
    func send(_ event: DanmakuEvent, sender: Danmaku)
}

protocol DanmakuSubDelegate {
    func send(_ event: DanmakuEvent)
}

class Danmaku: NSObject {
    var socket: SRWebSocket? = nil
    var liveSite: SupportSites = .unsupported
    var url = ""
    var id = ""
    var delegate: DanmakuDelegate?
    
    private var heartBeatCount = 0
    
    let biliLiveServer = URL(string: "wss://broadcastlv.chat.bilibili.com/sub")
    var biliLiveIDs = (rid: "", token: "")
    var bililiveEmoticons = [BiliLiveEmoticon]()
    
    struct BiliLiveDanmuMsg: Decodable {
        struct ResultObj: Decodable {
            let msg: String?
            init(from decoder: Decoder) throws {
                let unkeyedContainer = try decoder.singleValueContainer()
                msg = try? unkeyedContainer.decode(String.self)
            }
        }
        var info: [ResultObj]
    }
    
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
        socket?.close()
        socket = nil
        timer?.cancel()
        douyuSavedData = Data()
        heartBeatCount = 0
        
        douyinDM?.stop()
        douyinDM = nil
    }
    
    func prepareBlockList() throws {
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let targetPath = resourcePath + "/Danmaku/iina-plus-blockList.xml"
        if FileManager.default.fileExists(atPath: targetPath) {
            try FileManager.default.removeItem(atPath: targetPath)
        }
        switch Preferences.shared.dmBlockList.type {
        case .none:
            return
        case .basic:
            let basicList = resourcePath + "/Block-List-Basic.xml"
            try FileManager.default.copyItem(atPath: basicList, toPath: targetPath)
        case .plus:
            let basicList = resourcePath + "/Block-List-Plus.xml"
            try FileManager.default.copyItem(atPath: basicList, toPath: targetPath)
        case .custom:
            FileManager.default.createFile(atPath: targetPath, contents: Preferences.shared.dmBlockList.customBlockListData, attributes: nil)
        }
    }

    
    func loadDM() {
        guard let url = URL(string: self.url) else { return }
        let roomID = url.lastPathComponent
        let videoDecoder = Processes.shared.videoDecoder
        switch liveSite {
        case .biliLive:
            socket = .init(url: biliLiveServer!)
            socket?.delegate = self
            
            bililiveRid(roomID).get {
                self.biliLiveIDs.rid = $0
            }.then {
                when(fulfilled: self.bililiveToken($0),
                     self.bililiveEmoticons($0))
            }.done {
                self.biliLiveIDs.token = $0.0
                self.bililiveEmoticons = $0.1
                self.socket?.open()
            }.catch {
                Log("can't find bilibili ids \($0).")
            }
        case .douyu:
            
            Log("Processes.shared.videoDecoder.getDouyuHtml")
            
            videoDecoder.douyu.getDouyuHtml(url.absoluteString).done {
                self.initDouYuSocket($0.roomId)
                }.catch {
                    Log($0)
            }
        case .huya:
            AF.request(url.absoluteString).responseString().done {
                let js = $0.string.subString(from: "var TT_ROOM_DATA = ", to: "};")
                let roomData = (js + "}").data(using: .utf8) ?? Data()
                let roomInfo: JSONObject = try JSONParser.JSONObjectWithData(roomData)
                
                if let id: String = try? roomInfo.value(for: "id"),
                    let uid = Int(id) {
                    self.huyaAnchorUid = uid
                } else {
                    self.huyaAnchorUid = try roomInfo.value(for: "id")
                }
                
                self.socket = .init(url: self.huyaServer!)
                self.socket?.delegate = self
                self.socket?.open()
            }.catch {
                Log("Init huya AnchorUid failed \($0).")
            }
        case .douyin:
            douyinDM = .init()
            douyinDM?.requestPrepared = { ur in
                self.socket = .init(urlRequest: ur)
                self.socket?.delegate = self
                self.socket?.open()
            }
            douyinDM?.start(self.url)
            socketClosed = false
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
        timer = DispatchSource.makeTimerSource(flags: [], queue: timerQueue)
        guard let timer = timer else {
            return
        }
        
        let interval: DispatchTimeInterval = liveSite == .douyin ? .seconds(10) : .seconds(30)
        
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
    

    
    
    func bililiveRid(_ roomID: String) -> Promise<(String)> {
        return Promise { resolver in
            AF.request("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)").response {
                do {
                    let json = try JSONParser.JSONObjectWithData($0.data ?? Data())
                    let id: Int = try json.value(for: "data.room_id")
                    resolver.fulfill("\(id)")
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    func bililiveToken(_ rid: String) -> Promise<(String)> {
        return Promise { resolver in
            AF.request("https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo?id=\(rid)&type=0").response {
                do {
                    let json = try JSONParser.JSONObjectWithData($0.data ?? Data())
                    let token: String = try json.value(for: "data.token")
                    resolver.fulfill(token)
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    struct BiliLiveEmoticon: Unmarshaling {
        let emoji: String
        let url: String
        let width: Int
        let height: Int
        let identity: Int
        let emoticonUnique: String
        let emoticonId: Int
        
        var emoticonData: Data?
        
        init(object: MarshaledObject) throws {
            emoji = try object.value(for: "emoji")
            let u: String = try object.value(for: "url")
            url = u.replacingOccurrences(of: "http://", with: "https://")
            width = try object.value(for: "width")
            height = try object.value(for: "height")
            identity = try object.value(for: "identity")
            emoticonUnique = try object.value(for: "emoticon_unique")
            emoticonId = try object.value(for: "emoticon_id")
        }
    }
    
    
    func bililiveEmoticons(_ rid: String) -> Promise<([BiliLiveEmoticon])> {
        return Promise { resolver in
            AF.request("https://api.live.bilibili.com/xlive/web-ucenter/v2/emoticon/GetEmoticons?platform=pc&room_id=\(rid)").response {
                
                struct BiliLiveEmoticonData: Unmarshaling {
                    let emoticons: [BiliLiveEmoticon]
                    let pkgId: Int
                    let pkgName: String
                    init(object: MarshaledObject) throws {
                        emoticons = try object.value(for: "emoticons")
                        pkgId = try object.value(for: "pkg_id")
                        pkgName = try object.value(for: "pkg_name")
                    }
                }
                
                do {
                    let json = try JSONParser.JSONObjectWithData($0.data ?? Data())
                    let emoticonData: [BiliLiveEmoticonData] = try json.value(for: "data.data")
                    var emoticons = emoticonData.flatMap {
                        $0.emoticons
                    }
                    
                    when(fulfilled: emoticons.enumerated().map { item -> Promise<()> in
                        let key = "BiliLive_Emoticons_" + item.element.emoticonUnique
                        if let image = SDImageCache.shared.imageFromCache(forKey: key) {
                            emoticons[item.offset].emoticonData = image.sd_imageData()
                            return .value
                        } else {
                            return AF.request(item.element.url).responseData().done {
                                emoticons[item.offset].emoticonData = $0.data
                                SDImageCache.shared.store(NSImage(data: $0.data), forKey: key)
                            }
                        }
                    }).done {
                        resolver.fulfill(emoticons)
                    }.catch {
                        resolver.reject($0)
                    }
                } catch let error {
                    resolver.reject(error)
                }
            }
        }
    }
    
    /*
    func testedBilibiliAPI() {
        let p = ["aid": 31027408,
                 "appkey": "1d8b6e7d45233436",
                 "build": 5310000,
                 "mobi_app": "android",
                 "oid": 54186450,
                 "plat":2,
                 "platform": "android",
                 "ps": 0,
                 "ts": 1536407932,
                 "type": 1,
                 "sign": 0] as [String : Any]
        AF.request("https://api.bilibili.com/x/v2/dm/list.so", parameters: p).response { re in
            let data = re.data
            let head = data.subdata(in: 0..<4)
            let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee })) + 4
            let d1 = data.subdata(in: 4..<endIndex)
            
            let d2 = data.subdata(in: endIndex..<data.endIndex)
            
            let d3 = try! d2.gunzipped()
            
            let str1 = String(data: d1, encoding: .utf8)
            let str2 = String(data: d3, encoding: .utf8)
            
            //            FileManager.default.createFile(atPath: "/Users/xjbeta/Downloads/d1", contents: d1, attributes: nil)
            //
            //            FileManager.default.createFile(atPath: "/Users/xjbeta/Downloads/d2", contents: d3, attributes: nil)
            
        }
    }
 
     */
    
}


extension Danmaku: SRWebSocketDelegate {
    func webSocketDidOpen(_ webSocket: SRWebSocket) {
        Log("webSocketDidOpen")

        switch liveSite {
        case .biliLive:
            let json = """
            {"uid":0,"roomid":\(biliLiveIDs.rid),"protover":2,"platform":"web","clientver":"1.14.0","type":2,"key":"\(biliLiveIDs.token)"}
            """
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
                    d = try d.gunzipped()
                    return d
                }  catch let error {
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
            
            let dms = datas.compactMap { data -> DanmakuComment? in
                if let s = String(data: data, encoding: .utf8)?.subString(from: "\"emoticon_unique\":\"", to: "\","),
                   let emoticon = self.bililiveEmoticons.first(where: { $0.emoticonUnique == s }) {
                    
                    guard let base64 = emoticon.emoticonData?.base64EncodedString(),
                            base64.count > 0 else { return nil }
                    
                    let ext = NSString(string: emoticon.url.lastPathComponent).pathExtension
                    
                    let size = Int(emoticon.width / 2) > 125 ? 125 : Int(emoticon.width / 2)
                    
                    
                    return DanmakuComment(
                        text: "",
                        imageSrc: "data:image/\(ext);base64," + base64,
                        imageWidth: size)
                } else if let s = (try? JSONDecoder().decode(BiliLiveDanmuMsg.self, from: data))?.info.compactMap ({ $0.msg }).first {
                    return DanmakuComment(text: s)
                } else {
                    return nil
                }
            }
            
            sendDM(.init(method: .sendDM, text: "", dms: dms))
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
                let re = try DouYinResponse(serializedData: data)
                let ree = try DouYinDMResponse(serializedData: re.data.gunzipped())
                
                let dms = ree.messages.filter {
                    $0.method == "WebcastChatMessage"
                }.compactMap {
                    try? ChatMessage(serializedData: $0.payload)
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
