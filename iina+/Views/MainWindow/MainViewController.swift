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
    @IBOutlet var bookmarkArrayController: NSArrayController!
    
    @IBAction func sendURL(_ sender: Any) {
        if bookmarkTableView.selectedRow != -1 {
            let url = dataManager.requestData()[bookmarkTableView.selectedRow].url
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
            bookmarkTableView.reloadData()
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
        bookmarkArrayController.sortDescriptors = dataManager.sortDescriptors
        bookmarkTableView.backgroundColor = .clear
        bookmarkTableView.registerForDraggedTypes([.bookmarkRow])
        bookmarkTableView.draggingDestinationFeedbackStyle = .gap
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
        let str = dataManager.requestData()[row].url
        if let url = URL(string: str) {
            switch LiveSupportList(raw: url.host) {
            case .unsupported:
                return 17
            default:
                return 55
            }
        }
        return 0
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let str = dataManager.requestData()[row].url
        if let url = URL(string: str) {
            switch LiveSupportList(raw: url.host) {
            case .unsupported:
                if let view = tableView.makeView(withIdentifier: .liveUrlTableCell, owner: nil) as? NSTableCellView {
                    view.textField?.stringValue = str
                    return view
                }
            default:
                if let view = tableView.makeView(withIdentifier: .liveStatusTableCellView, owner: nil) as? LiveStatusTableCellView {
                    view.resetInfo()
                    getInfo(url, { liveInfo in
                        view.setInfo(liveInfo)
                    }) { re in
                        do {
                            let _ = try re()
                        } catch let error {
                            print(error)
                            DispatchQueue.main.async {
                                view.titleTextField.stringValue = str
                                view.liveStatusImageView.image = NSImage(named: "NSStatusNone")
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
    
    
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        guard let row: Int = rowIndexes.first,
            let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) else {
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
        
        
        if let objs = bookmarkArrayController.arrangedObjects as? [Bookmark] {
            if oldRow < row {
                dataManager.moveBookmark(at: oldRow, to: row - 1)
                tableView.moveRow(at: oldRow, to: row - 1)
            } else {
                dataManager.moveBookmark(at: oldRow, to: row)
                tableView.moveRow(at: oldRow, to: row)
            }
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
