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
import Starscream
import Gzip
import JavaScriptCore
import CryptoSwift
import PromiseKit
import Marshal

protocol DanmakuDelegate {
    func send(_ method: DanamkuMethod, text: String, id: String)
}

class Danmaku: NSObject {
    var socket: WebSocket? = nil
    var liveSite: SupportSites = .unsupported
    var url = ""
    var id = ""
    var delegate: DanmakuDelegate?
    
    let biliLiveServer = URL(string: "wss://broadcastlv.chat.bilibili.com/sub")
    var biliLiveIDs = (rid: "", token: "")
    
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
    
    
    let douyuServer = URL(string: "wss://danmuproxy.douyu.com:8506")
    var douyuRoomID = ""
    var douyuSavedData = Data()
    
    let huyaServer = URL(string: "wss://wsapi.huya.com")
    var huyaAnchorUid = -1
    let huyaJSContext = JSContext()
    
    var egameInfo: EgameInfo?
    private var egameTimer: DispatchSourceTimer?
    
    let langPlayServer = URL(string: "wss://cht-web.lv-show.com/chat_nsp/?EIO=3&transport=websocket")
    var langPlayUserInfo: (liveID: String, pfid: String, accessToken: String) = ("", "", "")
    
    let cc163Server = URL(string: "wss://weblink.cc.163.com")
    
    
    
    
    init(_ site: SupportSites, url: String) {
        liveSite = site
        self.url = url
        
        if site == .huya {
            if let huyaFilePath = Bundle.main.path(forResource: "huya", ofType: "js") {
                huyaJSContext?.evaluateScript(try? String(contentsOfFile: huyaFilePath))
            } else {
                Log("Not found huya.js.")
            }
        }
    }
    
    func stop() {
        socket?.disconnect()
        socket = nil
        timer?.cancel()
        egameTimer?.cancel()
        douyuSavedData = Data()
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
        let videoGet = Processes.shared.videoGet
        switch liveSite {
        case .bilibili, .bangumi:
            delegate?.send(.loadDM, text: "", id: id)
        case .biliLive:
            socket = .init(request: .init(url: biliLiveServer!))
            socket?.delegate = self
            
            bililiveRid(roomID).get {
                self.biliLiveIDs.rid = $0
            }.then {
                self.bililiveToken($0)
            }.get {
                self.biliLiveIDs.token = $0
            }.done { _ in
                self.socket?.connect()
            }.catch {
                Log("can't find bilibili ids \($0).")
            }
        case .douyu:
            
            Log("Processes.shared.videoGet.getDouyuHtml")
            
            videoGet.getDouyuHtml(url.absoluteString).done {
                self.initDouYuSocket($0.roomId)
                }.catch {
                    Log($0)
            }
        case .huya:
            
            AF.request(url.absoluteString).response { response in
                guard response.error == nil,
                      let text = response.text,
                      let roomData = text.subString(from: "var TT_ROOM_DATA = ", to: ";var").data(using: .utf8),
                      let roomInfo: JSONObject = try? JSONParser.JSONObjectWithData(roomData),
                      let id: Int = try? roomInfo.value(for: "id") else {
                    Log("Init huya AnchorUid failed.")
                    return
                }
                
                self.huyaAnchorUid = id
                
                self.socket = .init(request: .init(url: self.huyaServer!))
                self.socket?.delegate = self
                self.socket?.connect()
            }
        case .eGame:
            videoGet.getEgameInfo(url).done {
                self.egameInfo = $0.0
                self.startEgameTimer()
                }.catch {
                    Log("Get Egame Info for DM error: \($0)")
            }
        case .langPlay:
            guard let id = Int(roomID) else { return }
            videoGet.getLangPlayInfo(id).done {
                
//                https://sgkoi.dev/2019/01/24/kingkong-live-danmaku-2/
                
                let pfid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                let s1 = #"{"alg":"HS256","typ":"JWT"}"#.kkBase64()
                
                let s2 = """
{"live_id":"\($0.liveID)","pfid":"\(pfid)","name":"訪客\(pfid.dropFirst(pfid.count-5))","access_token":null,"lv":1,"from":1,"from_seq":1,"client_type":"web"}
""".kkBase64()
                
                let ss = s1 + "." + s2
                var encStr = try HMAC(key: $0.liveKey, variant: .sha256).authenticate(ss.bytes).toBase64()
                
                encStr = encStr.kkFormatterBase64()
                
                let s3 = encStr
                let token = ss + "." + s3
                self.langPlayUserInfo = ($0.liveID, $0.roomID, token)
                
                self.socket = .init(request: .init(url: self.langPlayServer!))
                self.socket?.delegate = self
                self.socket?.connect()
            }.catch {
                Log("Get LangPlay Info for DM error: \($0)")
            }
        default:
            break
        }
    }
    
    private func sendDM(_ str: String) {
        delegate?.send(.sendDM, text: str, id: id)
    }
    
    private func initDouYuSocket(_ roomID: String) {
        Log("initDouYuSocket")
        douyuRoomID = roomID
        socket = .init(request: .init(url: self.douyuServer!))
        socket?.delegate = self
        socket?.connect()
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
        if let timer = timer {
            timer.schedule(deadline: .now(), repeating: .seconds(30))
            timer.setEventHandler {
                switch self.liveSite {
                case .biliLive:
                    self.socket?.write(data: self.pack(format: "NnnNN", values: [16, 16, 1, 2, 1]) as Data)
                case .douyu:
                    //                        let keeplive = "type@=keeplive/tick@=\(Int(Date().timeIntervalSince1970))/"
                    let keeplive = "type@=mrkl/"
                    self.socket?.write(data: self.douyuSocketFormatter(keeplive))
                case .huya:
                    self.socket?.write(ping: Data())
                case .langPlay:
                    self.socket?.write(string: "2")
                default:
                    break
                }
            }
            timer.resume()
        }
    }
    
    
    private let egameTimerQueue = DispatchQueue(label: "com.xjbeta.iina+.EgameDmTimer")
    
    private func startEgameTimer() {
        egameTimer?.cancel()
        egameTimer = nil
        egameTimer = DispatchSource.makeTimerSource(flags: [], queue: egameTimerQueue)
        if let timer = egameTimer {
            timer.schedule(deadline: .now(), repeating: .seconds(1))
            timer.setEventHandler {
                self.requestEgameDM()
            }
            timer.resume()
        }
    }
    
    func requestEgameDM() {
        guard let info = egameInfo else { return }
        
        let p = ["_t" : "\(Int(NSDate().timeIntervalSince1970 * 1000))",
            "g_tk" : "",
            "p_tk" : "",
            "param" : """
            {"key":{"module":"pgg_live_barrage_svr","method":"get_barrage","param":{"anchor_id":\(info.anchorId),"vid":"\(info.pid)","scenes":4096,"last_tm":\(info.lastTm)}}}
            """,
            "app_info" : """
            {"platform":4,"terminal_type":2,"egame_id":"egame_official","version_code":"9.9.9.9","version_name":"9.9.9.9"}
            """,
            "tt" : "1"]
        
        AF.request("https://wdanmaku.egame.qq.com/cgi-bin/pgg_barrage_async_fcgi", parameters: p).response { response in
            do {
                let json: JSONObject = try JSONParser.JSONObjectWithData(response.data ?? Data())
                let dm: EgameDM = try json.value(for: "data.key.retBody.data")
                
                if info.lastTm < dm.lastTm {
                    self.egameInfo?.lastTm = dm.lastTm
                    
                }
                if dm.isSwitchPid, dm.newPid != "" {
                    self.egameInfo?.pid = dm.newPid
                }
                
                // 29 坐骑
                // 30 守护
                // 33, 31 横幅
                // 3 房管
                // 24 夺宝战机?
                // 7 礼物
                // 28 下注
                // 22 分享直播间
                
                // 1 禁言
                // 10002   ?????
                // 35 进入直播间
                
                // 23 关注了主播
                // 41 xxx 送出x个 xxx
                
                
                // 3, 0, 9   弹幕
                
                let blockType = [29, 33, 24, 7, 28, 22, 31, 30, 10002, 1, 35, 23, 41]
                
                let dmMsgs = dm.msgList.filter {
                    !blockType.contains($0.type)
                }
                
                dmMsgs.forEach {
                    self.sendDM($0.content)
                }
                
                let dmType = [3, 0, 9]
                let unKonwn = dmMsgs.filter {
                    !dmType.contains($0.type)
                }
                
                
                if unKonwn.count > 0 {
                    Log(unKonwn)
                }
                
            } catch let error {
                Log("Decode egame json error: \(error)")
            }
        }
        
        
        
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


extension Danmaku: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            webSocketDidOpen(client)
        case .disconnected(let reason, let code):
            webSocket(client, didCloseWithCode: Int(code), reason: reason)
        case .text(let string):
            webSocket(client, didReceiveMessageWith: string)
        case .binary(let data):
            webSocket(client, didReceiveMessageWith: data)
        default:
            break
        }
    }
    
    func webSocketDidOpen(_ webSocket: WebSocket) {
        Log("webSocketDidOpen")

        switch liveSite {
        case .biliLive:
            let json = """
            {"uid":0,"roomid":\(biliLiveIDs.rid),"protover":2,"platform":"web","clientver":"1.14.0","type":2,"key":"\(biliLiveIDs.token)"}
            """
            //0000 0060 0010 0001 0000 0007 0000 0001
            let data = pack(format: "NnnNN", values: [json.count + 16, 16, 1, 7, 1])
            data.append(json.data(using: .utf8)!)
            webSocket.write(data: data as Data)
            startTimer()
        case .huya:
            let id = huyaAnchorUid
            let result = huyaJSContext?.evaluateScript("""
new Uint8Array(sendRegisterGroups(["live:\(id)", "chat:\(id)"]));
""")

            let data = Data(result?.toArray() as? [UInt8] ?? [])
            webSocket.write(data: data)
            startTimer()
        case .douyu:
            let loginreq = "type@=loginreq/roomid@=\(douyuRoomID)/"
            let joingroup = "type@=joingroup/rid@=\(douyuRoomID)/gid@=-9999/"


            webSocket.write(data: douyuSocketFormatter(loginreq))
            webSocket.write(data: douyuSocketFormatter(joingroup))
            startTimer()

        case .langPlay:
            startTimer()
        default:
            break
        }
    }
    
    func webSocket(_ webSocket: WebSocket, didCloseWithCode code: Int, reason: String?) {
        Log("webSocketdidClose \(reason ?? "")")
        switch liveSite {
        case .biliLive:
            timer?.cancel()
            timer = nil
        default:
            break
        }
        delegate?.send(.liveDMServer, text: "error", id: id)
    }
    
    func webSocket(_ webSocket: WebSocket, didReceiveMessageWith string: String) {
        switch liveSite {
        case .langPlay:
            if !string.starts(with: #"42/chat_nsp,["join""#) {
                print(string)
            }
            
            
//            0{"sid":"dyeL2p6yeiDpBiTaA0r2","upgrades":[],"pingInterval":50000,"pingTimeout":60000}
            if string.starts(with: #"42/chat_nsp,["msg""#) {
                let str = string.subString(from: #""msg":""#, to: #"",""#)
                sendDM(str)
            } else if string.starts(with: #"0{"sid""#) {
                webSocket.write(string: "40/chat_nsp,")
            } else if string == "40/chat_nsp" {
                let info = langPlayUserInfo
                let str = """
42/chat_nsp,["authentication",{"live_id":"\(info.liveID)","anchor_pfid":"\(info.pfid)","access_token":"\(info.accessToken)","token":"\(info.accessToken)","from":"LANG_WEB","client_type":"LANG_WEB","r":0}]
"""
                webSocket.write(string: str)
            } else if string == #"42/chat_nsp,["authenticated",true]"# {
                Log("LangPlay authenticated.")
            } else if string.starts(with: #"42/chat_nsp,["join""#) {
                return
            } else {
//                print(string)
            }
        default:
            break
        }
    }

    func webSocket(_ webSocket: WebSocket, didReceiveMessageWith data: Data) {
        switch liveSite {
        case .biliLive:
            //            0000 0234
            //            0-4 json length + head
            if data.count == 20 {
                Log("received heartbeat")
                return
            } else if data.count == 26 {
                Log("connect success")
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


            datas.compactMap {
                try? JSONDecoder().decode(BiliLiveDanmuMsg.self, from: $0)
                }.compactMap {
                    $0.info.compactMap ({ $0.msg }).first
                }.forEach {
                    sendDM($0)
            }
        case .huya:
            let bytes = [UInt8](data)
            guard let re = huyaJSContext?.evaluateScript("test(\(bytes));"),
                  re.isString,
                  let str = re.toString() else {
                return
            }
            
            if str == "EWebSocketCommandType.EWSCmdS2C_RegisterGroupRsp" {
                Log("huya websocket inited \(str)")
                return
            } else if str.starts(with: "EWebSocketCommandType") {
                Log("huya websocket info \(str)")
                return
            }
            
            guard !str.contains("分享了直播间，房间号"), !str.contains("录制并分享了小视频"), !str.contains("进入直播间"), !str.contains("刚刚在打赏君活动中") else { return }
            
            sendDM(str)
            
            
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
            
            msgDatas.compactMap {
                String(data: $0, encoding: .utf8)
                }.forEach {
                    if $0.starts(with: "type@=chatmsg") {
                        let dm = $0.subString(from: "txt@=", to: "/cid@=")
                        guard !dm.contains("#挑战666#") else {
                            return
                        }
                        DispatchQueue.main.async {
                            self.sendDM(dm)
                        }
                    } else if $0.starts(with: "type@=error") {
                        Log("douyu socket disconnected: \($0)")
                        self.delegate?.send(.liveDMServer, text: "error", id: id)
                        socket?.disconnect()
                    }
            }
        default:
            break
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

struct EgameDM: Unmarshaling {
    var isSwitchPid: Bool
    var newPid: String
    var lastTm: Int
    var msgList: [Msg]
    
    struct Msg: Unmarshaling {
        var type: Int
        var content: String
        
        init(object: MarshaledObject) throws {
            type = try object.value(for: "type")
            content = try object.value(for: "content")
        }
    }
    
    init(object: MarshaledObject) throws {
        isSwitchPid = try object.value(for: "is_switch_pid")
        newPid = try object.value(for: "new_pid")
        lastTm = try object.value(for: "last_tm")
        msgList = try object.value(for: "msg_list")
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
