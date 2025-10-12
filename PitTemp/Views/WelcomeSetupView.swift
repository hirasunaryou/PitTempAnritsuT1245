//
//  WelcomeSetupView.swift
//  PitTemp


// WelcomeSetupView.swift
// 初回起動で Checker（使う人）と HR-2500 の名前を保存するビュー。
// 2回目以降は AppStorage の値で自動入力済み → Continue でメインへ。

import SwiftUI

struct WelcomeSetupView: View {
    // 永続保存（UserDefaultsベース）
    @AppStorage("profile.checker") private var checker: String = ""
    @AppStorage("hr2500.id") private var hr2500ID: String = ""

    // 1回表示したかどうか
    @AppStorage("onboarded") private var onboarded: Bool = false

    // もし KeyboardWatcher を入れていれば候補を出せる
//    @EnvironmentObject var kb: KeyboardWatcher

    // 入力用の一時バッファ（編集中のみ）
    @State private var checkerDraft: String = ""
    @State private var hrDraft: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // タイトル
                VStack(spacing: 8) {
                    Text("Welcome to PitTemp")
                        .font(.largeTitle).bold()
                    Text("Please confirm who uses the app and which thermometer.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                Form {
                    Section("Checker") {
                        TextField("Your name (ex. TAKESHI)", text: $checkerDraft)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                    }
                    Section("Thermometer") {
                        TextField("Device name (ex. HR-P20230)", text: $hrDraft)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

//                        // 接続キーボード名から候補をワンタップ反映
//                        if let cand = kb.hrCandidateID {
//                            Button("Use detected: \(cand)") { hrDraft = cand }
//                        }
//                        if !kb.connectedNames.isEmpty {
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text("Connected Keyboards")
//                                    .font(.caption).foregroundStyle(.secondary)
//                                ForEach(kb.connectedNames, id: \.self) { Text("• \($0)").font(.caption) }
//                            }
//                        }
                    }
                }

                Button {
                    // 空なら既存値にフォールバック（2回目以降も“そのまま続行”を許す）
                    let c = checkerDraft.trimmingCharacters(in: .whitespaces)
                    let h = hrDraft.trimmingCharacters(in: .whitespaces)
                    if !c.isEmpty { checker = c }
                    if !h.isEmpty { hr2500ID = h }
                    onboarded = true
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Spacer(minLength: 12)
            }
            .navigationTitle("Quick Setup")
        }
        .onAppear {
            // 既存値があれば初期表示に反映（確認→そのままContinueできる）
            checkerDraft = checker
            hrDraft = hr2500ID
        }
    }
}

