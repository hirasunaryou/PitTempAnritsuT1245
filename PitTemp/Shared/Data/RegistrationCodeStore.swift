import Foundation

/// TR45 の登録コードをデバイス ID ごとに永続化する単純なストア。
protocol RegistrationCodeStoring {
    func code(for deviceID: String) -> String?
    func save(code: String, for deviceID: String)
}

final class RegistrationCodeStore: RegistrationCodeStoring, ObservableObject {
    @Published private(set) var codes: [String: String]
    private let defaultsKey = "jp.pitemp.tr4a.registration"

    init(userDefaults: UserDefaults = .standard) {
        if let saved = userDefaults.dictionary(forKey: defaultsKey) as? [String: String] {
            codes = saved
        } else {
            codes = [:]
        }
    }

    func code(for deviceID: String) -> String? { codes[deviceID] }

    func save(code: String, for deviceID: String) {
        codes[deviceID] = code
        UserDefaults.standard.set(codes, forKey: defaultsKey)
    }

    /// "12345678" → [0x12,0x34,0x56,0x78] のように BCD へ変換するヘルパ。
    static func bcdBytes(from decimal: String) -> [UInt8]? {
        guard decimal.count == 8, decimal.allSatisfy({ $0.isNumber }) else { return nil }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: decimal.count, by: 2) {
            let start = decimal.index(decimal.startIndex, offsetBy: i)
            let end = decimal.index(start, offsetBy: 2)
            let pair = decimal[start..<end]
            guard let high = UInt8(pair.first!.hexDigitValue ?? 0),
                  let low = UInt8(pair.last!.hexDigitValue ?? 0) else { return nil }
            let byte = (high << 4) | low
            bytes.append(byte)
        }
        return bytes
    }
}
