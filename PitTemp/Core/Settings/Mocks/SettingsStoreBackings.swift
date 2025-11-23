//
//  SettingsStoreBackings.swift
//  PitTemp
//
//  テストやプレビュー向けに UserDefaults を使わない SettingsStore バックエンド。
//

import Foundation

final class InMemorySettingsStoreBacking: SettingsStoreBacking {
    private var storage: [String: Any]

    init(seed: [String: Any] = [:]) {
        storage = seed
    }

    func value<T>(forKey key: String, default defaultValue: T) -> T {
        if let value = storage[key] as? T {
            return value
        }
        return defaultValue
    }

    func set<T>(_ value: T, forKey key: String) {
        storage[key] = value
    }

    func rawValue(forKey key: String) -> Any? {
        storage[key]
    }
}
