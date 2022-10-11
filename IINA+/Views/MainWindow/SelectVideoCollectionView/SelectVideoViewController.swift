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
    
    var videoInfos: [(String, [VideoSelector])] = [] {
        didSet {
            let length = videoInfos.flatMap {
                $0.1
            }.map {
                $0.title.count
            }.max()
            
            if let max = length {
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
        (
            collectionView.collectionViewLayout as? NSCollectionViewFlowLayout
        )?.sectionHeadersPinToVisibleBounds = true
    }
    
    func videoInfos(at section: Int) -> [VideoSelector] {
        videoInfos[section - (currentItem > 0 ? 1 : 0)].1
    }
    
    func videoInfo(at indexPath: IndexPath) -> VideoSelector? {
        switch indexPath.section {
        case 0 where currentItem > 0:
            return videoInfos.flatMap {
                $0.1
            }[currentItem]
        default:
            return videoInfos(at: indexPath.section)[indexPath.item]
        }
    }
    
}

extension SelectVideoViewController: NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize {
        if currentItem > 0 && section == 0 {
            return .zero
        } else if videoInfos.count <= 1 {
            return .zero
        } else {
            return .init(width: 1000, height: 30)
        }
    }
}

extension SelectVideoViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        videoInfos.count + (currentItem > 0 ? 1 : 0)
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        (currentItem > 0 && section == 0) ? 1 : videoInfos(at: section).count
    }
    
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: .init(rawValue: "SelectVideoCollectionViewHeader"), for: indexPath)
        (view as? SelectVideoCollectionViewHeader)?.titleTextField.stringValue = videoInfo(at: indexPath)?.title ?? ""
        return view
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
            if let longTitle = (info as? BiliVideoSelector)?.longTitle {
                s += "  \(longTitle)"
            }
        case .douyu, .huya, .biliLive, .cc163:
            s = (info.isLiving ? "🔥" : "") + info.title
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
            guard let info = info as? BiliVideoSelector else { return }
            if info.isCollection {
                u = "https://www.bilibili.com/video/\(info.bvid)"
            } else {
                u = "https://www.bilibili.com/video/\(videoId)?p=\(info.index)"
            }
        case .douyu, .huya, .biliLive:
            u = info.url
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
