//
//  MiniTempChart.swift
//  PitTemp
//
//  役割: ライブ温度の折れ線＋点、左Y軸表示
//  初心者向けメモ: iOS 16+ の Swift Charts を使用（import Charts）
//

import SwiftUI
import Charts

struct MiniTempChart: View {
    let data: [TempSample]

    var body: some View {
        let ys = data.map{$0.c}; let pad = 0.5
        let yMin = (ys.min() ?? 0) - pad, yMax = (ys.max() ?? 1) + pad
        let last = data.last?.c

        Chart {
            ForEach(data) { d in
                LineMark(x: .value("t", d.ts), y: .value("c", d.c))
                    .interpolationMethod(.monotone)
            }
            ForEach(data) { d in
                PointMark(x: .value("t", d.ts), y: .value("c", d.c))
            }
            if let l = last, let t = data.last?.ts {
                PointMark(x: .value("t", t), y: .value("c", l)).symbolSize(80)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine(); AxisTick()
                if let d = v.as(Double.self) {
                    AxisValueLabel { Text(String(format: "%.0f℃", d)).monospacedDigit() }
                }
            }
        }
        .chartYScale(domain: yMin...yMax)
        .frame(height: 110)
    }
}
