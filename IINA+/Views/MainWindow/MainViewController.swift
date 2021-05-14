//
//  ViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import CoreData
import PromiseKit
import Alamofire

private extension NSPasteboard.PasteboardType {
    static let bookmarkRow = NSPasteboard.PasteboardType("bookmark.Row")
}

class MainViewController: NSViewController {
    // MARK: - Main Views
    @IBOutlet weak var mainTabView: NSTabView!
    var mainTabViewOldItem = SidebarItem.none
    @objc dynamic var mainTabViewSelectedIndex = 0
    
    var mainWindowController: MainWindowController {
        return view.window?.windowController as! MainWindowController
    }
    // MARK: - Bookmarks Tab Item
    @IBOutlet weak var bookmarkTableView: NSTableView!
    @IBOutlet var bookmarkArrayController: NSArrayController!
    @objc var bookmarks: NSManagedObjectContext
    @IBAction func sendURL(_ sender: Any) {
        if bookmarkTableView.selectedRow != -1 {
            let url = dataManager.requestData()[bookmarkTableView.selectedRow].url
            searchField.stringValue = url
            searchField.becomeFirstResponder()
            startSearch(self)
        }
    }
    
    
    @IBAction func deleteBookmark(_ sender: Any) {
        guard let index = bookmarkTableView.selectedIndexs().first,
            let w = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Bookmark."
        alert.informativeText = "This item will be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: w) { [weak self] in
            if $0 == .alertFirstButtonReturn {
                self?.dataManager.deleteBookmark(index)
                self?.bookmarkTableView.reloadData()
            }
        }
    }
    
    @IBAction func addBookmark(_ sender: Any) {
        performSegue(withIdentifier: NSStoryboardSegue.Identifier("showAddBookmarkViewController"), sender: nil)
    }
    
    let dataManager = DataManager()
    required init?(coder: NSCoder) {
        bookmarks = (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
        bookmarks.undoManager = UndoManager()
        super.init(coder: coder)
    }
    
    // MARK: - Bilibili Tab Item
    @IBOutlet weak var bilibiliTableView: NSTableView!
    @IBOutlet var bilibiliArrayController: NSArrayController!
    @objc dynamic var bilibiliCards: [BilibiliCard] = []
    let bilibili = Bilibili()
    @IBOutlet weak var videoInfosContainerView: NSView!
    
    @IBAction func sendBilibiliURL(_ sender: Any) {
        if bilibiliTableView.selectedRow != -1 {
            let card = bilibiliCards[bilibiliTableView.selectedRow]
            let bvid = card.bvid
            if card.videos == 1 {
                searchField.stringValue = "https://www.bilibili.com/video/\(bvid)"
                searchField.becomeFirstResponder()
                startSearch(self)
            } else if card.videos > 1,
                      let u = URL(string: "https://www.bilibili.com/video/\(bvid)") {
                
                bilibili.getVideoList(u).done { infos in
                    self.showSelectVideo(bvid, infos: infos)
                    }.catch { error in
                        Log("Get video list error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Search Tab Item
    @IBOutlet weak var searchField: NSSearchField!
    @IBAction func startSearch(_ sender: Any) {
        startSearchingUrl(searchField.stringValue)
    }
    
    @IBOutlet weak var suggestionsTableView: NSTableView!
    @IBOutlet weak var addNoticeStackView: NSStackView!
    
    var bookmarkArrayCountObserver: NSKeyValueObservation?
    
    var isSearching = false {
        didSet {
            DispatchQueue.main.async {
                self.suggestionsTableView.reloadData()
            }
        }
    }
    
    var yougetResult: YouGetJSON? = nil {
        didSet {
            suggestionsTableView.reloadData()
        }
    }
    
    var waitingErrorMessage: String? = nil {
        didSet {
            suggestionsTableView.reloadData()
        }
    }
    
    @IBAction func openSelectedSuggestion(_ sender: Any) {
        let uuid = UUID().uuidString
        let row = suggestionsTableView.selectedRow
        
        func clear() {
            isSearching = false
            waitingErrorMessage = nil
            yougetResult = nil
        }
        
        guard row != -1,
            let yougetJSON = yougetResult,
            let key = yougetResult?.streams.keys.sorted()[row],
            let stream = yougetResult?.streams[key],
            let url = URL(string: searchField.stringValue) else {
            if isSearching {
                Processes.shared.stopDecodeURL()
            }
            clear()
            return
        }
        clear()
        
        var urlStr: [String] = []
        if let videoUrl = stream.url {
            urlStr = [videoUrl]
        } else {
            urlStr = stream.src
        }
        var title = yougetJSON.title
        let site = LiveSupportList(url: url.absoluteString)
        
        Processes.shared.videoGet.prepareDanmakuFile(
            url,
            yougetJSON: yougetJSON,
            id: uuid).done {
            
            // init Danmaku
            if Preferences.shared.enableDanmaku,
               Processes.shared.isDanmakuVersion() {
                switch site {
                case .bilibili, .bangumi, .biliLive, .douyu, .huya, .eGame, .langPlay:
                    self.httpServer.register(uuid, site: site, url: url.absoluteString)
                default:
                    break
                }
            }
            
            
            switch site {
            case .douyu:
                if Preferences.shared.liveDecoder == .internal😀 {
                    title = key
                }
                Processes.shared.openWithPlayer(urlStr, title: title, options: .douyu, uuid: uuid)
            case .huya, .longzhu, .quanmin, .eGame, .langPlay:
                Processes.shared.openWithPlayer(urlStr, title: title, options: .withoutYtdl, uuid: uuid)
            case .bilibili, .bangumi:
                Processes.shared.openWithPlayer(urlStr, audioUrl: yougetJSON.audio, title: title, options: .bilibili, uuid: uuid, rawBiliURL: url.absoluteString)
            case .biliLive:
                Processes.shared.openWithPlayer(urlStr, title: title, options: .bililive, uuid: uuid)
            case .unsupported:
                Processes.shared.openWithPlayer(urlStr, title: title, options: .none, uuid: uuid)
            }

            }.catch {
                Log("Prepare DM file error : \($0)")
        }
    }
    
    // MARK: - Danmaku
    let httpServer = HttpServer()
    
    let iinaProxyAF = Alamofire.Session()
    
    // MARK: - Functions
    override func viewDidLoad() {
        super.viewDidLoad()
        httpServer.start()
        
        loadBilibiliCards()
        bookmarkArrayController.sortDescriptors = dataManager.sortDescriptors
        bookmarkTableView.registerForDraggedTypes([.bookmarkRow])
        bookmarkTableView.draggingDestinationFeedbackStyle = .gap
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTableView), name: .reloadMainWindowTableView, object: nil)
        NotificationCenter.default.addObserver(forName: .sideBarSelectionChanged, object: nil, queue: .main) {
            if let userInfo = $0.userInfo as? [String: SidebarItem],
                let item = userInfo["selectedItem"] {
                switch item {
                case .bookmarks:
                    self.selectTabItem(.bookmarks)
                case .bilibili:
                    self.selectTabItem(.bilibili)
                case .search:
                    self.selectTabItem(.search)
                    self.mainWindowController.window?.makeFirstResponder(self.searchField)
                default: break
                }
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: bilibiliTableView.enclosingScrollView)
        
        NotificationCenter.default.addObserver(forName: .loadDanmaku, object: nil, queue: .main) {
            guard let dic = $0.userInfo as? [String: String],
                let id = dic["id"] else { return }
            
            self.httpServer.register(id, site: .bilibili, url: "https://swift.org/\(id)")
        }
        
        // esc key down event
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:
                if let str = self.mainTabView.selectedTabViewItem?.identifier as? String,
                    let item = SidebarItem(rawValue: str) {
                    let oldItem = self.mainTabViewOldItem
                    
                    switch item {
                    case .selectVideos, .search:
                        switch oldItem {
                        case .bookmarks, .bilibili, .search:
                            NotificationCenter.default.post(name: .updateSideBarSelection, object: nil, userInfo: ["newItem": oldItem])
                            self.selectTabItem(oldItem)
                            self.mainTabViewOldItem = .none
                            return nil
                        default:
                            break
                        }
                    default:
                        break
                    }
                }
            default:
                break
            }
            return event
        }
        
        bookmarkArrayCountObserver = bookmarkArrayController.observe(\.arrangedObjects, options: [.new, .initial]) { arrayController, _ in
            let c = (arrayController.arrangedObjects as? [Any])?.count
            self.addNoticeStackView.isHidden = c != 0
        }
    }
    
    var canLoadMoreBilibiliCards = true
    
    @objc func scrollViewDidScroll(_ notification: Notification) {
        bilibiliTableView.enumerateAvailableRowViews { (view, i) in
            guard let v = view as? MainWindowTableRowView,
                let cellV = v.subviews.first as? BilibiliCardTableCellView,
                let boxV = cellV.imageBoxView,
                boxV.state != .stop else { return }
            
            boxV.updatePreview(.stop)
            boxV.stopTimer()
        }
        
        guard canLoadMoreBilibiliCards else { return }

        if let scrollView = notification.object as? NSScrollView {
            let visibleRect = scrollView.contentView.documentVisibleRect
            let documentRect = scrollView.contentView.documentRect
            if documentRect.height - visibleRect.height - visibleRect.origin.y < 150 {
                loadBilibiliCards(.history)
            }
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    @objc func reloadTableView() {
        guard let str = mainTabView.selectedTabViewItem?.identifier as? String,
              let item = SidebarItem(raw: str) else {
            return
        }
        
        switch item {
        case .bookmarks:
            var row = 0
            while row < bookmarkTableView.numberOfRows {
                if let view = bookmarkTableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? LiveStatusTableCellView {
                    view.getInfo()
                }
                row += 1
            }
            
        case .bilibili:
            if bilibiliCards.count > 0 {
                loadBilibiliCards(.new)
            } else {
                loadBilibiliCards(.init😅)
            }
        case .search:
            mainWindowController.window?.makeFirstResponder(searchField)
        default:
            break
        }
    }
    
    func selectTabItem(_ item: SidebarItem) {
        if let str = mainTabView.selectedTabViewItem?.identifier as? String,
            let item = SidebarItem(raw: str) {
            mainTabViewOldItem = item
        }
        mainTabView.selectTabViewItem(withIdentifier: item.rawValue)
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let vc = segue.destinationController as? AddBookmarkViewController {
            vc.dismiss = {
                self.dismiss(vc)
            }
        }
    }
    
    func loadBilibiliCards(_ action: BilibiliDynamicAction = .init😅) {
        var dynamicID = -1
        
        switch action {
        case .history:
            dynamicID = bilibiliCards.last?.dynamicId ?? -1
        case .new:
            dynamicID = bilibiliCards.first?.dynamicId ?? -1
        default: break
        }
        
        canLoadMoreBilibiliCards = false
        progressStatusChanged(!canLoadMoreBilibiliCards)
        bilibili.getUid().then {
            self.bilibili.dynamicList($0, action, dynamicID)
            }.done(on: .main) { cards in
                switch action {
                case .init😅:
                    self.bilibiliCards = cards
                case .history:
                    self.bilibiliCards.append(contentsOf: cards)
                case .new:
                    if cards.count > 0 {
                        self.bilibiliCards.insert(contentsOf: cards, at: 0)
                    }
                }
            }.ensure(on: .main) {
                self.canLoadMoreBilibiliCards = true
                self.progressStatusChanged(!self.canLoadMoreBilibiliCards)
            }.catch { error in
                Log("Get bilibili dynamicList error: \(error)")
        }
    }
    
    func progressStatusChanged(_ inProgress: Bool) {
        NotificationCenter.default.post(name: .progressStatusChanged, object: nil, userInfo: ["inProgress": inProgress])
    }
    
    func showSelectVideo(_ videoId: String, infos: [VideoSelector]) {
        if let selectVideoViewController = self.children.compactMap({ $0 as? SelectVideoViewController }).first {
            DispatchQueue.main.async {
                self.searchField.stringValue = ""
                selectVideoViewController.videoInfos = infos
                selectVideoViewController.videoId = videoId
                self.selectTabItem(.selectVideos)
            }
        }
    }
    
    func startSearchingUrl(_ url: String, directly: Bool = false) {
        guard url != "" else { return }
        
        Processes.shared.stopDecodeURL()
        waitingErrorMessage = nil
        isSearching = true
        progressStatusChanged(true)
        NotificationCenter.default.post(name: .updateSideBarSelection, object: nil, userInfo: ["newItem": SidebarItem.search])
        let str = searchField.stringValue
        decodeUrl(url, directly: directly).ensure {
            self.isSearching = false
            self.progressStatusChanged(false)
        }.done {
            Log("decodeUrl success: \(str)")
        }.catch { error in
            var s = "ಠ_ಠ  oops, "
            switch error {
            case PMKError.cancelled:
                return
            case VideoGetError.invalidLink:
                s += "invalid url."
            case VideoGetError.isNotLiving:
                s += "the host is not online."
            case VideoGetError.notSupported:
                s += "the website is not supported."
            case VideoGetError.needVip:
                s += "need vip."
            default:
                s += "something went wrong."
            }
            
            self.waitingErrorMessage = s
        }
    }
    
    func decodeUrl(_ url: String, directly: Bool = false) -> Promise<()> {
        
        return Promise { resolver in
            
            let videoGet = Processes.shared.videoGet
            let str = url
            yougetResult = nil
            guard str.isUrl,
                  let url = URL(string: str) else {
                resolver.reject(VideoGetError.invalidLink)
                return
            }
            
            func decodeUrl() {
                videoGet.liveInfo(str, false).get {
                    if !$0.isLiving {
                        throw VideoGetError.isNotLiving
                    }
                }.then { _ in
                    Processes.shared.decodeURL(str)
                }.done(on: .main) {
                    self.yougetResult = $0
                    print($0)
                    resolver.fulfill(())
                }.catch(on: .main, policy: .allErrors) {
                    print($0)
                    resolver.reject($0)
                }
            }
            
            if directly {
                decodeUrl()
            } else if url.host == "www.bilibili.com" {
                
                let pc = url.pathComponents
                
                if pc.count >= 3,
                   pc[1] == "video" {
//                    ([String]?) $R0 = 3 values {
//                        [0] = "/"
//                        [1] = "video"
//                        [2] = "BV1ft4y1a7Yd"
//                    }
                    let vid = pc[2]
                    bilibili.getVideoList(url).done { infos in
                        if infos.count > 1 {
                            self.showSelectVideo(vid, infos: infos)
                            resolver.fulfill(())
                        } else {
                            decodeUrl()
                        }
                    }.catch {
                        resolver.reject($0)
                    }
                } else if pc.count >= 4,
                          pc[1] == "bangumi",
                          pc[2] == "play" {
                    
//                    let vid = pc[3]
//                    ([String]) $R2 = 4 values {
//                        [0] = "/"
//                        [1] = "bangumi"
//                        [2] = "play"
//                        [3] = "ep339061" // ss34407
//                    }
                    bilibili.getBangumiList(url).done {
                        let epVS = $0.epVideoSelectors
//                        let selectionVS = $0.selectionVideoSelectors
//                        let c = epVS.count + selectionVS.count
//                        if c == 1, let vs = epVS.first ?? selectionVS.first {
                        if epVS.count == 1 {
                            decodeUrl()
                        } else {
                            self.showSelectVideo("", infos: epVS)
                            resolver.fulfill(())
                        }
                    }.catch {
                        resolver.reject($0)
                    }
                }
            } else if url.host == "www.douyu.com",
                      url.pathComponents.count > 2,
                      url.pathComponents[1] == "topic" {
                
                videoGet.getDouyuHtml(str).done {
                    if $0.roomIds.count > 0 {
                        let infos = $0.roomIds.enumerated().map {
                            DouyuVideoSelector(index: $0.offset,
                                               title: "频道 - \($0.offset + 1) - \($0.element)",
                                               id: Int($0.element) ?? 0,
                                               coverUrl: nil)
                        }
                        
                        self.showSelectVideo("", infos: infos)
                        resolver.fulfill(())
                    } else {
                        decodeUrl()
                    }
                }.catch {
                    resolver.reject($0)
                }
            } else {
                decodeUrl()
            }
        }
    }
    
    func checkIINAProxy() -> Promise<(Bool)> {
        return Promise { resolver in
            guard var u = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                resolver.fulfill(true)
                return
            }
            u.appendPathComponent("Preferences")
            u.appendPathComponent("com.colliderli.iina.plist")
            
            var dic = NSDictionary(contentsOf: u)
            
            guard let proxyStr = dic?["httpProxy"] as? String else {
                resolver.fulfill(true)
                return
            }
            
            dic = nil
            
            let proxyArray = proxyStr.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            
            guard proxyArray.count == 2 else {
                resolver.fulfill(true)
                return
            }
            let host = "http://" + proxyArray[0]
            let port = proxyArray[1]
            
            iinaProxyAF.session.configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: 1,
                kCFNetworkProxiesHTTPProxy: host,
                kCFNetworkProxiesHTTPPort: port,
                
    //            kCFProxyUsernameKey: "",
    //            kCFProxyPasswordKey: "",
            ]
            
            iinaProxyAF.request("https://al.flv.huya.com").response {
                if let error = $0.error {
                    print("Connect to video url error: \(error)")
                    resolver.fulfill(false)
                } else {
                    resolver.fulfill(true)
                }
            }
        }
    }
    
    deinit {
        bookmarkArrayCountObserver?.invalidate()
    }
}

extension MainViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView {
        case bookmarkTableView:
            return dataManager.requestData().count
        case bilibiliTableView:
            return tableView.numberOfRows
        case suggestionsTableView:
            if let obj = yougetResult {
                return obj.streams.count
            } else if isSearching || waitingErrorMessage != nil {
                return 1
            }
        default:
            break
        }
        return 0
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch tableView {
        case bookmarkTableView:
            let str = dataManager.requestData()[row].url
            switch LiveSupportList(url: str) {
            case .unsupported:
                return 23
            default:
                return 55
            }
        case bilibiliTableView:
            return tableView.rowHeight
        case suggestionsTableView:
            return 30
        default:
            break
        }
        return 0
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch tableView {
        case bookmarkTableView:
            let str = dataManager.requestData()[row].url
            switch LiveSupportList(url: str) {
            case .unsupported:
                if let view = tableView.makeView(withIdentifier: .liveUrlTableCellView, owner: nil) as? NSTableCellView {
                    view.textField?.stringValue = str
                    return view
                }
            default:
                if let view = tableView.makeView(withIdentifier: .liveStatusTableCellView, owner: nil) as? LiveStatusTableCellView {
                    if let u = URL(string: str) {
                        view.url = u
                    }
                    return view
                }
            }
        case bilibiliTableView:
            if let view = tableView.makeView(withIdentifier: .bilibiliCardTableCellView, owner: nil) as? BilibiliCardTableCellView {
                view.imageBoxView.aid = bilibiliCards[row].aid
                view.imageBoxView.imageView?.image = nil
                view.imageBoxView.updatePreview(.stop)
                ImageLoader.request(bilibiliCards[row].picUrl) { img in
                    DispatchQueue.main.async {
                        view.imageBoxView.pic = img
                        view.imageView?.image = img
                    }
                }
                return view
            }
        case suggestionsTableView:
            if let obj = yougetResult {
                if let view = tableView.makeView(withIdentifier: .suggestionsTableCellView, owner: self) as? SuggestionsTableCellView {
                    let streams = obj.streams.sorted {
                            $0.key < $1.key
                        }.sorted {
                            $0.value.size ?? 0 > $1.value.size ?? 0
                    }
                    let stream = streams[row]
                    view.setStream(stream)
                    return view
                }
            } else {
                if let view = tableView.makeView(withIdentifier: .waitingTableCellView, owner: self) as? WaitingTableCellView {
                    let waiting = waitingErrorMessage == nil
                    view.waitProgressIndicator.startAnimation(nil)
                    view.waitProgressIndicator.isHidden = !waiting
                    view.errorInfoTextField.isHidden = waiting
                    view.errorInfoTextField.stringValue = waitingErrorMessage ?? ""
                    return view
                }
            }
        default:
            break
        }
        return nil
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("MainWindowTableRowView"), owner: self) as? MainWindowTableRowView
        
    }
    
    
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        guard let row: Int = rowIndexes.first,
            let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? LiveStatusTableCellView else {
                return
        }
        let image = view.screenshot()

        session.enumerateDraggingItems(options: .concurrent, for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, idx, stop in
            
            var rect = NSRect(origin: draggingItem.draggingFrame.origin, size: image.size)
            rect.origin.y -= rect.size.height
            rect.origin.y += draggingItem.draggingFrame.size.height
            draggingItem.draggingFrame = rect

            let backgroundImageComponent = NSDraggingImageComponent(key: NSDraggingItem.ImageComponentKey(rawValue: "background"))
            backgroundImageComponent.contents = image
            backgroundImageComponent.frame = NSRect(origin: NSZeroPoint, size: image.size)
            draggingItem.imageComponentsProvider = {
                return [backgroundImageComponent]
            }
        }
    }
    

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView == bookmarkTableView else {
            return nil
        }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .bookmarkRow)
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return []
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {

        var oldRows: [Int] = []
        info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) {
            (draggingItem, idx, stop) in
            guard let item = draggingItem.item as? NSPasteboardItem else { return }
            guard let rowStr = item.string(forType: .bookmarkRow) else { return }
            guard let row = Int(rowStr) else { return }
            oldRows.append(row)
        }
        
        guard oldRows.count == 1, let oldRow = oldRows.first else {
            return false
        }
        
        tableView.beginUpdates()
        if oldRow < row {
            dataManager.moveBookmark(at: oldRow, to: row - 1)
            tableView.moveRow(at: oldRow, to: row - 1)
        } else {
            dataManager.moveBookmark(at: oldRow, to: row)
            tableView.moveRow(at: oldRow, to: row)
        }
        tableView.endUpdates()

        return true
    }
    

}

extension MainViewController: NSSearchFieldDelegate {
    func searchFieldDidStartSearching(_ sender: NSSearchField) {
        print(#function, sender.stringValue)
    }
    
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        print(#function, sender.stringValue)
    }
}

extension NSTableView {
    func selectedIndexs() -> IndexSet {
        if clickedRow != -1 {
            if selectedRowIndexes.contains(clickedRow) {
                return selectedRowIndexes
            } else {
                return IndexSet(integer: clickedRow)
            }
        } else {
            return selectedRowIndexes
        }
    }
}
