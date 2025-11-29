import Foundation

/// TR4A系のSOHレスポンスをパースし、待ち受けているコマンド完了ハンドラへ振り分ける小さなルーター。
/// - Note: 温度フレーム以外（設定読み取り/書き込みなど）のレスポンスを扱いたいため、NotifyControllerから生のDataを渡す想定。
final class TR4ACommandRouter {
    struct Response {
        let command: UInt8
        let status: UInt8
        let payload: Data
    }

    enum CommandError: Error {
        case timeout
        case invalidFrame
    }

    private let queue = DispatchQueue(label: "BLE.TR4A.CommandRouter")
    private var waiters: [UUID: Pending] = [:]

    private struct Pending {
        let command: UInt8
        let timeout: DispatchWorkItem
        let completion: (Result<Response, CommandError>) -> Void
    }

    func clear() {
        queue.async {
            self.waiters.values.forEach { $0.timeout.cancel() }
            self.waiters.removeAll()
        }
    }

    /// TR4AのSOHレスポンスを受け取り、登録済みのハンドラへ配送する。
    func handle(_ data: Data) {
        guard let parsed = parse(data) else { return }
        queue.async {
            guard let (id, waiter) = self.waiters.first(where: { $0.value.command == parsed.command }) else { return }
            waiter.timeout.cancel()
            self.waiters.removeValue(forKey: id)
            waiter.completion(.success(parsed))
        }
    }

    /// 特定のコマンド応答を待つ。タイムアウトすると .timeout が返る。
    func waitFor(command: UInt8, timeout: TimeInterval = 2.0, completion: @escaping (Result<Response, CommandError>) -> Void) {
        let id = UUID()
        let work = DispatchWorkItem { [weak self] in
            self?.queue.async {
                self?.waiters.removeValue(forKey: id)
                completion(.failure(.timeout))
            }
        }
        queue.async {
            self.waiters[id] = Pending(command: command, timeout: work, completion: completion)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
    }
}

private extension TR4ACommandRouter {
    /// TR4AのSOHフレームをシンプルにバリデーションし、コマンド・ステータス・ペイロードを返す。
    func parse(_ data: Data) -> Response? {
        guard data.count >= 6 else { return nil }
        guard data[0] == 0x01 else { return nil }

        let size = Int((UInt16(data[3]) << 8) | UInt16(data[4]))
        let payloadStart = 6
        let total = payloadStart + size
        guard data.count >= total else { return nil }

        let command = data[1]
        let status = data[5]
        let payload = data[payloadStart..<total]
        return Response(command: command, status: status, payload: Data(payload))
    }
}
