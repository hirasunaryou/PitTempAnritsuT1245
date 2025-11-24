//
//  MetaInfo.swift
//  PitTemp
// CSVの Date 自動入力 + 追加メタ（GPS/端末情報/アプリ情報/HR2500 ID）
// 端末・アプリ・タイムゾーン等のメタ取得ヘルパ
//
import Foundation
import UIKit

struct MetaInfo {
    let deviceName: String           // 例: "Ken's iPhone"
    let deviceModel: String          // 例: "iPhone"
    let modelIdentifier: String      // 例: "iPhone16,2"
    let marketingName: String        // 例: "iPhone 15 Pro"（簡易マップ）
    let system: String               // "iOS"
    let systemVersion: String        // "18.0"
    let vendorID: String             // IDFV（アプリベンダ単位で安定）
    let appVersion: String           // CFBundleShortVersionString
    let buildNumber: String          // CFBundleVersion
    let timezone: String             // "Asia/Tokyo"
    let locale: String               // "ja_JP"
    let batteryLevel: String         // "85%"
    let batteryState: String         // "charging" / "unplugged" / "full" / "unknown"
    let lowPowerMode: Bool           // 省電力モード
    let thermalState: String         // nominal/fair/serious/critical
    let freeDiskGB: String           // 小数1桁表示の空きGB

    static func current() -> MetaInfo {
        let dev = UIDevice.current
        dev.isBatteryMonitoringEnabled = true
        let level = dev.batteryLevel >= 0 ? String(format: "%.0f%%", dev.batteryLevel * 100) : "unknown"
        let state: String = {
            switch dev.batteryState {
            case .charging: return "charging"
            case .full:     return "full"
            case .unplugged:return "unplugged"
            default:        return "unknown"
            }
        }()

        let idfv = UIDevice.current.identifierForVendor?.uuidString ?? ""
        let dict = Bundle.main.infoDictionary ?? [:]
        let ver   = dict["CFBundleShortVersionString"] as? String ?? "?"
        let build = dict["CFBundleVersion"] as? String ?? "?"

        let modelId = modelIdentifier()
        let mkName  = marketingName(for: modelId)

        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ["nominal","fair","serious","critical"][min(Int(ProcessInfo.processInfo.thermalState.rawValue), 3)]

        let freeGB = freeDiskSpaceInGB()

        return MetaInfo(
            deviceName: dev.name,
            deviceModel: dev.model,
            modelIdentifier: modelId,
            marketingName: mkName,
            system: dev.systemName,
            systemVersion: dev.systemVersion,
            vendorID: idfv,
            appVersion: ver,
            buildNumber: build,
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            batteryLevel: level,
            batteryState: state,
            lowPowerMode: lpm,
            thermalState: thermal,
            freeDiskGB: freeGB
        )
    }

    // MARK: - Helpers

    // "iPhone16,2" のような機種IDを取得
    static func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }
    }

    // 簡易マップ（必要に応じて追加）
    static func marketingName(for identifier: String) -> String {
        // 主要どころだけ例示。必要なら増やしてください。
        let map: [String:String] = [
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone16,2": "iPhone 15 Pro",
            "iPhone16,1": "iPhone 15 Pro Max",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,5": "iPhone 13",
            "iPad14,3":   "iPad Pro 11 (M4)"
        ]
        return map[identifier] ?? identifier
    }

    static func freeDiskSpaceInGB() -> String {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue {
            return String(format: "%.1fGB", free / 1_000_000_000.0)
        }
        return "?"
    }
}
