//
//  ConnectivityMonitor.swift
//  PitTemp
//
//  役割: ネットワーク到達性を監視し、UI 側から「いまオンラインか」
//  を安全に参照できるようにする ObservableObject。
//  初学者メモ:
//   - Network.framework の NWPathMonitor は iOS で標準提供される
//     リーチャビリティ API。回線が切れてもクラッシュしないよう、
//     モニターは強参照で保持し、メインスレッドへ状態を中継する。
//   - Combine の @Published を通じてビューに変更を伝えられる。
//

import Foundation
import Network

final class ConnectivityMonitor: ObservableObject {
    // "現在オンラインか" を画面に公開するプロパティ。デフォルトは true。
    // ※オフライン時に Save したいケースでも UI が止まらないよう、
    //   明示的に false が届くまで true で動作させています。
    @Published var isOnline: Bool = true

    // NWPathMonitor はライフタイム中 1 つを保持する。
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PitTemp.ConnectivityMonitor")

    init() {
        // モニター開始と同時にハンドラを登録。
        // ハンドラの中で self を参照するため [weak self] を付けて循環参照を防ぐ。
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        // View が破棄される際に監視を停止してリソースリークを防ぐ。
        monitor.cancel()
    }
}
