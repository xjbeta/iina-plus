//
//  ViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import CoreData

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
        if let index = bookmarkTableView.selectedIndexs().first {
            dataManager.deleteBookmark(index)
            bookmarkTableView.reloadData()
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
            let aid = card.aid
            if card.videos == 1 {
                searchField.stringValue = "https://www.bilibili.com/video/av\(aid)"
                searchField.becomeFirstResponder()
                startSearch(self)
            } else if card.videos > 1 {
                bilibili.getVideoList(aid, { infos in
                    self.showSelectVideo(aid, infos: infos)
                }) { re in
                    do {
                        let _ = try re()
                    } catch let error {
                        Logger.log("Get video list error: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Search Tab Item
    @IBOutlet weak var searchField: NSSearchField!
    @IBAction func startSearch(_ sender: Any) {
        Processes.shared.stopDecodeURL()
        let group: DispatchGroup? = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 0)
        group?.notify(queue: .main) {
            self.progressStatusChanged(false)
        }
        
        group?.enter()
        let str = searchField.stringValue
        yougetResult = nil
        guard str != "", str.isUrl else {
            Processes.shared.stopDecodeURL()
            isSearching = false
            return
        }
        isSearching = true
        
        progressStatusChanged(true)
        NotificationCenter.default.post(name: .updateSideBarSelection, object: nil, userInfo: ["newItem": SidebarItem.search])
        if let url = URL(string: str),
            url.host == "www.bilibili.com",
            url.lastPathComponent.starts(with: "av"),
            !str.contains("p=") {
            let aid = Int(url.lastPathComponent.replacingOccurrences(of: "av", with: "")) ?? 0
            bilibili.getVideoList(aid, { infos in
                if infos.count > 1 {
                    self.showSelectVideo(aid, infos: infos)
                    group?.leave()
                    self.isSearching = false
                    semaphore.signal()
                } else {
                    semaphore.signal()
                }
                
            }) { re in
                do {
                    let _ = try re()
                } catch let error {
                    semaphore.signal()
                    Logger.log("Get video list error: \(error)")
                }
            }
            semaphore.wait()
        }
        
        guard isSearching else {
            return
        }
        
        
        Processes.shared.decodeURL(str, { obj in
            DispatchQueue.main.async {
                self.yougetResult = obj
                group?.leave()
            }
        }) { error in
            DispatchQueue.main.async {
                if let view = self.suggestionsTableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? WaitingTableCellView {
                    view.setStatus(.error)
                }
                group?.leave()
            }
        }
    }
    
    @IBOutlet weak var suggestionsTableView: NSTableView!
    
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
        let row = suggestionsTableView.selectedRow
        guard row != -1 else {
            yougetResult = nil
            isSearching = false
            Processes.shared.stopDecodeURL()
            return
        }
        if let key = yougetResult?.streams.keys.sorted()[row],
            let stream = yougetResult?.streams[key] {
            var urlStr: [String] = []
            if let videoUrl = stream.url {
                urlStr = [videoUrl]
            } else {
                urlStr = stream.src
            }
            
            if let host = URL(string: searchField.stringValue)?.host {
                let title = yougetResult?.title ?? ""
                let site = LiveSupportList(raw: host)
                switch site {
                case .douyu:
                    Processes.shared.openWithPlayer(urlStr, title: title, options: .douyu)
                case .biliLive, .huya, .longzhu, .panda, .pandaXingYan, .quanmin:
                    Processes.shared.openWithPlayer(urlStr, title: title, options: .withoutYtdl)
                case .bilibili:
                    Processes.shared.openWithPlayer(urlStr, title: title, options: .bilibili)
                case .unsupported:
                    Processes.shared.openWithPlayer(urlStr, title: title, options: .none)
                }
                
                // init Danmaku
                if Preferences.shared.enableDanmaku {
                    switch site {
                    case .bilibili, .biliLive, .panda, .douyu, .huya:
                        self.danmakuWindowController?.initDanmaku(site, title, searchField.stringValue)
                    default:
                        break
                    }
                }
            }
        }
        isSearching = false
        yougetResult = nil
    }
    
    // MARK: - Danmaku
    let danmakuWindowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "DanmakuWindowController") as? DanmakuWindowController
    
    
    // MARK: - Functions
    override func viewDidLoad() {
        super.viewDidLoad()
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
    }
    
    var canLoadMoreBilibiliCards = true
    
    @objc func scrollViewDidScroll(_ notification: Notification) {
        guard canLoadMoreBilibiliCards else { return }

        if let scrollView = notification.object as? NSScrollView {
            let visibleRect = scrollView.contentView.documentVisibleRect
            let documentRect = scrollView.contentView.documentRect
            if documentRect.height - visibleRect.height - visibleRect.origin.y < 10 {
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
    
    func loadBilibiliCards(_ action: BilibiliDynamicAction = .init) {
        var dynamicID = -1
        let group = DispatchGroup()
        
        switch action {
        case .history:
            dynamicID = bilibiliCards.last?.dynamicId ?? -1
        case .new:
            dynamicID = bilibiliCards.first?.dynamicId ?? -1
        default: break
        }
        
        canLoadMoreBilibiliCards = false
        progressStatusChanged(!canLoadMoreBilibiliCards)
        group.enter()
        bilibili.dynamicList(action, dynamicID, { cards in
            DispatchQueue.main.async {
                switch action {
                case .init:
                    self.bilibiliCards = cards
                case .history:
                    self.bilibiliCards.append(contentsOf: cards)
                case .new:
                    self.bilibiliCards.insert(contentsOf: cards, at: 0)
                default: break
                }
                group.leave()
            }
        }) { re in
            do {
                let _ = try re()
            } catch let error {
                Logger.log("Get bilibili dynamicList error: \(error)")
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.canLoadMoreBilibiliCards = true
            self.progressStatusChanged(!self.canLoadMoreBilibiliCards)
        }
    }
    
    func progressStatusChanged(_ inProgress: Bool) {
        NotificationCenter.default.post(name: .progressStatusChanged, object: nil, userInfo: ["inProgress": inProgress])
    }
    
    func showSelectVideo(_ aid: Int, infos: [BilibiliSimpleVideoInfo]) {
        if let selectVideoViewController = self.children.compactMap({ $0 as? SelectVideoViewController }).first {
            DispatchQueue.main.async {
                self.searchField.stringValue = ""
                selectVideoViewController.videoInfos = infos
                selectVideoViewController.aid = aid
                self.selectTabItem(.selectVideos)
            }
        }
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
                view.imageBoxView.pic = bilibiliCards[row].pic
                return view
            }
        case suggestionsTableView:
            if let obj = yougetResult {
                if let view = tableView.makeView(withIdentifier: .suggestionsTableCellView, owner: self) as? SuggestionsTableCellView {
                    let streams = obj.streams.sorted {
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
