import Foundation

#if canImport(UIKit)
import UIKit
#endif

struct DeviceIdentity: Equatable {
    let id: String
    let name: String

    static func current() -> DeviceIdentity {
        #if canImport(UIKit)
        let device = UIDevice.current
        let vendorID = device.identifierForVendor?.uuidString ?? Self.persistedFallbackID()
        return DeviceIdentity(id: vendorID, name: device.name)
        #else
        let computerName = ProcessInfo.processInfo.hostName
        let identifier = Self.persistedFallbackID()
        return DeviceIdentity(id: identifier, name: computerName.isEmpty ? "Device" : computerName)
        #endif
    }

    private static func persistedFallbackID() -> String {
        let defaults = UserDefaults.standard
        let key = "deviceIdentity.fallbackID"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }
}
