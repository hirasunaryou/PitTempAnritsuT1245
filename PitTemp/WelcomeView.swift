//
//  WelcomeView.swift
//  PitTemp
//
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject var folderBM: FolderBookmark
    @AppStorage("profile.checker") private var checker: String = ""
    @AppStorage("hr2500.id") private var hr2500ID: String = ""   // “例: HR-P20230”
    @State private var showPicker = false

    var onContinue: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Who & Device") {
                    TextField("Checker", text: $checker)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Thermometer (e.g. HR-P20230)", text: $hr2500ID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .placeholder(when: hr2500ID.isEmpty) {
                            Text("e.g. HR-P20230").foregroundStyle(.secondary)
                        }
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
                Section {
                    Button(role: .none) {
                        // 軽ハプティクスは呼び出し側で。ここは念のため二重でもOK
                        Haptics.impactLight()
                        onContinue()
                    } label: {
                        Label("Continue", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checker.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Welcome")
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                folderBM.save(url: first)
            }
        }
    }
}

// 小さなプレースホルダ拡張（任意）
private extension View {
    func placeholder<Content: View>(when shouldShow: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .leading) { self; if shouldShow { content() } }
    }
}
