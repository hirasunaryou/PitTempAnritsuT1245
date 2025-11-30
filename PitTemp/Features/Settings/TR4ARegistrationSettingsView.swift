import SwiftUI

/// TR45 ごとの登録コードを保存・編集するシンプルな画面。
struct TR4ARegistrationSettingsView: View {
    @EnvironmentObject var registry: DeviceRegistry
    @EnvironmentObject var registrationStore: TR4ARegistrationStore

    @State private var newIdentifier: String = ""
    @State private var newCode: String = ""

    var body: some View {
        Form {
            Section("Known devices") {
                if registry.known.isEmpty {
                    Text("Scan or connect once to list TR45 devices here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(registry.known) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.name)
                            .font(.headline)
                        Text("Identifier: \(record.id)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("Registration code (8 digits)",
                                  text: Binding(
                                    get: { registrationStore.code(for: record.id) ?? "" },
                                    set: { registrationStore.set(code: $0, for: record.id) }
                                  ))
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    .padding(.vertical, 6)
                }
            }

            Section("Manual entry") {
                TextField("Device identifier (serial or UUID)", text: $newIdentifier)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
                TextField("Registration code (8 digits)", text: $newCode)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
                Button("Save code") {
                    registrationStore.set(code: newCode, for: newIdentifier)
                    newIdentifier = ""
                    newCode = ""
                }
                .disabled(newIdentifier.isEmpty || newCode.count != 8)
            }

            Section {
                Text("登録コードは TR45 ごとに 8 桁の 10 進数で指定します。セキュリティ ON の機体では、ここで保存したコードだけを 0x76 パスコードコマンドとして送信し、OFF 機では送信しません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("TR45 Registration Codes")
    }
}

