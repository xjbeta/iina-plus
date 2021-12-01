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
    var currentItem = 0
    
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
                    layout.sectionInset.bottom = 20
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
    
    func videoInfo(at indexPath: IndexPath) -> VideoSelector? {
        switch indexPath.section {
        case 0 where currentItem > 0:
            return videoInfos[currentItem]
        case 0:
            return videoInfos[indexPath.item]
        case 1 where currentItem > 0:
            return videoInfos[indexPath.item]
        default:
            return nil
        }
    }
    
}

extension SelectVideoViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        currentItem > 0 ? 2 : 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        let c = videoInfos.count
        
        switch section {
        case 0:
            return currentItem > 0 ? 1 : c
        case 1:
            return c
        default:
            return 0
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "SelectVideoCollectionViewItem"), for: indexPath)
        guard let selectVideoItem = item as? SelectVideoCollectionViewItem,
              let info = videoInfo(at: indexPath) else {
            return item
        }
        

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
        guard let indexPath = indexPaths.first,
              let view = collectionView.item(at: indexPath)?.view as? SelectVideoCollectionViewItemView else {
            return
        }
        view.isSelected = false
    }
    
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first,
              let view = collectionView.item(at: indexPath)?.view as? SelectVideoCollectionViewItemView,
              let main = self.parent as? MainViewController,
              let info = videoInfo(at: indexPath) else {
            return
        }
        
        view.isSelected = true
        
        main.selectTabItem(.search)
        
        var u = ""
        switch info.site {
        case .bilibili:
            u = "https://www.bilibili.com/video/\(videoId)?p=\(info.index)"
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
