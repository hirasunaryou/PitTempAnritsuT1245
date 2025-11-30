//
//  TR4ARegistrationStore.swift
//  PitTemp
//
//  役割: TR45 ごとの登録コード(8桁)を保存し、プロトコル層へ安全に供給する。
//

import Foundation

protocol TR4ARegistrationStoring: AnyObject, ObservableObject {
    var entries: [TR4ARegistrationEntry] { get }
    func code(for identifier: String) -> String?
    func set(code: String?, for identifier: String)
}

struct TR4ARegistrationEntry: Identifiable, Equatable {
    let id: String
    var code: String
}

final class TR4ARegistrationStore: ObservableObject, TR4ARegistrationStoring {
    @Published private(set) var entries: [TR4ARegistrationEntry] = []

    private let defaultsKey = "tr4a.registrationCodes"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func code(for identifier: String) -> String? {
        entries.first { $0.id == identifier }?.code
    }

    func set(code: String?, for identifier: String) {
        // 8 桁でなければ削除扱いにする。
        guard let code, code.count == 8, code.allSatisfy({ $0.isNumber }) else {
            entries.removeAll { $0.id == identifier }
            persist()
            return
        }
        if let idx = entries.firstIndex(where: { $0.id == identifier }) {
            entries[idx].code = code
        } else {
            entries.append(TR4ARegistrationEntry(id: identifier, code: code))
        }
        persist()
    }
}

private extension TR4ARegistrationStore {
    func load() {
        guard let dict = defaults.dictionary(forKey: defaultsKey) as? [String: String] else { return }
        entries = dict.map { TR4ARegistrationEntry(id: $0.key, code: $0.value) }
            .sorted { $0.id < $1.id }
    }

    func persist() {
        let dict = entries.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.id] = entry.code
        }
        defaults.set(dict, forKey: defaultsKey)
    }
}

