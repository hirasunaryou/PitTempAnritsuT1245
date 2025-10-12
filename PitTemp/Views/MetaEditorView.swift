import SwiftUI

struct MetaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: SessionViewModel
    @EnvironmentObject var settings: SettingsStore   // ⬅️ 追加

    @State private var blockExternalKeys = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Block external keyboard while editing", isOn: $blockExternalKeys)
                        .tint(.orange)
                        .font(.footnote)
                }

                Section("Session") {
                    TextField("TRACK", text: $vm.meta.track)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("DATE (ISO8601)", text: $vm.meta.date)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("TIME", text: $vm.meta.time).keyboardType(.numbersAndPunctuation)
                        TextField("LAP",  text: $vm.meta.lap).keyboardType(.numbersAndPunctuation)
                    }
                }

                Section("Car & People") {
                    TextField("CAR", text: $vm.meta.car)
                    TextField("DRIVER", text: $vm.meta.driver)
                    TextField("TYRE", text: $vm.meta.tyre)
                    TextField("CHECKER", text: $vm.meta.checker)
                }

                Section {
                    // ⬇ ここを settings に変更
                    Toggle("Autofill Date/Time if empty", isOn: $settings.autofillDateTime)
                }
            }
            .navigationTitle("Edit Meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }

        }
        .onAppear { vm.stopAll() }
    }
}
