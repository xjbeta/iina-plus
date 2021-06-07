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
    
    var videoInfos: [VideoSelector] = [] {
        didSet {
            if let max = videoInfos.map({ $0.title.count }).max() {
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
    
    var videoId = ""
    
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
        
        var s = ""
        switch info.site {
        case .bilibili:
            s = "\(info.index)  \(info.title)"
        case .bangumi:
            s = info.title
            if let longTitle = (info as? BilibiliVideoSelector)?.longTitle {
                s += "  \(longTitle)"
            }
        case .douyu:
            s = info.title
        case .cc163:
            let i = info as! CC163VideoSelector
            s = i.title
            if i.isLiving {
                s += " - 直播中"
            }
        default:
            break
        }
        
        selectVideoItem.titleTextField.stringValue = s
        selectVideoItem.titleTextField.toolTip = s
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
            if let main = self.parent as? MainViewController {
                main.selectTabItem(.search)
                let info = videoInfos[item]
                
                var u = ""
                switch info.site {
                case .bilibili:
                    u = "https://www.bilibili.com/video/\(videoId)/?p=\(info.index)"
                case .douyu:
                    u = "https://www.douyu.com/\(info.id)"
                case .bangumi:
                    u = "https://www.bilibili.com/bangumi/play/ep\(info.id)"
                case .cc163:
                    let i = info as! CC163VideoSelector
                    u = i.url
                    
                    main.searchField.stringValue = u
                    main.searchField.becomeFirstResponder()
                    main.startSearchingUrl(u, directly: false)
                    view.isSelected = false
                    return
                default:
                    break
                }
                main.searchField.stringValue = u
                main.searchField.becomeFirstResponder()
                main.startSearchingUrl(u, directly: true)
                view.isSelected = false
            }
        }
    }
}
