//
//  SideBarViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/10.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire

enum SidebarItem: String {
    case bookmarks
    case bilibili
    case search
    case selectVideos
    case none
    
    init?(raw: String) {
        self.init(rawValue: raw)
    }
}

class SidebarViewController: NSViewController {

    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var sidebarTableView: NSTableView!
    var sideBarItems: [SidebarItem] = [.bookmarks, .search]
    var sideBarSelectedItem: SidebarItem = .none
    
    var reachabilityManager: NetworkReachabilityManager?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sideBarSelectedItem = sideBarItems.first ?? .none
        NotificationCenter.default.addObserver(forName: .updateSideBarSelection, object: nil, queue: .main) {
            guard let userInfo = $0.userInfo as? [String: SidebarItem],
                  let newItem = userInfo["newItem"] else { return }

            Task { @MainActor in
                guard let index = self.sideBarItems.firstIndex(of: newItem) else { return }
                self.sidebarTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
        
        NotificationCenter.default.addObserver(forName: .progressStatusChanged, object: nil, queue: .main) {
            guard let userInfo = $0.userInfo as? [String: Bool],
                  let inProgress = userInfo["inProgress"] else { return }
            
            Task { @MainActor in
                if inProgress {
                    self.progressIndicator.startAnimation(nil)
                } else {
                    self.progressIndicator.stopAnimation(nil)
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: .biliStatusChanged, object: nil, queue: .main) {
            guard let userInfo = $0.userInfo as? [String: Bool],
                      let isLogin = userInfo["isLogin"] else { return }
            
            Task { @MainActor in
                self.biliStatusChanged(isLogin)
            }
        }
        startNRMListening()
    }
    
    func checkBiliLoginState() {
		Task {
			do {
				let _ = try await Processes.shared.videoDecoder.bilibili.isLogin()
			} catch let error {
				Log(error)
				biliStatusChanged(false)
			}
		}
    }
    
    func biliStatusChanged(_ isLogin: Bool) {
        DispatchQueue.main.async {
            self.sideBarItems = [.bookmarks, .search]
            if isLogin {
                self.sideBarItems.insert(.bilibili, at: 1)
            }
            self.sidebarTableView.reloadData()
        }
    }
    
    
    func startNRMListening() {
        stopNRMListening()
        
        reachabilityManager = NetworkReachabilityManager(host: "www.bilibili.com")
        reachabilityManager?.startListening { status in
            switch status {
            case .reachable(.cellular):
                Log("NetworkReachability reachable cellular.")
                Task { @MainActor in
                    self.checkBiliLoginState()
                }
            case .reachable(.ethernetOrWiFi):
                Log("NetworkReachability reachable ethernetOrWiFi.")
                Task { @MainActor in
                    self.checkBiliLoginState()
                }
            case .notReachable:
                Log("NetworkReachability notReachable.")
            case .unknown:
                break
            }
        }
    }
    
    func stopNRMListening() {
        reachabilityManager?.stopListening()
        reachabilityManager = nil
    }
    
    deinit {
        Task { [reachabilityManager] in
            reachabilityManager?.stopListening()
        }
    }
    
}

extension SidebarViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return sideBarItems.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let view = sidebarTableView.makeView(withIdentifier: .sidebarTableCellView, owner: self) as? SidebarTableCellView {
            view.item = sideBarItems[row]
            if row == 0 {
                view.isSelected = true
            }
            return view
        }
        return nil
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = sidebarTableView.selectedRow
        guard selectedRow >= 0, selectedRow < numberOfRows(in: sidebarTableView) else { return }
        
        if let row = sideBarItems.firstIndex(of: sideBarSelectedItem),
            let view = sidebarTableView.view(atColumn: sidebarTableView.selectedColumn, row: row, makeIfNecessary: false) as? SidebarTableCellView {
            view.isSelected = false
        }
        
        if let view = sidebarTableView.view(atColumn: sidebarTableView.selectedColumn, row: sidebarTableView.selectedRow, makeIfNecessary: false) as? SidebarTableCellView {
            view.isSelected = true
        }
        sideBarSelectedItem = sideBarItems[sidebarTableView.selectedRow]
        
        NotificationCenter.default.post(name: .sideBarSelectionChanged, object: nil, userInfo: ["selectedItem": sideBarSelectedItem])
    }
    
    
}
