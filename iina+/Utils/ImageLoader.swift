//
//  ImageLoader.swift
//  iina+
//
//  Created by xjbeta on 2019/6/26.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import Alamofire
import AlamofireImage

class ImageLoader: NSObject {
    
    static let imageCache = AutoPurgingImageCache()
    static let imageCacheName = Bundle.main.bundleIdentifier! + ".imageCache"
    
    static func request(_ url: String, complete: @escaping ((NSImage?) -> ())) {
        guard url != "" else {
            complete(nil)
            return
        }
        
        if let image = imageCache.image(withIdentifier: url) {
            complete(image)
        } else {
            AF.request(url).responseData {
                guard let d = $0.data,
                    let image = NSImage(data: d) else {
                        complete(nil)
                        return
                }
                imageCache.add(image, withIdentifier: url)
                complete(image)
            }
        }
    }
    
    static func cacheSize() -> String {
        do {
            var url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            url.appendPathComponent(Bundle.main.bundleIdentifier!)
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
    
    static func removeAll() {
        let re = imageCache.removeAllImages()
        if !re {
            Log("Remove all image cache error.")
        }
    }
    
    static func removeOldCache() {
        do {
            var url = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            url.appendPathComponent(imageCacheName)
            
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(atPath: url.path)
            }
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
