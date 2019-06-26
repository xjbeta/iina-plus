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
            
            let diskConfig = DiskConfig(name: Bundle.main.bundleIdentifier! + ".imageCache",
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
    
}

extension NSImageView {
    public func setImage(_ url: String) {
        self.image = nil
        ImageLoader.request(url) { [weak self] in
            self?.image = $0
        }
    }
}
