//
//  DeviceRegistryView.swift
//  PitTemp
//

import SwiftUI

/// 既知デバイス一覧 → 1台を選んで編集
struct DeviceRegistryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var registry: DeviceRegistry

    var body: some View {
        List {
            if registry.known.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No known devices yet")
                            .font(.headline)
                        Text("Scan for devices from the Measure screen, then they will appear here.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                Section("Known Devices") {
                    ForEach(sortedKnown()) { rec in
                        NavigationLink {
                            DeviceRegistryDetailView(device: rec)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(rec))
                                        .font(.body)
                                    Text(rec.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if rec.autoConnect {
                                    Label("Preferred", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Device Registry")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private func sortedKnown() -> [DeviceRecord] {
        registry.known.sorted { a, b in
            // 1) lastSeen desc  2) name asc
            let ta = a.lastSeenAt ?? .distantPast
            let tb = b.lastSeenAt ?? .distantPast
            if ta != tb { return ta > tb }
            return a.name < b.name
        }
    }

    private func displayName(_ rec: DeviceRecord) -> String {
        if let alias = rec.alias, !alias.isEmpty { return alias }
        return rec.name
    }
}

/// 1台分の編集画面：エイリアス/優先/忘却
struct DeviceRegistryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var registry: DeviceRegistry

    let device: DeviceRecord

    @State private var alias: String = ""
    @State private var autoConnect: Bool = false

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("ID") { Text(device.id).textSelection(.enabled) }
                LabeledContent("Original Name") { Text(device.name) }
                if let t = device.lastSeenAt {
                    LabeledContent("Last Seen") { Text(rel(t)) }
                }
                if let rssi = device.lastRSSI {
                    LabeledContent("RSSI") { Text("\(rssi) dBm") }
                }
            }

            Section("Edit") {
                TextField("Alias (nickname)", text: $alias)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("Prefer auto-connect", isOn: $autoConnect)
            }

            Section {
                Button(role: .destructive) {
                    registry.forget(id: device.id)
                    dismiss()
                } label: {
                    Label("Forget this device", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Edit Device")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    registry.setAlias(alias.isEmpty ? nil : alias, for: device.id)
                    registry.setAutoConnect(autoConnect, for: device.id)
                    dismiss()
                }
            }
        }
        .onAppear {
            alias = device.alias ?? ""
            autoConnect = device.autoConnect
        }
    }

    private func rel(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 2 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        let d = h / 24
        return "\(d)d ago"
    }
}
