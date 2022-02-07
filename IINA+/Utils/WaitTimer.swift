//
//  WaitTimer.swift
//  Aria2D
//
//  Created by xjbeta on 16/8/28.
//  Copyright © 2016年 xjbeta. All rights reserved.
//

import Cocoa

class WaitTimer: NSObject {
    
	required init(timeOut: DispatchTimeInterval,
                  queue: DispatchQueue = .global(),
	              action: @escaping (() -> Void)) {
		self.timeOut = timeOut
		self.action = action
		self.queue = queue
    }
	
    private var timeOut: DispatchTimeInterval = .milliseconds(50)
	private var commitTimer: DispatchSourceTimer?
	private var queue: DispatchQueue
	private var action: (() -> Void)?
	
    func run() {
        setTimer()
    }
	
	private func commit() {
		action?()
    }
    
	private func setTimer() {
        if commitTimer != nil {
            resetTimer()
        } else {
            startTimer()
        }
    }
    
    private func startTimer() {
		commitTimer = DispatchSource.makeTimerSource(flags: [], queue: queue)
		commitTimer?.schedule(deadline: .now() + timeOut, repeating: 0)
        commitTimer?.setEventHandler {
            self.commit()
            self.stop()
        }
        commitTimer?.resume()
    }
    
    
    
    
    private func resetTimer() {
		commitTimer?.schedule(deadline: .now() + timeOut, repeating: 0)
    }
    
	func stop() {
        if commitTimer != nil {
            commitTimer?.cancel()
            commitTimer = nil
        }
    }
}
