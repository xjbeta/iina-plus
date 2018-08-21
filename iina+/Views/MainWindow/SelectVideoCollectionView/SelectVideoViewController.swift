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
            collectionView.reloadData()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
//        selectVideoItem.titleButton.title = "[\(info.page)] \(info.part)"
        selectVideoItem.titleTextField.stringValue = "[\(info.page)] \(info.part)"
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
        if let item = indexPaths.first?.item {
            if let view = collectionView.item(at: item)?.view as? SelectVideoCollectionViewItemView {
                view.isSelected = true
            }
        }
    }
}
