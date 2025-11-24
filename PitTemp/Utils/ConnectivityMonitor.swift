// ConnectivityMonitor.swift
// ネットワーク到達性を UI に伝えるための軽量オブザーバ。
// iOS 標準の NWPathMonitor をラップし、"圏外なのにクラウドに保存された?" という
// ユーザーの不安を和らげるフィードバックの材料として使う。

import Foundation
import Network

/// 画面側でオンライン/オフラインの表示を切り替えるための ObservableObject。
/// - important: アプリ全体で 1 つだけ生成し、environmentObject として渡す前提。
final class ConnectivityMonitor: ObservableObject {
    /// 現在オンラインかどうか。`true` のときのみクラウドアップロードを自動で走らせる。
    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ConnectivityMonitor.queue")

    init() {
        // NWPathMonitor はバックグラウンドキューで監視し、状態変化を MainActor にブリッジする。
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

