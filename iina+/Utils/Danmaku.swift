//
//  Danmaku.swift
//  iina+
//
//  Created by xjbeta on 2018/10/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SwiftHTTP
import Marshal
import SocketRocket
import Gzip
import Socket
import JavaScriptCore

class Danmaku: NSObject {
    var socket: SRWebSocket? = nil
    var liveSite: LiveSupportList = .unsupported
    var url = ""
    
    let biliLiveServer = URL(string: "wss://broadcastlv.chat.bilibili.com/sub")
    var biliLiveRoomID = 0
    var pandaInitStr = ""
    
    var douyuSocket: Socket? = nil
    
    let huyaServer = URL(string: "wss://cdnws.api.huya.com")
    let huyaFilePath = Bundle.main.path(forResource: "huya", ofType: "js")
    var huyaUserInfo = ("", "", "")
    
    var egameInfo: EgameInfo?
    private var egameTimer: DispatchSourceTimer?
    
    var danmukuObservers: [NSObjectProtocol] = []
    
    let httpServer = HttpServer()
    
    init(_ site: LiveSupportList, url: String) {
        liveSite = site
        self.url = url
    }
    
    func start() {
        do {
            try prepareBlockList()
        } catch let error {
            Logger.log("Prepare DM block list error: \(error)")
        }
        
        httpServer.connected = { [weak self] in
            self?.loadCustomFont()
            self?.customDMSpeed()
            self?.customDMOpdacity()
            self?.loadDM()
            self?.loadFilters()
        }
        
        httpServer.disConnected = { [weak self] in
            self?.stop()
        }
        httpServer.start()
        
        danmukuObservers.append(Preferences.shared.observe(\.danmukuFontFamilyName, options: .new, changeHandler: { _, _ in
            self.loadCustomFont()
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmSpeed, options: .new, changeHandler: { _, _ in
            self.customDMSpeed()
        }))
        danmukuObservers.append(Preferences.shared.observe(\.dmOpacity, options: .new, changeHandler: { _, _ in
            self.customDMOpdacity()
        }))
    }
    
    
    func stop() {
        socket?.close()
        socket = nil
        douyuSocket?.close()
        douyuSocket = nil
        httpServer.stop()
        timer?.cancel()
        egameTimer?.cancel()
        
        danmukuObservers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }
    
    func prepareBlockList() throws {
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let targetPath = resourcePath + "/Danmaku/iina-plus-blockList.xml"
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
    
    func loadFilters() {
        var types = Preferences.shared.dmBlockType
        if Preferences.shared.dmBlockList.type != .none {
            types.append("List")
        }
        httpServer.send(.dmBlockList, text: types.joined(separator: ", "))
    }
    
    private func loadCustomFont() {
        guard let font = Preferences.shared.danmukuFontFamilyName else { return }
        httpServer.send(.customFont, text: font)
    }
    
    private func customDMSpeed() {
        let dmSpeed = Int(Preferences.shared.dmSpeed)
        httpServer.send(.dmSpeed, text: "\(dmSpeed)")
    }
    
    private func customDMOpdacity() {
        httpServer.send(.dmOpacity, text: "\(Preferences.shared.dmOpacity)")
    }
    
    func loadDM() {
        guard let url = URL(string: self.url) else { return }
        let roomID = url.lastPathComponent
        switch liveSite {
        case .bilibili:
            httpServer.send(.loadDM)
        case .biliLive:
            socket = SRWebSocket(url: biliLiveServer!)
            socket?.delegate = self
            
            HTTP.GET("https://api.live.bilibili.com/room/v1/Room/get_info?room_id=\(roomID)") {
                do {
                    let json = try JSONParser.JSONObjectWithData($0.data)
                    self.biliLiveRoomID = try json.value(for: "data.room_id")
                    self.socket?.open()
                } catch let error {
                    Logger.log("can't find bilibili live room id \(error)")
                }
            }
        case .panda:
            HTTP.GET("https://riven.panda.tv/chatroom/getinfo?roomid=\(roomID)&protocol=ws") {
                do {
                    let json = try JSONParser.JSONObjectWithData($0.data)
                    let pandaInfo = try PandaChatRoomInfo(object: json)
                    
                    self.pandaInitStr = pandaInfo.initStr()
                    self.socket = SRWebSocket(url: pandaInfo.chatAddr!)
                    self.socket?.delegate = self
                    self.socket?.open()
                } catch let error {
                    Logger.log("can't find panda live room id \(error)")
                }
            }
        case .douyu:
            initDouYuSocket(roomID)
        case .huya:
            let header = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 Safari/604.1"]
            
            HTTP.GET("https://m.huya.com/\(roomID)", headers: header) {
                //            var SUBSID = '2460685313';
                //            lSid: "2460685313"
                
                //            var TOPSID = '94525224';
                //            lTid: "94525224"
                
                //            ayyuid: '1394575534',
                //            lUid: "1394575534"
                let text = $0.text ?? ""
                
                let lSid = text.subString(from: "var SUBSID = '", to: "';")
                let lTid = text.subString(from: "var TOPSID = '", to: "';")
                let lUid = text.subString(from: "ayyuid: '", to: "',")
                self.huyaUserInfo = (lSid, lTid, lUid)
                
                self.socket = SRWebSocket(url: self.huyaServer!)
                self.socket?.delegate = self
                self.socket?.open()
            }
        case .eGame:
            VideoGet().getEgameInfo(url).done {
                self.egameInfo = $0.0
                self.startEgameTimer()
                }.catch {
                    Logger.log("Get Egame Info for DM error: \($0)")
            }
        default:
            break
        }
    }
    
    private func sendDM(_ str: String) {
        httpServer.send(.sendDM, text: str)
    }
    
//    private func sendDebugDM(_ str: String) {
//        print("sendDebugDM \(str)")
//        evaluateJavaScript("""
//            window.cm.send({'text': "\(str)",'stime': 0,'mode': 4, 'align': 2,'color': 0xffffff,'border': false});
//            """)
//    }
    
    
    private func initDouYuSocket(_ roomID: String) {
        DispatchQueue(label: "com.xjbeta.douyuSocket").async {
            do {
                self.douyuSocket = try Socket.create(family: .inet, type: .stream, proto: .tcp)
                
                try self.douyuSocket?.connect(to: "openbarrage.douyutv.com", port: 8601)
                Logger.log("douyu socket started: \(self.douyuSocket?.isConnected ?? false)")
                let loginreq = "type@=loginreq/roomid@=\(roomID)/"
                let joingroup = "type@=joingroup/rid@=\(roomID)/gid@=-9999/"
                
                try self.douyuSocket?.write(from: self.douyuSocketFormatter(loginreq))
                try self.douyuSocket?.write(from: self.douyuSocketFormatter(joingroup))
                self.startTimer()
                
                var savedData = Data()
                repeat {
                    
                    var d = Data()
                    let _ = try self.douyuSocket?.read(into: &d)
                    if d.count == 0 {
                        self.douyuSocket?.close()
                    }
                    
                    if savedData.count != 0 {
                        savedData.append(d)
                        d = savedData
                        savedData = Data()
                    }
                    
                    var msgDatas: [Data] = []
                    
                    while d.count > 12 {
                        let head = d.subdata(in: 0..<4)
                        let endIndex = Int(CFSwapInt32LittleToHost(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee }))
                        if d.count < endIndex+2 {
                            savedData.append(savedData)
                            d = Data()
                        } else {
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
                                DispatchQueue.main.async {
                                    self.sendDM(dm)
                                }
                            } else if $0.starts(with: "type@=error") {
                                Logger.log("douyu socket disconnected: \($0)")
                                self.httpServer.send(.liveDMServer, text: "error")
                                self.douyuSocket?.close()
                            }
                    }
                } while true
            } catch let error {
                Logger.log("Douyu socket error: \(error)")
            }
        }
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
                do {
                    switch self.liveSite {
                    case .biliLive:
                        try self.socket?.send(data: self.pack(format: "NnnNN", values: [16, 16, 1, 2, 1]) as Data)
                    case .panda:
                        try self.socket?.send(data: self.pack(format: "nn", values: [6, 0]) as Data)
                    case .douyu:
                        //                        let keeplive = "type@=keeplive/tick@=\(Int(Date().timeIntervalSince1970))/"
                        let keeplive = "type@=mrkl/"
                        try self.douyuSocket?.write(from: self.douyuSocketFormatter(keeplive))
                    case .huya:
                        try self.socket?.sendPing(nil)
                    default:
                        break
                    }
                } catch let error {
                    Logger.log("send keep live pack error: \(error)")
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
        
        HTTP.GET("https://wdanmaku.egame.qq.com/cgi-bin/pgg_barrage_async_fcgi", parameters: p) { response in
            do {
                let json: JSONObject = try JSONParser.JSONObjectWithData(response.data)
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
                
                
                // 3, 0, 9   弹幕
                
                let blockType = [29, 33, 24, 7, 28, 22, 31, 30, 10002, 1, 35]
                
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
                    print(unKonwn)
                }
                
            } catch let error {
                Logger.log("Decode egame json error: \(error)")
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
        HTTP.GET("https://api.bilibili.com/x/v2/dm/list.so", parameters: p) { re in
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
        Logger.log("webSocketDidOpen")
        
        switch liveSite {
        case .biliLive:
            let json = """
            {"uid":0,"roomid": \(biliLiveRoomID)}
            """
            //0000 0060 0010 0001 0000 0007 0000 0001
            let data = pack(format: "NnnNN", values: [json.count + 16, 16, 1, 7, 1])
            data.append(json.data(using: .utf8)!)
            try? webSocket.send(data: data as Data)
            startTimer()
        case .panda:
            //0006 0002 00DA
            let data = pack(format: "nnn", values: [6, 2, pandaInitStr.count])
            data.append(pandaInitStr.data(using: .utf8)!)
            try? webSocket.send(data: data as Data)
            startTimer()
        case .huya:
            /*
             sendWup    onlineui    OnUserHeartBeat    HUYA.UserHeartBeatReq
             sendWup    liveui    doLaunch    HUYA.LiveLaunchReq
             sendWup    PropsUIServer    getPropsList    HUYA.GetPropsListReq
             sendWup    liveui    getLivingInfo    HUYA.GetLivingInfoReq
             sendWup    onlineui    OnUserHeartBeat    HUYA.UserHeartBeatReq
             sendWup    liveui    doLaunch    HUYA.LiveLaunchReq
             sendWup    PropsUIServer    getPropsList    HUYA.GetPropsListReq
             sendWup    liveui    getLivingInfo    HUYA.GetLivingInfoReq
             
             sendRegister    HUYA.WSUserInfo
             
             sendWup    liveui    userIn    HUYA.UserChannelReq
 */
            
            let jsContext = JSContext()
            jsContext?.evaluateScript(try? String(contentsOfFile: huyaFilePath!))
//            jsContext?.evaluateScript("""
//                var wsUserInfo = new HUYA.WSUserInfo;
//                wsUserInfo.lSid = "\(huyaSubSid)";
//                """)
//            var SUBSID = '2460685313';
//            lSid: "2460685313"
            
//            var TOPSID = '94525224';
//            lTid: "94525224"
            
//            ayyuid: '1394575534',
//            lUid: "1394575534"
            
//            111111111
//            sGuid: "7160c3b1b915fd5b5546e2eae3ea5077"
            jsContext?.evaluateScript("""
                var wsUserInfo = new HUYA.WSUserInfo;
                wsUserInfo.lSid = "\(huyaUserInfo.0)";
                wsUserInfo.lTid = "\(huyaUserInfo.1)";
                wsUserInfo.lUid = "\(huyaUserInfo.2)";
                wsUserInfo.sGuid = "111111111";
                """)
            let result = jsContext?.evaluateScript("""
new Uint8Array(sendRegister(wsUserInfo));
""")
            
            let data = Data(bytes: result?.toArray() as? [UInt8] ?? [])
            try? webSocket.send(data: data)
            startTimer()
        default:
            break
        }
    }
    
    func webSocket(_ webSocket: SRWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        Logger.log("webSocketdidClose \(reason ?? "")")
        switch liveSite {
        case .biliLive, .panda:
            timer?.cancel()
            timer = nil
        default:
            break
        }
        httpServer.send(.liveDMServer, text: "error")
    }
    
    
    func webSocket(_ webSocket: SRWebSocket, didReceiveMessageWith data: Data) {
        
        switch liveSite {
        case .biliLive:
            //            0000 0234
            //            0-4 json length + head
            
            if data.count == 20 {
                Logger.log("received heartbeat")
            } else if data.count == 16 {
                Logger.log("connect success")
            }
            
            var datas: [Data] = []
            var d = data
            while d.count > 20 {
                let head = d.subdata(in: 0..<4)
                let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee }))
                
                if endIndex <= d.endIndex {
                    datas.append(d.subdata(in: 16..<endIndex))
                    d = d.subdata(in: endIndex..<d.endIndex)
                } else {
                    d.removeAll()
                }
            }
            
            struct DanmuMsg: Decodable {
                struct ResultObj: Decodable {
                    let msg: String?
                    init(from decoder: Decoder) throws {
                        let unkeyedContainer = try decoder.singleValueContainer()
                        msg = try? unkeyedContainer.decode(String.self)
                    }
                }
                var info: [ResultObj]
            }
            
            datas.compactMap {
                try? JSONDecoder().decode(DanmuMsg.self, from: $0)
                }.compactMap {
                    $0.info.compactMap ({ $0.msg }).first
                }.forEach {
                    sendDM($0)
            }
            
        case .panda:
            //            00 06 00 03 00 05 61 63 6B 3A 30 00 00 02 A9 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 48
            //            0 - 15 mark
            //
            //            00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 41
            //            01 41 json length
            if data.count == 4 {
                Logger.log("received heartbeat")
            } else if data.count == 22 {
                Logger.log("connect success")
            }
            
            var datas: [Data] = []
            var d = data
            guard d.count > 15 else { return }
            d = d.subdata(in: 15..<d.endIndex)
            
            while d.count > 22 {
                let head = d.subdata(in: 12..<16)
                let endIndex = Int(CFSwapInt32(head.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) in ptr.pointee })) + 16
                
                if endIndex <= d.endIndex {
                    datas.append(d.subdata(in: 16..<endIndex))
                    d = d.subdata(in: endIndex..<d.endIndex)
                } else {
                    d.removeAll()
                }
            }
            
            
            datas.compactMap { data -> String? in
                do {
                    let json = try JSONParser.JSONObjectWithData(data)
                    let type: String = try json.value(for: "type")
                    if type == "1" {
                        let str: String = try json.value(for: "data.content")
                        return str
                    } else {
                        return nil
                    }
                } catch let error {
                    print(error)
                    print(String(data: data, encoding: .utf8) ?? "")
                    return nil
                }
                }.forEach {
                    sendDM($0)
            }
            
            //            😍[:喜欢]
            //            😢[:哭]
            //            😠[:闭嘴]
            //            😪[:睡]
            //            😺[:惊讶]
            //            😎[:酷]
            //            💦[:流汗]
            //            💪[:努力]
            //            💢[:愤怒]
            //            🤔️[:疑问]
            //            😵[:晕]
            //            🤯[:疯]
            //            😱[:哀]
            //            💀[:骷髅]
            //            😳[:害羞]
            //            🤪[:抠鼻]
            //            😑[:呵欠]
            //            👎[:鄙视]
            //            🎉[:撒花]
            //            😚[:亲]
            //            😞[:可怜]
            //            233 [:233]
        //            666[:666]
        case .huya:
            let jsContext = JSContext()
            jsContext?.evaluateScript(try? String(contentsOfFile: huyaFilePath!))
            let bytes = [UInt8](data)
            
            if let re = jsContext?.evaluateScript("test(\(bytes));"),
                re.isString {
                let str = re.toString() ?? ""
                guard str != "HUYA.EWebSocketCommandType.EWSCmd_RegisterRsp" else {
                    Logger.log("huya websocket inited EWSCmd_RegisterRsp")
                    return
                }
                guard str != "HUYA.EWebSocketCommandType.Default" else {
                    Logger.log("huya websocket WebSocketCommandType.Default \(data)")
                    return
                }
                guard !str.contains("分享了直播间，房间号"), !str.contains("录制并分享了小视频"), !str.contains("进入直播间") else { return }
                sendDM(str)
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
                print("Unrecognized character: \($0.element)")
            }
        }
        return data
    }
}

struct PandaChatRoomInfo: Unmarshaling {
    var appid: String
    var rid: Int
    var sign: String
    var authType: String
    var ts: Int
    var chatAddr: URL?
    
    init(object: MarshaledObject) throws {
        appid = try object.value(for: "data.appid")
        rid = try object.value(for: "data.rid")
        sign = try object.value(for: "data.sign")
        authType = try object.value(for: "data.authType")
        ts = try object.value(for: "data.ts")
        let chatList: [String]  = try object.value(for: "data.chat_addr_list")
        if let str = chatList.first, let url = URL(string: "wss://" + str) {
            chatAddr = url
        }
    }
    
    func initStr() -> String {
        return """
        u:\(rid)@\(appid)
        ts:\(ts)
        sign:\(sign)
        authtype:\(authType)
        plat:jssdk_pc_web
        version:0.5.10
        network:unknown
        compress:none
        """
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
