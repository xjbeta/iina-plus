//
//  AboutViewController.swift
//  IINA+
//
//  Created by xjbeta on 2024/5/28.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa
import CryptoSwift
import SDWebImage

class AboutViewController: NSViewController {

	lazy var alert = NSAlert()
	
    override func viewDidLoad() {
        super.viewDidLoad()
		
		verify()
    }
	
	func verify() {
		let image = view.subviews.filter {
			$0 is NSImageView
		}.compactMap {
			$0 as? NSImageView
		}.first?.image
		
		let key = image?.sd_imageData()?.sha1().toHexString()
		assert(key == "NzZkZDZhZGIyZGRkMzUxMTM5YmM1NTU5M2RmMDlkNGI2MzQ1OGFmMA==".base64Decode(), "Fxxk")
	}
}
