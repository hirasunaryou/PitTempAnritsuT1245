//
//  SessionRecorder.swift
//  PitTemp
//

import Foundation
import Combine

/// ストリームを受け取り、配列保持＋CSVへ追記する役。
final class SessionRecorder: ObservableObject {
    @Published private(set) var samples: [TemperatureSample] = []
    private var cancellables = Set<AnyCancellable>()
    private var exporter = CSVExporter()

    // メモリ過大を防ぐための最大保持数（例：5分×5Hz=1500）
    private let maxKeep = 3000

    func bind(to stream: AnyPublisher<TemperatureSample, Never>) {
        stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in
                guard let self else { return }
                samples.append(s)
                if samples.count > maxKeep { samples.removeFirst(samples.count - maxKeep) }
                exporter.appendLive(sample: s)
            }
            .store(in: &cancellables)
    }

    func reset() {
        samples.removeAll()
        exporter = CSVExporter() // 新規ファイルに切替（必要なら既存継続も選べる）
    }
}

