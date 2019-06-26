//
//  ImageLoader.swift
//  iina+
//
//  Created by xjbeta on 2019/6/26.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import Cache

class ImageLoader: NSObject {
    
    static let imageCacheName = Bundle.main.bundleIdentifier! + ".imageCache"
    
    static var storage: DiskStorage<Image> {
        get {
            
            let diskConfig = DiskConfig(name: imageCacheName,
                                        expiry: .seconds(3600 * 24 * 7),  // a week
                maxSize: 100*1000000)
            
            let storage = try! DiskStorage<Image>(config: diskConfig,
                                                  transformer: TransformerFactory.forImage())
            return storage
        }
    }
    
    static func request(_ url: String, complete: @escaping ((NSImage?) -> ())) {
        guard url != "" else {
            complete(nil)
            return
        }
        
        if let image = try? storage.object(forKey: url) {
            complete(image)
        } else {
            AF.request(url).responseData {
                guard let d = $0.data,
                    let image = NSImage(data: d) else {
                        complete(nil)
                        return
                }
                try? storage.setObject(image, forKey: url)
                complete(image)
            }
        }
    }
    
    static func cacheSize() -> String {
        do {
            var url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            url.appendPathComponent(imageCacheName)
            Log(url)
            
            var folderSize = 0
            
            try (FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL])?.lazy.forEach {
                folderSize += try $0.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0
            }
            
            let  byteCountFormatter =  ByteCountFormatter()
            byteCountFormatter.allowedUnits = .useMB
            byteCountFormatter.countStyle = .file
            let sizeToDisplay = byteCountFormatter.string(for: folderSize) ?? ""
            return sizeToDisplay
        } catch let error {
            Log(error)
            return ""
        }
    }
    
    static func removeExpired() {
        do {
            try storage.removeExpiredObjects()
        } catch let error {
            Log(error)
        }
    }
    
    static func removeAll() {
        do {
            try storage.removeAll()
        } catch let error {
            Log(error)
        }
    }
}

extension NSImageView {
    public func setImage(_ url: String) {
        self.image = nil
        ImageLoader.request(url) { [weak self] in
            self?.image = $0
        }
    }
}
