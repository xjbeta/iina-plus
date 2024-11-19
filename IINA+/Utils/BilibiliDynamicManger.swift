//
//  BilibiliDynamicManger.swift
//  IINA+
//
//  Created by xjbeta on 2024/7/12.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

@MainActor
protocol BilibiliDynamicMangerDelegate: Sendable {
	func bilibiliDynamicStatusChanged(_ isLoading: Bool)
	
	func bilibiliDynamicCardsContains(_ bvid: String) -> Bool
	
	func bilibiliDynamicInitCards(_ cards: [BilibiliCard])
	func bilibiliDynamicAppendCards(_ cards: [BilibiliCard])
	func bilibiliDynamicInsertCards(_ cards: [BilibiliCard])
	
	func bilibiliDynamicCards() -> [BilibiliCard]
}

actor BilibiliDynamicManger {

    private let tokenBucket = TokenBucket(tokens: 1)
    
    private var initDate: Date?
    private var newDate: Date?
    private var historyDate: Date?
	
    var delegate: BilibiliDynamicMangerDelegate?
	
	func setDelegate(_ newDelegate: BilibiliDynamicMangerDelegate) {
		delegate = newDelegate
	}
	
	func loadBilibiliCards(_ action: BilibiliDynamicAction = .init😅) {
        Task {
            await tokenBucket.withToken {
                await loadCards(action)
            }
        }
	}
    
	private func loadCards(_ action: BilibiliDynamicAction = .init😅) async {
        
        guard let delegate = delegate else { return }
		
		let uuid = UUID().uuidString
		
        await delegate.bilibiliDynamicStatusChanged(true)
		
        defer {
            Task {
                await delegate.bilibiliDynamicStatusChanged(false)
            }
        }
        
		var dynamicID = -1
		
        let bilibiliCards = await delegate.bilibiliDynamicCards()
		
		switch action {
		case .history:
            if historyDate != nil, historyDate!.secondsSinceNow < 1 {
//                Log("\(uuid), ignore, \(action)")
                return
            }
			dynamicID = bilibiliCards.last?.dynamicId ?? -1
		case .new:
            if newDate != nil, newDate!.secondsSinceNow < 5 {
//                Log("\(uuid), ignore, \(action)")
                return
            }
			dynamicID = bilibiliCards.first?.dynamicId ?? -1
        case .init😅:
            if initDate != nil, initDate!.secondsSinceNow < 15 {
//                Log("\(uuid), ignore, \(action)")
                return
            }
		}
		
		Log("\(uuid), start, \(action), \(dynamicID)")
		
		do {
			
			let bilibili = await Processes.shared.videoDecoder.bilibili
			let uid = try await bilibili.getUid()
			let cards = try await bilibili.dynamicList(uid, action, dynamicID)
			
			switch action {
			case .init😅:
                await delegate.bilibiliDynamicInitCards(cards)
                self.initDate = Date()
			case .history:
				let appends = await withTaskGroup(of: BilibiliCard?.self) { group -> [BilibiliCard] in
					for card in cards {
						group.addTask {
                            if await delegate.bilibiliDynamicCardsContains(card.bvid) {
								return nil
							} else {
								return card
							}
						}
					}
					
					var results = [BilibiliCard]()
					for await result in group {
						if let result {
							results.append(result)
						}
					}
					return results
				}
                await delegate.bilibiliDynamicAppendCards(appends)
                self.historyDate = Date()
			case .new:
                
				let appends = await withTaskGroup(of: BilibiliCard?.self) { group -> [BilibiliCard] in
					for card in cards {
						group.addTask {
                            if await delegate.bilibiliDynamicCardsContains(card.bvid) {
								return nil
							} else {
								return card
							}
						}
					}
					
					var results = [BilibiliCard]()
					for await result in group {
						if let result {
							results.append(result)
						}
					}
					return results
				}
				if appends.count > 0 {
                    await delegate.bilibiliDynamicInsertCards(appends)
				}
                self.newDate = Date()
			}
		} catch let error {
			Log("Get bilibili dynamicList error: \(error)")
		}
		
		Log("\(uuid), finish, \(dynamicID)")
	}
	
}
