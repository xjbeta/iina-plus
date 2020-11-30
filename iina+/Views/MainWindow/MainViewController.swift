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
            } else if card.videos > 1 {
                let u = "https://www.bilibili.com/video/\(bvid)"
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
        Processes.shared.stopDecodeURL()
        
        let str = searchField.stringValue
        yougetResult = nil
        guard str != "", str.isUrl else {
            isSearching = false
            return
        }
        isSearching = true

        progressStatusChanged(true)
        NotificationCenter.default.post(name: .updateSideBarSelection, object: nil, userInfo: ["newItem": SidebarItem.search])
        
        func decodeUrl() {
            Processes.shared.videoGet.liveInfo(str, false).get {
                if !$0.isLiving {
                    throw VideoGetError.isNotLiving
                }
                }.then { _ in
                    Processes.shared.decodeURL(str)
                }.done(on: .main) {
                    self.yougetResult = $0
                }.ensure {
                    self.progressStatusChanged(false)
                }.catch(on: .main, policy: .allErrors) { error in
                    Log("\(error)")

                    guard self.suggestionsTableView.numberOfRows == 1,
                        let view = self.suggestionsTableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? WaitingTableCellView else {
                            return
                    }
                    switch error {
                    case PMKError.cancelled:
                        return
                    case VideoGetError.isNotLiving:
                        view.setStatus(.isNotLiving)
                    case VideoGetError.notSupported:
                        view.setStatus(.notSupported)
                    default:
                        view.setStatus(.error)
                    }
            }
        }
        
        if let url = URL(string: str),
            url.host == "www.bilibili.com",
            !str.contains("?p=") {
            
            
            
            var vid = ""
            let pathComponents = NSString(string: str).pathComponents
            guard pathComponents.count > 3 else {
                return
            }
            vid = pathComponents[3]
            bilibili.getVideoList(url.absoluteString).done { infos in
                if infos.count > 1 {
                    self.showSelectVideo(vid, infos: infos)
                    self.isSearching = false
                    self.progressStatusChanged(false)
                } else {
                    decodeUrl()
                }
                }.catch { error in
                    Log("Get video list error: \(error)")
            }
        } else if let url = URL(string: str),
            url.host == "www.douyu.com",
            url.pathComponents.count > 2,
            url.pathComponents[1] == "topic" {
            
            Processes.shared.videoGet.getDouyuHtml(str).done {
                if $0.roomIds.count > 0 {
                    let infos = $0.roomIds.enumerated().map {
                        DouyuVideoList(index: $0.offset, title: "频道 - \($0.offset + 1) - \($0.element)", roomId: Int($0.element) ?? 0)
                    }

                    self.showSelectVideo("", infos: infos)
                    self.isSearching = false
                    self.progressStatusChanged(false)
                } else {
                    decodeUrl()
                }
                }.catch { error in
                    Log("Get douyu room list error: \(error)")
            }
        } else {
            decodeUrl()
        }
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
    
    @IBAction func openSelectedSuggestion(_ sender: Any) {
        let uuid = UUID().uuidString
        let row = suggestionsTableView.selectedRow
        guard row != -1,
            let yougetJSON = yougetResult,
            let key = yougetResult?.streams.keys.sorted()[row],
            let stream = yougetResult?.streams[key],
            let url = URL(string: searchField.stringValue) else {
                if isSearching {
                    Processes.shared.stopDecodeURL()
                }
                isSearching = false
                yougetResult = nil
            return
        }
        
        var urlStr: [String] = []
        if let videoUrl = stream.url {
            urlStr = [videoUrl]
        } else {
            urlStr = stream.src
        }
        var title = yougetJSON.title
        let site = LiveSupportList(raw: url.host)
        
        Processes.shared.videoGet.prepareDanmakuFile(url, id: uuid).done {
            
            // init Danmaku
            if Preferences.shared.enableDanmaku,
               Processes.shared.isDanmakuVersion() {
                switch site {
                case .bilibili, .biliLive, .douyu, .huya, .eGame, .langPlay:
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
            case .bilibili:
                Processes.shared.openWithPlayer(urlStr, audioUrl: yougetJSON.audio, title: title, options: .bilibili, uuid: uuid, rawBiliURL: url.absoluteString)
            case .biliLive:
                Processes.shared.openWithPlayer(urlStr, title: title, options: .bililive, uuid: uuid)
            case .unsupported:
                Processes.shared.openWithPlayer(urlStr, title: title, options: .none, uuid: uuid)
            }

            }.ensure {
                self.isSearching = false
                self.yougetResult = nil
            }.catch {
                Log("Prepare DM file error : \($0)")
        }
    }
    
    // MARK: - Danmaku
    let httpServer = HttpServer()
    
    
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
        var row = 0
        while row < bookmarkTableView.numberOfRows {
            if let view = bookmarkTableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? LiveStatusTableCellView {
                view.getInfo()
            }
            row += 1
        }
        
        loadBilibiliCards()
        if mainTabView.selectedTabViewItem?.label == "Search" {
            mainWindowController.window?.makeFirstResponder(searchField)
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
                    self.bilibiliCards.insert(contentsOf: cards, at: 0)
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
            } else if isSearching {
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
            if let url = URL(string: str) {
                switch LiveSupportList(raw: url.host) {
                case .unsupported, .bilibili:
                    return 20
                default:
                    return 55
                }
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
            if let url = URL(string: str) {
                switch LiveSupportList(raw: url.host) {
                case .unsupported, .bilibili:
                    if let view = tableView.makeView(withIdentifier: .liveUrlTableCellView, owner: nil) as? NSTableCellView {
                        view.textField?.stringValue = str
                        return view
                    }
                default:
                    if let view = tableView.makeView(withIdentifier: .liveStatusTableCellView, owner: nil) as? LiveStatusTableCellView {
                        view.url = url
                        return view
                    }
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
                    view.setStatus(.waiting)
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
