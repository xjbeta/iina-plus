//
//  ViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import CoreData

class MainViewController: NSViewController {

    @IBOutlet weak var searchField: NSSearchField!
    @IBAction func searchField(_ sender: Any) {
        let str = searchField.stringValue
        guard str != "" else {
            suggestionsWindowController.cancelSuggestions()
            return
        }
        
        if dataManager.checkURL(str) {
            suggestionsWindowController.begin(for: searchField, with: str)
        }
    }
    
    @IBOutlet weak var bookmarkTableView: NSTableView!
    
    @IBAction func sendURL(_ sender: Any) {
        if bookmarkTableView.selectedRow != -1,
            let url = dataManager.requestData()[bookmarkTableView.selectedRow].url {
            searchField.stringValue = url
            searchField.becomeFirstResponder()
            searchField(self)
        }
    }
    
    let suggestionsWindowController = NSStoryboard(name: .main, bundle: nil).instantiateController(withIdentifier:.suggestionsWindowController) as! SuggestionsWindowController
    @IBAction func hideSuggestions(_ sender: Any) {
        suggestionsWindowController.cancelSuggestions()
    }

    @IBAction func deleteBookmark(_ sender: Any) {
        if let index = bookmarkTableView.selectedIndexs().first {
            dataManager.deleteBookmark(index)
        }
    }
    @IBAction func addBookmark(_ sender: Any) {
        performSegue(withIdentifier: NSStoryboardSegue.Identifier("showAddBookmarkViewController"), sender: nil)
    }
    
    let dataManager = DataManager()
    
    @objc var bookmarks: NSManagedObjectContext
    required init?(coder: NSCoder) {
        self.bookmarks = (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        bookmarkTableView.backgroundColor = .clear
        NotificationCenter.default.addObserver(self, selector: #selector(reloadBookmarks), name: .reloadLiveStatus, object: nil)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        suggestionsWindowController.cancelSuggestions()
    }
    
    @objc func reloadBookmarks() {
        bookmarkTableView.reloadData()
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let vc = segue.destinationController as? AddBookmarkViewController {
            vc.dismiss = {
                self.dismiss(vc)
            }
        }
    }
    
}

extension MainViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataManager.requestData().count
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if let str = dataManager.requestData()[row].url,
            let url = URL(string: str) {
            switch LiveSupportList(url.host) {
            case .unsupported:
                return 17
            default:
                return 55
            }
        }
        return 0
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let str = dataManager.requestData()[row].url,
            let url = URL(string: str) {
            switch LiveSupportList(url.host) {
            case .unsupported:
                if let view = tableView.makeView(withIdentifier: .liveUrlTableCell, owner: nil) as? NSTableCellView {
                    view.textField?.stringValue = str
                    return view
                }
            default:
                if let view = tableView.makeView(withIdentifier: .liveStatusTableCellView, owner: nil) as? LiveStatusTableCellView {
                    getInfo(url, { liveInfo in
                        DispatchQueue.main.async {
                            view.titleTextField.stringValue = liveInfo.title
                            view.nameTextField.stringValue = liveInfo.name
                            view.userCoverImageView.image = liveInfo.userCover
                            view.liveStatusImageView.image = liveInfo.isLiving ? NSImage(named: "NSStatusAvailable") : NSImage(named: "NSStatusUnavailable")
                        }
                    }) { re in
                        do {
                            let _ = try re()
                        } catch let error {
                            print(error)
                            DispatchQueue.main.async {
                                view.titleTextField.stringValue = str
                                view.nameTextField.stringValue = ""
                                view.userCoverImageView.image = nil
                                view.liveStatusImageView.image = NSImage(named: "NSStatusUnavailable")
                            }
                        }
                    }
                    return view
                }
            }
        }
        return nil
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("LiveStatusTableRowView"), owner: self) as? LiveStatusTableRowView
        
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
