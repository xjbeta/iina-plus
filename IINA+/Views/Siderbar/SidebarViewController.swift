//
//  SideBarViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/10.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

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
    override func viewDidLoad() {
        super.viewDidLoad()
        sideBarSelectedItem = sideBarItems.first ?? .none
        NotificationCenter.default.addObserver(forName: .updateSideBarSelection, object: nil, queue: .main) {
            if let userInfo = $0.userInfo as? [String: SidebarItem],
                let newItem = userInfo["newItem"] {
                if let index = self.sideBarItems.firstIndex(of: newItem) {
                    self.sidebarTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: .progressStatusChanged, object: nil, queue: .main) {
            if let userInfo = $0.userInfo as? [String: Bool],
                let inProgress = userInfo["inProgress"] {
                if inProgress {
                    self.progressIndicator.startAnimation(nil)
                } else {
                    self.progressIndicator.stopAnimation(nil)
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: .biliStatusChanged, object: nil, queue: .main) {
            if let userInfo = $0.userInfo as? [String: Bool],
                let isLogin = userInfo["isLogin"] {
                self.biliStatusChanged(isLogin)
            }
        }
        
        Bilibili().isLogin().done { _ in
            }.catch { _ in
                self.biliStatusChanged(false)
        }
    }
    
    func biliStatusChanged(_ isLogin: Bool) {
        DispatchQueue.main.async {
            if isLogin {
                if !self.sideBarItems.contains(.bilibili) {
                    self.sideBarItems.insert(.bilibili, at: 1)
                    self.sidebarTableView.insertRows(at: IndexSet(integer: 1), withAnimation: .effectFade)
                } else if self.sideBarItems.count != 3 {
                    self.sideBarItems = [.bookmarks, .bilibili, .search]
                    self.sidebarTableView.reloadData()
                }
            } else {
                if let index = self.sideBarItems.firstIndex(of: .bilibili) {
                    self.sideBarItems.remove(at: index)
                    self.sidebarTableView.removeRows(at: IndexSet(integer: index), withAnimation: .effectFade)
                } else if self.sideBarItems.count != 2 {
                    self.sideBarItems = [.bookmarks, .search]
                    self.sidebarTableView.reloadData()
                }
            }
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
