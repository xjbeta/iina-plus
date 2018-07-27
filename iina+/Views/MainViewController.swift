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
        if bookmarkTableView.selectedRow != -1 {
            dataManager.deleteBookmark(bookmarkTableView.selectedRow)
        }
    }
    
    let dataManager = DataManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        suggestionsWindowController.cancelSuggestions()
    }
    

    
}

extension MainViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataManager.requestData().count
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 55
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let view = tableView.makeView(withIdentifier: .liveStatusTableCellView, owner: nil) as? LiveStatusTableCellView {
            let url = dataManager.requestData()[row].url ?? ""
            view.titleTextField.stringValue = url
            getInfo(url) { liveInfo in
                DispatchQueue.main.async {
                    view.titleTextField.stringValue = liveInfo.title
                    view.nameTextField.stringValue = liveInfo.name
                    view.userCoverImageView.image = liveInfo.userCover
                    view.liveStatusImageView.image = liveInfo.isLiving ? NSImage(named: "NSStatusAvailable") : NSImage(named: "NSStatusUnavailable")
                }
            }
            return view
        }
        return nil
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

