//
//  SessionRecorder.swift
//  PitTemp
//

import Combine
import Foundation

protocol SessionRecording: AnyObject {
    var samples: [TemperatureSample] { get }
    func bind(to stream: AnyPublisher<TemperatureSample, Never>)
    func reset()
}

protocol SessionSampleStore {
    func append(_ sample: TemperatureSample)
    func reset()
}

/// ストリームを受け取り、配列保持＋永続層へ委譲する役。
final class SessionRecorder: ObservableObject, SessionRecording {
    @Published private(set) var samples: [TemperatureSample] = []
    private var cancellables = Set<AnyCancellable>()
    private let store: SessionSampleStore

    // メモリ過大を防ぐための最大保持数（例：5分×5Hz=1500）
    private let maxKeep: Int

    init(store: SessionSampleStore = FileSessionStore(), maxKeep: Int = 3000) {
        self.store = store
        self.maxKeep = maxKeep
    }

    func bind(to stream: AnyPublisher<TemperatureSample, Never>) {
        stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in
                guard let self else { return }
                samples.append(s)
                if samples.count > maxKeep { samples.removeFirst(samples.count - maxKeep) }
                store.append(s)
            }
            .store(in: &cancellables)
    }

    func reset() {
        cancellables.removeAll()
        samples.removeAll()
        store.reset() // 新規ファイルに切替（必要なら既存継続も選べる）
    }
}

