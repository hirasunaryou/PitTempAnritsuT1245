//  PitTemp/Model/TemperatureFrame.swift
import Foundation

/// 1レコード = ID + 温度(℃) + ステータス
struct TemperatureFrame: Identifiable, Codable, Equatable {
    var id = UUID()
    let time: Date
    let deviceID: Int?      // 001..999
    let value: Double       // °C（0.1°C分解能を反映）
    let status: Status?     // 断線/下限超過/上限超過

    enum Status: String, Codable, Equatable {
        case bout   // センサ断線（B-OUT）
        case under  // 下限温度未満（-OVER）
        case over   // 上限温度以上（+OVER）
    }
    
    // id は永続化不要なら除外
    enum CodingKeys: String, CodingKey {
        case time
        case deviceID
        case value
        case status
    }
}
