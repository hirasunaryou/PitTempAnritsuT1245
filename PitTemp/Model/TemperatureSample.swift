//
//  TemperatureSample.swift
//  PitTemp
//  モデル & 記録
//

import Foundation

struct TemperatureSample: Identifiable, Codable {
    var id = UUID()
    let time: Date
    let value: Double
    
    enum CodingKeys: String, CodingKey {
        case time
        case value
    }
}
