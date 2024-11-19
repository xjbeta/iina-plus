//
//  ViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import CoreData
import Alamofire
import SDWebImage
@preconcurrency import WebKit

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
    @IBOutlet weak var bookmarkTableView: MainWindowTableView!
    @IBOutlet var bookmarkArrayController: NSArrayController!
    var bookmarks: [Bookmark] {
        get {
            return bookmarkArrayController.arrangedObjects as? [Bookmark] ?? []
        }
    }
	
    @objc var context: NSManagedObjectContext
    @IBAction func sendURL(_ sender: Any) {
        guard bookmarkTableView.selectedRow != -1 else { return }
        let url = bookmarks[bookmarkTableView.selectedRow].url
        searchField.stringValue = url
        
        let option = NSEvent.modifierFlags.contains(.option)
        startSearchingUrl(url, with: option)
    }
    
    // MARK: - Menu
    
    @IBOutlet var siteFilterMenu: NSMenu!
    @IBOutlet var liveStateMenu: NSMenu!
    
    enum LiveStateMenuItems: Int {
        case all = 2
        case living = 1
        case offline = 0
        case other = -1
    }
    
    @IBAction func deleteBookmark(_ sender: Any) {
        guard let index = bookmarkTableView.selectedIndexs().first,
              let objs = bookmarkArrayController.arrangedObjects as? [Bookmark],
              index >= 0,
              index < objs.count,
              let w = view.window else { return }
        let obj = objs[index]
        
        
        let alert = NSAlert()
        alert.messageText = "Delete Bookmark."
        alert.informativeText = "\(obj.liveName == "" ? obj.url : obj.liveName) will be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: w) { [weak self] in
            if $0 == .alertFirstButtonReturn {
                self?.dataManager.delete(obj)
                self?.bookmarkTableView.reloadData()
            }
        }
    }
    
    @IBAction func addBookmark(_ sender: Any) {
        performSegue(withIdentifier: NSStoryboardSegue.Identifier("showAddBookmarkViewController"), sender: nil)
    }
    
    @IBAction func removeFilters(_ sender: NSButton) {
        bookmarkArrayController.fetchPredicate = nil
        Log("Remove Filters")
    }
    
    @IBAction func copyUrl(_ sender: NSMenuItem) {
        var url: String?
        switch sender.menu {
        case bookmarkTableView.menu:
            url = bookmarks[bookmarkTableView.clickedRow].url
        case bilibiliTableView.menu:
            guard let bvid = bilibiliDataSource.itemIdentifier(forRow: bilibiliTableView.clickedRow)?.bvid else { return }
            url = "https://www.bilibili.com/video/" + bvid
        default:
            break
        }
        guard let url = url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
    
    @IBAction func decode(_ sender: NSMenuItem) {
        var url: String?
        switch sender.menu {
        case bookmarkTableView.menu:
            url = bookmarks[bookmarkTableView.clickedRow].url
        case bilibiliTableView.menu:
            guard let bvid = bilibiliDataSource.itemIdentifier(forRow: bilibiliTableView.selectedRow)?.bvid else { return }
            url = "https://www.bilibili.com/video/" + bvid
        default:
            break
        }
        guard let url = url else { return }
        
        searchField.stringValue = url
        searchField.becomeFirstResponder()
        startSearch(self)
    }
    
    let dataManager = DataManager()
    required init?(coder: NSCoder) {
        context = (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
        context.undoManager = UndoManager()
        super.init(coder: coder)
    }
    
    // MARK: - Bilibili Tab Item
    @IBOutlet weak var bilibiliTableView: MainWindowTableView!
    var bilibiliDataSource: NSTableViewDiffableDataSource<Int, BilibiliCard>!
    
    @MainActor
	let bilibiliDynamicManager = BilibiliDynamicManger()
	
    @IBOutlet weak var videoInfosContainerView: NSView!
    
    @IBAction func sendBilibiliURL(_ sender: Any) {
        guard let card = bilibiliDataSource.itemIdentifier(forRow: bilibiliTableView.selectedRow) else { return }
        
        let bvid = card.bvid
        if card.videos == 1 {
            searchField.stringValue = "https://www.bilibili.com/video/\(bvid)"
            searchField.becomeFirstResponder()
            startSearch(self)
        } else if card.videos > 1 {
            Task {
                do {
                    let infos = try await Processes.shared.videoDecoder.bilibili.getVideoList("https://www.bilibili.com/video/\(bvid)")
                    showSelectVideo(bvid, infos: infos)
                } catch let error {
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
    @IBOutlet var noticeTabView: NSTabView!
    
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
        let row = suggestionsTableView.selectedRow
        let processes = Processes.shared
        
        func clear() {
            isSearching = false
            waitingErrorMessage = nil
            yougetResult = nil
        }
        
        guard row != -1,
            let yougetJSON = yougetResult else {
            if isSearching {
                processes.stopDecodeURL()
            }
            clear()
            return
        }
        clear()
		
		Task {
			do {
				try await open(result: yougetJSON, row: row)
			} catch let error {
				Log("Prepare Video / DM file error : \(error)")
			}
		}
    }
    
    // MARK: - Danmaku
    
    let iinaProxyAF = Alamofire.Session()
    
    // MARK: - Functions
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureBilibiliTableView()
        
        dataManager.requestData().forEach {
            $0.state = LiveState.none.raw
        }
		
        Task {
            await bilibiliDynamicManager.setDelegate(self)
            await bilibiliDynamicManager.loadBilibiliCards()
		}
     
        bookmarkArrayController.sortDescriptors = dataManager.sortDescriptors
        bookmarkTableView.registerForDraggedTypes([.bookmarkRow])
        bookmarkTableView.draggingDestinationFeedbackStyle = .gap
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTableView), name: .reloadMainWindowTableView, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sideBarSelectionChanged(_:)), name: .sideBarSelectionChanged, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewDidScroll(_:)), name: NSScrollView.didLiveScrollNotification, object: bilibiliTableView.enclosingScrollView)
        
        // esc key down event
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:
                guard let str = self.mainTabView.selectedTabViewItem?.identifier as? String,
                      let item = SidebarItem(rawValue: str) else { return event }
                
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
            default:
                break
            }
            return event
        }
        
        bookmarkArrayCountObserver = bookmarkArrayController.observe(\.arrangedObjects, options: [.new, .initial]) { [unowned self] arrayController, _ in
            Task {
                await updateNoticeTabView()
            }
        }
    }
    
    
    @objc func scrollViewDidScroll(_ notification: Notification) {
        bilibiliTableView.enumerateAvailableRowViews { (view, i) in
            guard let v = view as? MainWindowTableRowView,
                let cellV = v.subviews.first as? BilibiliCardTableCellView,
                let boxV = cellV.imageBoxView,
                boxV.state != .stop else { return }
            
            boxV.updatePreview(.stop)
            boxV.stopTimer()
        }
		
        Task {
            if let scrollView = notification.object as? NSScrollView {
                let visibleRect = scrollView.contentView.documentVisibleRect
                let documentRect = scrollView.contentView.documentRect
                if documentRect.height - visibleRect.height - visibleRect.origin.y < 150 {
                    await bilibiliDynamicManager.loadBilibiliCards(.history)
                }
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
              let item = SidebarItem(raw: str)
              
        else {
            return
        }
        
        switch item {
        case .bookmarks:
            dataManager.reloadAllBookmark()
        case .bilibili:
			Task {
				if bilibiliDataSource.snapshot().numberOfItems > 0 {
					await bilibiliDynamicManager.loadBilibiliCards(.new)
				} else {
					await bilibiliDynamicManager.loadBilibiliCards(.init😅)
				}
			}
        case .search:
            mainWindowController.window?.makeFirstResponder(searchField)
        default:
            break
        }
    }
    
    @objc func sideBarSelectionChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: SidebarItem],
              let item = userInfo["selectedItem"] else {
            return
        }
        switch item {
        case .bookmarks:
            self.selectTabItem(.bookmarks)
        case .bilibili:
            self.selectTabItem(.bilibili)
        case .search:
            self.selectTabItem(.search)
        default:
            break
        }
        self.reloadTableView()
    }
    
    func updateNoticeTabView() {
        let c = (bookmarkArrayController.arrangedObjects as? [Any])?.count
        
        noticeTabView.isHidden = c != 0
        
        let i = bookmarkArrayController.fetchPredicate == nil ? 0 : 1
        noticeTabView.selectTabViewItem(at: i)
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
    

    
    func progressStatusChanged(_ inProgress: Bool) {
        NotificationCenter.default.post(name: .progressStatusChanged, object: nil, userInfo: ["inProgress": inProgress])
    }
    
    func showSelectVideo(_ videoId: String, infos: [(String, [VideoSelector])], currentItem: Int = 0) {
        guard let selectVideoViewController = self.children.compactMap({ $0 as? SelectVideoViewController }).first else {
            return
        }
        
        DispatchQueue.main.async {
            self.searchField.stringValue = ""
            selectVideoViewController.videoInfos = infos
            selectVideoViewController.videoId = videoId
            selectVideoViewController.currentItem = currentItem
            self.selectTabItem(.selectVideos)
        }
    }
    
	
    func openWithJSPlayer(_ url: String) {
        guard let playerWC = NSStoryboard(name: .player, bundle: nil).instantiateInitialController() as? JSPlayerWindowController else {
                    return
                }
        
        playerWC.window?.makeKeyAndOrderFront(nil)
        playerWC.contentVC?.url = url
    }
    
	
	func startSearchingUrl(_ url: String,
						   directly: Bool = false,
						   with option: Bool = false) {
		Task {
			do {
				try await startSearchingUrl(url, directly: directly, with: option)
			} catch let error {
				var s = NSLocalizedString("VideoGetError.oops", comment: "ಠ_ಠ  oops, ")
				switch error {
				case is CancellationError:
					return
				case VideoGetError.invalidLink:
					s += NSLocalizedString("VideoGetError.invalidLink", comment: "invalid url.")
				case VideoGetError.isNotLiving:
					s += NSLocalizedString("VideoGetError.isNotLiving", comment: "the host is not online.")
				case VideoGetError.notSupported:
					s += NSLocalizedString("VideoGetError.notSupported", comment: "the website is not supported.")
				case VideoGetError.needVip:
					s += NSLocalizedString("VideoGetError.needVip", comment: "need vip.")
				case VideoGetError.needLogin:
					s += NSLocalizedString("VideoGetError.needLogin", comment: "need login.")
				default:
					s += NSLocalizedString("VideoGetError.default", comment: "something went wrong.")
				}
				
				Log(error)
				await MainActor.run {
					waitingErrorMessage = s
				}
			}
		}
	}
    
    func startSearchingUrl(_ url: String,
                           directly: Bool = false,
                           with option: Bool = false) async throws {
		await MainActor.run {
			Processes.shared.stopDecodeURL()
			waitingErrorMessage = nil
			yougetResult = nil
		}
		
		guard url != "" else {
			await MainActor.run {
				isSearching = false
				progressStatusChanged(false)
			}
			return
		}
        
		let jspSupported = SupportSites(url: url).supportWebPlayer()
        
        if Preferences.shared.enableFlvjs, jspSupported {
			await MainActor.run {
				openWithJSPlayer(url)
			}
            return
        }
        
		await MainActor.run {
			isSearching = true
			progressStatusChanged(true)
		}

        NotificationCenter.default.post(name: .updateSideBarSelection, object: nil, userInfo: ["newItem": SidebarItem.search])
        var str = url
        
		let urlString = try await Processes.shared.videoDecoder.bilibiliUrlFormatter(url)
		
		await MainActor.run {
			if searchField.stringValue == str {
				searchField.stringValue = urlString
				str = urlString
			}
		}
		
		try await decodeUrl(urlString, directly: directly, with: option)
		
		
		await MainActor.run {
			isSearching = false
			progressStatusChanged(false)
		}
		
		Log("decodeUrl success: \(str)")
		

    }
    
    func decodeUrl(_ url: String,
                   directly: Bool = false,
                   with option: Bool = false) async throws {
     
		let videoGet = Processes.shared.videoDecoder
        let bilibili = await Processes.shared.videoDecoder.bilibili
        let douyu = await Processes.shared.videoDecoder.douyu
        
		var str = url
		yougetResult = nil
		guard str.isUrl,
			  let url = URL(string: str) else {
			throw VideoGetError.invalidLink
		}
		
		func decodeUrl() async throws {
			let info = try await videoGet.liveInfo(str, false)
			if !info.isLiving {
				throw VideoGetError.isNotLiving
			}
			let json = try await Processes.shared.decodeURL(str)
			
			if Preferences.shared.autoOpenResult && !option {
				try await open(result: json, row: 0)
			} else {
				await MainActor.run {
					self.yougetResult = json
				}
			}
		}
		
		if directly {
			try await decodeUrl()
		} else if let bUrl = BilibiliUrl(url: str) {
			let u = bUrl.fUrl
			
			switch bUrl.urlType {
			case .video:
				let infos = try await bilibili.getVideoList(u)
				let list = infos.flatMap({ $0.1 })
				if list.count > 1 {
					let cItem = list.first!.isCollection ? list.firstIndex(where: { $0.bvid == bUrl.id }) : bUrl.p - 1
					showSelectVideo(bUrl.id, infos: infos, currentItem: cItem ?? 0)
				} else {
					try await decodeUrl()
				}
			case .bangumi:
                let epVS = try await bilibili.bangumi.getBangumiList(u).epVideoSelectors
				if epVS.count == 1 {
					try await decodeUrl()
				} else {
					var cItem = 0
					if bUrl.id.starts(with: "ep") {
						cItem = epVS.firstIndex {
							$0.id == bUrl.id.dropFirst(2)
						} ?? 0
					}
					
					showSelectVideo("", infos: [("", epVS)], currentItem: cItem)
				}
			default:
				return
			}
		} else if url.host == "www.douyu.com",
				  url.pathComponents.count > 2,
				  url.pathComponents[1] == "topic" {
			
			
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), any Error>) in
				Task {
					defer {
						continuation.resume()
					}
					
					do {
						let htmls = try await douyu.getDouyuHtml(str)
						guard htmls.roomIds.count > 0 else {
							try await decodeUrl()
							return
						}
						let cid = htmls.roomId
						var re = [DouyuVideoSelector]()
						
						let names = try await douyu.getDouyuEventRoomNames(htmls.pageId)
						
						re = names.enumerated().map {
							DouyuVideoSelector(
								index: $0.offset,
								title: $0.element.text,
								id: $0.element.roomId,
								url: "https://www.douyu.com/\($0.element.roomId)",
								isLiving: false,
								coverUrl: nil)
						}
						
						let status = try await douyu.getDouyuEventRoomOnlineStatus(htmls.pageId)
						
						re.enumerated().forEach {
							re[$0.offset].isLiving = status[$0.element.id] ?? false
						}
						showSelectVideo("", infos: [("", re)], currentItem: re.map({ $0.id }).firstIndex(of: cid) ?? 0)
					} catch let error {
						switch error {
						case VideoGetError.douyuNotFoundSubRooms:
							try await decodeUrl()
						default:
							continuation.resume(throwing: error)
						}
					}
				}
			}
			
			
		} else if url.host == "www.huya.com" {
			let rl = try await videoGet.huya.getHuyaRoomList(url.absoluteString)
			if rl.list.count == 0 {
				try await decodeUrl()
			} else {
				showSelectVideo("", infos: [("", rl.list)], currentItem: rl.list.firstIndex(where: { $0.id == rl.current }) ?? 0)
			}
		} else if url.host == "live.bilibili.com" {
			let list = try await videoGet.biliLive.getRoomList(url.absoluteString)
			if list.1.count == 0 || list.1.count == 1 {
				try await decodeUrl()
			} else {
				var c = 0
				if url.pathComponents.count > 1 {
					let id = "\(url.pathComponents[1])"
					c = list.1.firstIndex(where: { $0.id == id || $0.sid == id }) ?? 0
				}
				showSelectVideo("", infos: [("", list.1)], currentItem: c)
			}
		} else if url.host == "cc.163.com" {
			let state = try await videoGet.cc163.getCC163State(url.absoluteString)
			if state.list.count > 1 {
				let infos = state.list.enumerated().map {
					CC163VideoSelector(
						index: $0.offset,
						title: $0.element.name,
						ccid: "\($0.element.ccid)",
						isLiving: $0.element.isLiving,
						url: $0.element.channel,
						id: "\($0.element.ccid)")
				}
				showSelectVideo("", infos: [("", infos)])
			} else if let i = state.info as? CC163Info {
				str = "https://cc.163.com/ccid/\(i.ccid)"
				try await decodeUrl()
			} else if let i = state.info as? CC163ChannelInfo {
				str = "https://cc.163.com/ccid/\(i.ccid)"
				try await decodeUrl()
			}
		} else {
			try await decodeUrl()
		}
    }
    
	func open(result: YouGetJSON, row: Int) async throws {
		let proc = Processes.shared
		let pref = Preferences.shared
		
		var yougetJSON = result
		let uuid = yougetJSON.uuid
		
		let videoGet = proc.videoDecoder
		
		guard yougetJSON.videos.count > 0 else {
			throw VideoGetError.notFountData
		}
		
		let key = yougetJSON.videos[row].key
		
		yougetJSON = try await videoGet.prepareVideoUrl(yougetJSON, key)
		try await videoGet.prepareDanmakuFile(yougetJSON: yougetJSON, id: uuid)
		
		guard !pref.enableFlvjs,
			  pref.livePlayer == .iina,
			  await proc.iina.archiveType == .plugin else {
			try await proc.openWithPlayer(yougetJSON, key)
			return
		}
		
		@MainActor
		func showInstallAlert() {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Danmaku plugin Install Alert messageText", comment: "You need to install the Danmaku plugin for IINA")
			alert.informativeText = NSLocalizedString("Danmaku plugin Install Alert informativeText", comment: "")
			
			alert.alertStyle = .warning
			alert.addButton(withTitle: "OK")
			let _ = alert.runModal()
		}
		
		switch IINAApp.pluginState() {
		case .needsUpdate(let plugin) where plugin.ghVersion < 4:
			Log("Open result failed, plugin outdate.")
			showInstallAlert()
		case .isDev, .needsUpdate(_), .ok(_), .newer(_):
			Log("Open result with plugin")
			try await proc.openWithPlayer(yougetJSON, key)
		case .needsInstall, .multiple:
			Log("Open result failed, pluginNotFound.")
			showInstallAlert()
		case .error(let error):
			throw error
		}
	}
    
	
	/*
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
	 */
    
    func initLiveStateMenu() {
        let items = liveStateMenu.items
        if items.first(where: { $0.state == .on }) == nil {
            items.first?.state = .on
        }
        
        if bookmarkArrayController.fetchPredicate == nil {
            items.forEach {
                $0.state = .off
            }
            items.first?.state = .on
        }
        
        items.forEach {
            $0.action = #selector(selectLiveStateItem)
        }
    }
    
    @objc func selectLiveStateItem(_ menuItem: NSMenuItem) {
        liveStateMenu.items.forEach {
            $0.state = .off
        }
        menuItem.state = .on
        updateFilter()
    }
    
    func initLiveSiteMenu() {
        let items = siteFilterMenu.items
        if items.count == 0 {
            initLiveSiteMenuItems()
        }
        if items.first(where: { $0.state == .on }) == nil {
            items.first?.state = .on
        }
        
        if bookmarkArrayController.fetchPredicate == nil,
           items.first?.state != .on {
            items.forEach {
                $0.state = .off
            }
            items.first?.state = .on
        }
    }
    
    func initLiveSiteMenuItems() {
        let menu = siteFilterMenu!
        let act = #selector(selectLiveSiteItem)
        
        menu.removeAllItems()
        
        let all = NSLocalizedString("LiveSite.All", comment: "All")
        let allItem = ObjMenuItem(title: all, action: act, keyEquivalent: "")
        
        allItem.tag = 1
        allItem.state = .on
        
        var items = [
            allItem,
            .separator()
        ]
        
        let sites = dataManager.requestData().map {
            $0.url
        }.compactMap(SupportSites.init(url: ))
            .filter {
                $0 != .unsupported
            }
        
        let siteItems = Array(Set(sites))
            .sorted {
                $0.siteName > $1.siteName
            }.map { site -> ObjMenuItem in
                let i = ObjMenuItem(title: site.siteName, action: act, keyEquivalent: "")
                i.tag = -99
                i.item = site
                return i
            }
        items.append(contentsOf: siteItems)
        
        menu.items = items
    }
    
    @objc func selectLiveSiteItem(_ menuItem: NSMenuItem) {
        siteFilterMenu.items.forEach {
            $0.state = .off
        }
        
        menuItem.state = .on
        updateFilter()
    }
    
    func updateFilter() {
        var f = ""
        if let item = liveStateMenu.items.first(where: { $0.state == .on }),
           let sItem = LiveStateMenuItems(rawValue: item.tag) {
            
            switch sItem {
            case .all:
                f = ""
            case .living:
                f = "state == 1"
            case .offline:
                f = "state == 0"
            case .other:
                // Bangumi bilibili -99
                f = "state == -1"
            }
        }
        
        var f2 = ""
        if let item = siteFilterMenu.items.first(where: { $0.state == .on }) as? ObjMenuItem {
            switch item.tag {
            case 1:
                f2 = ""
            default:
                if let i = item.item as? SupportSites {
                    f2 = "url CONTAINS '\(i.rawValue)'"
                    if i == .bilibili || i == .bangumi {
                        f = ""
                    }
                }
            }
        }
        
        let format = [f, f2].filter {
            $0 != ""
        }.joined(separator: " && ")
        
        guard format != "" else {
            bookmarkArrayController.fetchPredicate = nil
            Log("Remove Filters")
            return
        }
        
        Log("New Filters: \(format)")
        
        let p = NSPredicate(format: format)
        bookmarkArrayController.fetchPredicate = p
    }
    
    
    func configureBilibiliTableView() {
        guard let tableView = bilibiliTableView else { return }

        tableView.delegate = self
        tableView.dataSource = bilibiliDataSource

        bilibiliDataSource = NSTableViewDiffableDataSource<Int, BilibiliCard>(tableView: tableView) { (tableView, tableColumn, row, item) -> NSView in
            guard let view = tableView.makeView(withIdentifier: .bilibiliCardTableCellView, owner: self) as? BilibiliCardTableCellView else { return NSTableCellView() }
            view.update(item)
            return view
        }
        
        bilibiliDataSource.rowViewProvider = { (tableView, tableColumn, itemIdentifier) in
            tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("MainWindowTableRowView"), owner: self) as? MainWindowTableRowView ?? MainWindowTableRowView()
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
            return bookmarks.count
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
            let str = bookmarks[row].url
            switch SupportSites(url: str) {
            case .unsupported:
                return 23
            default:
                return 57
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
            let data = bookmarks[row]
            let str = data.url
            switch SupportSites(url: str) {
            case .unsupported:
                return tableView.makeView(withIdentifier: .liveUrlTableCellView, owner: nil)
            default:
                return tableView.makeView(withIdentifier: .liveStatusTableCellView, owner: nil) as? LiveStatusTableCellView
            }
        case suggestionsTableView:
            if let obj = yougetResult {
                if let view = tableView.makeView(withIdentifier: .suggestionsTableCellView, owner: self) as? SuggestionsTableCellView {
                    let s = obj.videos[row]
                    view.setStream(s)
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

        guard bookmarkArrayController.fetchPredicate == nil else {
            return false
        }
        
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

extension MainViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu {
        case liveStateMenu:
            initLiveStateMenu()
        case siteFilterMenu:
            initLiveSiteMenu()
        default:
            return
        }
    }
}

extension MainViewController: BilibiliDynamicMangerDelegate {
	func bilibiliDynamicStatusChanged(_ isLoading: Bool) {
		progressStatusChanged(isLoading)
	}
	
	func bilibiliDynamicCardsContains(_ bvid: String) -> Bool {
        bilibiliDataSource.snapshot().itemIdentifiers.contains(where: { $0.bvid == bvid })
	}
	
	func bilibiliDynamicInitCards(_ cards: [BilibiliCard]) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, BilibiliCard>()
        snapshot.deleteAllItems()
        snapshot.appendSections([0])
        snapshot.appendItems(cards, toSection: 0)
        bilibiliDataSource.apply(snapshot, animatingDifferences: false)
	}
	
	func bilibiliDynamicAppendCards(_ cards: [BilibiliCard]) {
        var snapshot = bilibiliDataSource.snapshot()
        snapshot.appendItems(cards, toSection: 0)
        bilibiliDataSource.apply(snapshot, animatingDifferences: false)
	}
	
	func bilibiliDynamicInsertCards(_ cards: [BilibiliCard]) {
        var snapshot = bilibiliDataSource.snapshot()
        if let item = snapshot.itemIdentifiers(inSection: 0).first {
            snapshot.insertItems(cards, beforeItem: item)
        } else {
            snapshot.appendItems(cards)
        }
        bilibiliDataSource.apply(snapshot, animatingDifferences: false)
	}
	
	func bilibiliDynamicCards() -> [BilibiliCard] {
        
        bilibiliDataSource.snapshot().itemIdentifiers
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
