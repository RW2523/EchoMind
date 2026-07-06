//
//  Item.swift
//  EchoMind
//
//  Created by EchoMind Host on 7/6/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
