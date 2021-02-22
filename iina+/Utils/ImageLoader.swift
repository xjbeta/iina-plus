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
    static var storage: DiskStorage<Image> {
        get {
            let diskConfig = DiskConfig(name: diskConfigName,
                                        expiry: .seconds(3600 * 24 * 7),  // a week
                maxSize: 100*1000000,
                directory: appCacheUrl)
            let storage = try! DiskStorage<Image>(config: diskConfig,
                                                  transformer: TransformerFactory.forImage())
            return storage
        }
    }
    
    static let diskConfigName = "ImageCache"
    
    static let userCacheUrl: URL? = {
        return try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    }()
    
    static let appCacheUrl: URL? = {
        return userCacheUrl?.appendingPathComponent(Bundle.main.bundleIdentifier!)
    }()
    
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
            guard let url = appCacheUrl?.appendingPathComponent(diskConfigName) else { return "" }
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
    
    static func removeOld() {
        do {
            // Old Image cache folder
            guard let cacheUrl = userCacheUrl else { return }
            
            let oldFolderName = Bundle.main.bundleIdentifier! + ".imageCache"
            let oldUrl = cacheUrl.appendingPathComponent(oldFolderName)
            if FileManager.default.fileExists(atPath: oldUrl.path) {
                try FileManager.default.removeItem(atPath: oldUrl.path)
            }
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
            guard let iv = self, let i = $0 else { return }
            
            if iv.isSquare(), i.size.width != i.size.height {
                
                let w = i.size.width
                let h = i.size.height
                var rect = CGRect(x: 0, y: 0, width: 0, height: 0)
                
                let v = min(w, h)
                rect.size.width = v
                rect.size.height = v
                
                let o = abs(w - h) / 2
                
                if w > h {
                    rect.origin.x = o
                } else {
                    rect.origin.y = o
                }
        
                guard let re = i.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: rect) else {
                    return
                }
                
                iv.image = NSImage.init(cgImage: re, size: rect.size)
            } else {
                iv.image = i
            }
        }
    }
    
    func isSquare() -> Bool {
        return frame.size.width == frame.size.height
    }
}
