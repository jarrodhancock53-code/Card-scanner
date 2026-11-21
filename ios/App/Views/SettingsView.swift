import SwiftUI
import PackRipCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var data: DataStore
    @State private var message: String?
    @State private var updating = false

    var body: some View {
        Form {
            Section("Card data") {
                Text("\(data.sets.count) sets, prices from \(data.prices.updatedAt.isEmpty ? "unknown" : data.prices.updatedAt)")
                TextField("Data folder URL (https://...)", text: $model.dataURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button(updating ? "Updating..." : "Update data now") {
                    guard let url = URL(string: model.dataURL), url.scheme?.hasPrefix("http") == true else {
                        message = "Enter the URL of the folder that holds sets.json."; return
                    }
                    updating = true
                    Task {
                        do { try await data.update(from: url); message = "Updated." }
                        catch { message = "Update failed: \(error.localizedDescription)" }
                        updating = false
                    }
                }.disabled(updating)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Recap") {
                Stepper("A hit is worth \(Recapper.money(model.hitThreshold)) or more", value: $model.hitThreshold, in: 1...100, step: 1)
            }
            Section("About") {
                Text("Free Apple ID builds stop opening after 7 days. Plug in your phone and press Run in Xcode to reinstall.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

