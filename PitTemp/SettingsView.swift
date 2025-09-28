//
//  SettingsView.swift
//  PitTemp
//
//  役割: 共有フォルダの指定、測定窓/グラフ幅の設定
//  初心者向けメモ:
//   - SwiftUI の .fileImporter を使って「フォルダ」を選んでもらう
//   - 選んだ URL はブックマーク化して永続保存（iOS のお作法）
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var vm: SessionViewModel
    @EnvironmentObject var folderBM: FolderBookmark

    @State private var showPicker = false
    
    @AppStorage("profile.checker") private var checker: String = ""
    @AppStorage("hr2500.id") private var hr2500ID: String = ""
//    @EnvironmentObject var kb: KeyboardWatcher

    var body: some View {
        NavigationStack {
            Form {
                
                Section("Profile") {
                    TextField("Checker", text: $checker)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("Thermometer (HR-...)", text: $hr2500ID)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
//                        if let cand = kb.hrCandidateID {
//                            Button("Use detected") { hr2500ID = cand }
//                        }
                    }
                    // 必要なら「Reset onboarding」ボタンも
                    Button("Show Welcome on next launch") { UserDefaults.standard.set(false, forKey: "onboarded") }
                        .tint(.orange)
                }
                
                Section("Shared Folder") {
                    HStack {
                        Text("Upload Folder")
                        Spacer()
                        Text(folderBM.folderURL?.lastPathComponent ?? "Not set")
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose iCloud Folder…") { showPicker = true }
                }
                
                Section("Measurement") {
                    Stepper(value: $vm.durationSec, in: 2...20) { Text("Window: \(vm.durationSec) s") }
                    Stepper(value: $vm.chartWindowSec, in: 3...60) { Text("Chart Width: \(Int(vm.chartWindowSec)) s") }
                    Toggle("Autofill Date/Time if empty", isOn: $vm.autofillDateTime)
                }
                
                Section("Device & Location") {
                    TextField("HR2500 ID (label / asset tag)", text: $vm.hr2500ID)

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
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first {
                    folderBM.save(url: first)
                }
            case .failure(let error):
                print("Folder pick failed:", error)
            }
        }
    }
}
