//
//  SessionID.swift
//  PitTemp
//
//  新仕様のセッションIDを集中管理するための型。
//  - 人間が読めるフォーマット（Op-ISO8601-Device-Context-Rand-vRev-Sync）を rawValue として保持
//  - 旧UUIDベースのIDとの互換を確保するため、フォールバック初期化を用意
//  - 生成関数は純粋関数として実装し、テストで固定値を差し込めるようにしている
//
//  コードを読む学習者向けメモ:
//    - "IDの構造化"と"表示用文字列"を分離すると、後からフォーマットを変えても呼び出し側の変更を最小にできる
//    - Codableのカスタム初期化で「旧データ（UUID文字列）を新仕様（SessionID）」へなめらかに移行する
//
import Foundation

struct SessionID: Hashable, Codable, Identifiable, CustomStringConvertible {
    enum Operation: String, Codable {
        case measure = "MEASURE"
        case edit = "EDIT"
        case dup = "DUP"
        case merge = "MERGE"
        case unknown = "UNKNOWN"
    }

    enum SyncState: String, Codable {
        case offline = "OFF"
        case online = "ON"
        case merged = "MERGED"
        case unknown = "UNKNOWN"
    }

    /// 生の表示用文字列。既存のUUIDベースIDもここにそのまま入れることで互換性を保つ。
    let rawValue: String
    let op: Operation
    let timestamp: Date
    let deviceAbbrev: String
    let context: String
    let random: String
    let revision: Int
    let syncState: SyncState

    var id: String { rawValue }
    var description: String { rawValue }

    // MARK: - 生成
    static func generate(op: Operation = .measure,
                         timestamp: Date = Date(),
                         deviceAbbrev: String,
                         context: String,
                         random: String = SessionID.randomAlphanumerics(count: 5),
                         revision: Int = 1,
                         syncState: SyncState = .offline,
                         timeZone: TimeZone = .current) -> SessionID {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        isoFormatter.timeZone = timeZone
        let iso = isoFormatter.string(from: timestamp)
        let contextTrimmed = context.isEmpty ? "CTX" : context.replacingOccurrences(of: " ", with: "_")
        let body = "\(op.rawValue)-\(iso)-\(deviceAbbrev)-\(contextTrimmed)-\(random)-v\(revision)-\(syncState.rawValue)"
        return SessionID(rawValue: body,
                         op: op,
                         timestamp: timestamp,
                         deviceAbbrev: deviceAbbrev,
                         context: contextTrimmed,
                         random: random,
                         revision: revision,
                         syncState: syncState)
    }

    // MARK: - デコード互換層
    init(rawValue: String) {
        // 可能なら新フォーマットをパース。失敗したら UUID/任意文字列をそのまま保持する。
        if let parsed = SessionID.parse(rawValue) {
            self = parsed
            return
        }
        self.rawValue = rawValue
        self.op = .unknown
        self.timestamp = Date.distantPast
        self.deviceAbbrev = "unknown"
        self.context = "unknown"
        self.random = "legacy"
        self.revision = 1
        self.syncState = .unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = SessionID(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// UUID文字列など旧仕様を新仕様に持ち上げるためのヘルパー。
    static func fromUUID(_ uuid: UUID) -> SessionID {
        SessionID(rawValue: uuid.uuidString)
    }

    // MARK: - 内部ユーティリティ
    private static func randomAlphanumerics(count: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<count).compactMap { _ in letters.randomElement() })
    }

    private static func parse(_ raw: String) -> SessionID? {
        // 期待フォーマット: Op-ISO8601-Device-Context-Rand-v<rev>-Sync
        // ISO8601部分にもハイフンが含まれるため、「末尾5要素 + 先頭1要素」を固定し、中間を時刻とみなす。
        let parts = raw.split(separator: "-")
        guard parts.count >= 7 else { return nil }

        let opToken = String(parts[0])
        let syncToken = String(parts.last!)
        let revToken = parts[parts.count - 2]
        let randomToken = parts[parts.count - 3]
        let contextToken = parts[parts.count - 4]
        let deviceToken = parts[parts.count - 5]
        let isoSlice = parts[1..<(parts.count - 5)]
        let isoString = isoSlice.joined(separator: "-")

        let op = Operation(rawValue: opToken) ?? .unknown
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        guard let ts = formatter.date(from: isoString) else { return nil }

        let revision = Int(revToken.dropFirst()) ?? 1
        let sync = SyncState(rawValue: syncToken) ?? .unknown

        return SessionID(rawValue: raw,
                         op: op,
                         timestamp: ts,
                         deviceAbbrev: String(deviceToken),
                         context: String(contextToken),
                         random: String(randomToken),
                         revision: revision,
                         syncState: sync)
    }
}
