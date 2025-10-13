//
//  SettingsView.swift
//  PitTemp
//
//  役割: 共有フォルダの指定、測定窓/グラフ幅など各種設定
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var vm: SessionViewModel
    @EnvironmentObject var folderBM: FolderBookmark
    @EnvironmentObject var settings: SettingsStore   // ← 追加：設定は SettingsStore に集約

    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                // プロファイル
                Section("Profile") {
                    // checker は SettingsStore 側に寄せていないため、必要なら移設可。
                    // ここでは既存キーを流用する形で統一するため SettingsStore に追加して使うのが綺麗です。
                    // ひとまずキーをそのまま使いたい場合は、下行のように @AppStorage を残すか、
                    // SettingsStore に @AppStorage("profile.checker") を追加して $settings.checker にしてください。
                    TextField("Checker", text: .init(
                        get: { UserDefaults.standard.string(forKey: "profile.checker") ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: "profile.checker") }
                    ))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                    HStack {
                        TextField("Thermometer (HR-...)", text: $settings.hr2500ID) // ← SettingsStore を参照
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    Button("Show Welcome on next launch") {
                        UserDefaults.standard.set(false, forKey: "onboarded")
                    }
                    .tint(.orange)
                }

                // 共有フォルダ
                Section("Shared Folder") {
                    HStack {
                        Text("Upload Folder")
                        Spacer()
                        Text(folderBM.folderURL?.lastPathComponent ?? "Not set")
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose iCloud Folder…") { showPicker = true }
                }
                
                Section("Meta Input") {
                    Picker("Mode", selection: Binding(
                        get: { settings.metaInputMode },
                        set: { settings.metaInputMode = $0 }
                    )) {
                        ForEach(SettingsStore.MetaInputMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                }


                // 測定パラメータ
                Section("Measurement") {
                    Stepper(value: $settings.durationSec, in: 2...20) {
                        Text("Window: \(settings.durationSec) s")
                    }
                    Stepper(value: $settings.chartWindowSec, in: 3...60, step: 1) {
                        Text("Chart Width: \(Int(settings.chartWindowSec)) s")
                    }
                    Toggle("Autofill Date/Time if empty", isOn: $settings.autofillDateTime)
                    
                    // 👇 追加：Zone順序の切替
                    Picker(
                        "Zone order",
                        selection: Binding(
                            get: { settings.zoneOrderEnum },
                            set: { settings.zoneOrderEnum = $0 }
                        )
                    ) {
                        ForEach(SettingsStore.ZoneOrder.allCases) { o in
                            Text(o.label).tag(o)
                        }
                    }
                }
                
                Section("Bluetooth") {
                    Toggle("Auto connect first seen device", isOn: $settings.bleAutoConnect)
                        .onChange(of: settings.bleAutoConnect) { _, newValue in
                            // ここは必要なら反映を書く（MeasureView 側で反映しているなら何もしなくてOK）
                            // 例）ble.autoConnectOnDiscover = newValue
                            // 'onChange(of:perform:)' was deprecated in iOS 17.0: Use `onChange` with a two or zero parameter action closure instead.
                        }

                    Text("If ON, the app connects to the first matching device it discovers. Turn OFF to pick a device manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                
                // デバイス & ロケーション
                Section("Device & Location") {
                    TextField("HR2500 ID (label / asset tag)", text: $settings.hr2500ID)

                    HStack {
                        let status = LocationLogger.shared.authStatus
                        Text("Location: \(String(describing: status))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Enable") { LocationLogger.shared.request() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false   // フォルダは1つで十分
        ) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first { folderBM.save(url: first) }
            case .failure(let error):
                print("Folder pick failed:", error)
            }
        }
    }
}
