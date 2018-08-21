//
//  SelectVideoViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/21.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class SelectVideoViewController: NSViewController {

    @IBOutlet weak var collectionView: NSCollectionView!
    
    var videoInfos: [BilibiliSimpleVideoInfo] = [] {
        didSet {
            if let max = videoInfos.map({ $0.part.count }).max() {
                var size: NSSize? = nil
                switch max {
                case _ where max > 40:
                    size = NSSize(width: 190, height: 70)
                case _ where max > 20:
                    size = NSSize(width: 190, height: 52)
                case _ where max > 0:
                    size = NSSize(width: 190, height: 34)
                default:
                    break
                }
                if let size = size {
                    let layout = NSCollectionViewFlowLayout()
                    layout.itemSize = size
                    collectionView.collectionViewLayout = layout
                }
            }
            collectionView.reloadData()
        }
    }
    
    var aid: Int = 0
    var oldTabItem = -1
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:
                if let main = self.parent as? MainViewController {
                    guard main.mainTabView.selectedTabViewItem?.label == "SelectVideos" else {
                        return event
                    }
                    if self.oldTabItem > 0,
                        self.oldTabItem < main.mainTabView.tabViewItems.count {
                        main.mainTabView.selectTabViewItem(at: self.oldTabItem)
                        return nil
                    }
                }
            default:
                break
            }
            return event
        }
    }
    
}

extension SelectVideoViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return videoInfos.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "SelectVideoCollectionViewItem"), for: indexPath)
        guard let selectVideoItem = item as? SelectVideoCollectionViewItem else {
            return item
        }
        let info = videoInfos[indexPath.item]
        let infoStr = "[\(info.page)] \(info.part)"
        selectVideoItem.titleTextField.stringValue = infoStr
        selectVideoItem.titleTextField.toolTip = infoStr
        return selectVideoItem
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        if let item = indexPaths.first?.item {
            if let view = collectionView.item(at: item)?.view as? SelectVideoCollectionViewItemView {
                view.isSelected = false
            }
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if let item = indexPaths.first?.item,
            let view = collectionView.item(at: item)?.view as? SelectVideoCollectionViewItemView {
            view.isSelected = true
            if let main = self.parent as? MainViewController,
                let searchItem = main.mainTabView.tabViewItems.filter({ $0.label == "Search" }).first {
                main.mainTabView.selectTabViewItem(searchItem)
                main.searchField.stringValue = "https://www.bilibili.com/video/av\(aid)/?p=\(videoInfos[item].page)"
                main.searchField.becomeFirstResponder()
                main.startSearch(self)
                view.isSelected = false
            }
        }
    }
}
