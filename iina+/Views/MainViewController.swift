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
        
        suggestionsWindowController.begin(for: searchField, with: str)
    }
    
    @IBOutlet weak var bookmarkTableView: NSTableView!
    @IBOutlet var bookmarkArrayController: NSArrayController!
    
    @IBAction func sendURL(_ sender: Any) {
        if bookmarkTableView.selectedRow != -1,
            let bookmarksArray = bookmarkArrayController.arrangedObjects as? [Bookmark] {
            searchField.stringValue = bookmarksArray[bookmarkTableView.selectedRow].url ?? ""
            searchField.becomeFirstResponder()
            searchField(self)
        }
    }
    @IBAction func hideSuggestions(_ sender: Any) {
        suggestionsWindowController.cancelSuggestions()
    }
    
    lazy var appDelegate: AppDelegate = {
        return NSApp.delegate as! AppDelegate
    }()

    let suggestionsWindowController = NSStoryboard(name: .main, bundle: nil).instantiateController(withIdentifier:.suggestionsWindowController) as! SuggestionsWindowController
    
    @objc var bookmarks: NSManagedObjectContext
    
    required init?(coder: NSCoder) {
        self.bookmarks = (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
        super.init(coder: coder)
    }
    
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



}

extension MainViewController: NSSearchFieldDelegate {
    func searchFieldDidStartSearching(_ sender: NSSearchField) {
        print(#function, sender.stringValue)
    }
    
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        print(#function, sender.stringValue)
    }
}

