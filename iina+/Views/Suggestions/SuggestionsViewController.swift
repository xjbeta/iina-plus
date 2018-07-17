//
//  SuggestionsViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/8.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SuggestionsViewController: NSViewController {
    
    @IBOutlet weak var suggestionsTableView: NSTableView!
    @IBAction func openSelection(_ sender: Any) {
        let row = suggestionsTableView.selectedRow
        if let key = yougetObj?.streams.keys.sorted()[row],
            let stream = yougetObj?.streams[key] {
            var urlStr = ""
            if let url = stream.url {
                urlStr = url
            } else if let url = stream.src.first {
                urlStr = url
            }
            if url != "" {
                 Processes.shared.openWithIINA(urlStr, title: yougetObj?.title ?? "")
            }
        }
        if let window = view.window?.windowController as? SuggestionsWindowController {
            window.cancelSuggestions()
        }
    }
    
    var yougetObj: YouGetJSON? = nil {
        didSet {
            reloadSuggestionsTableView()
        }
    }
    
    var url = "" {
        didSet {
            startDecode(url)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    func startDecode(_ url: String) {
        yougetObj = nil
        Processes.shared.decodeURL(url, with: .ykdl, { obj in
            DispatchQueue.main.async {
                self.yougetObj = obj
            }
        }) { error in
            
            DispatchQueue.main.async {
                if let view = self.suggestionsTableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? WaitingTableCellView {
                    view.setStatus(.error)
                }
            }
        }
    }
    
    func reloadSuggestionsTableView() {
        suggestionsTableView.reloadData()
        let rowCount = numberOfRows(in: suggestionsTableView)
        let height = CGFloat(rowCount) * (suggestionsTableView.rowHeight + suggestionsTableView.intercellSpacing.height)
        
        if let window = view.window {
            let size = NSSize(width: window.frame.size.width, height: height)
            var point = window.frame.origin
            point.y -= (height - window.frame.size.height)
            
            NSAnimationContext.runAnimationGroup({
                $0.duration = 0.15
                window.animator().setFrame(NSRect.init(origin: point, size: size), display: true, animate: true)
            })
        }
    }
    
}

extension SuggestionsViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if let obj = yougetObj {
            return obj.streams.count
        } else {
            return 1
        }
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return nil
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let obj = yougetObj {
            if let view = tableView.makeView(withIdentifier: .suggestionsTableCellView, owner: self) as? SuggestionsTableCellView {
                view.textField?.stringValue = obj.streams.keys.sorted()[row]
                return view
            }
        } else {
            if let view = tableView.makeView(withIdentifier: .waitingTableCell, owner: self) as? WaitingTableCellView {
                view.setStatus(.waiting)
                return view
            }
        }
        return nil
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return yougetObj != nil
    }
}
