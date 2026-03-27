import SwiftUI

struct CompactSettingsPanel: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Timer")
                        .font(.subheadline.weight(.semibold))

                    Stepper(value: $viewModel.workDurationMinutes, in: 1...180) {
                        Text("Work: \(viewModel.workDurationMinutes) min")
                    }

                    Stepper(value: $viewModel.breakDurationMinutes, in: 1...60) {
                        Text("Break: \(viewModel.breakDurationMinutes) min")
                    }

                    Button("Save Durations") {
                        viewModel.saveDurations()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .panelSectionStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Behavior")
                        .font(.subheadline.weight(.semibold))

                    Toggle("Auto-start next session", isOn: $viewModel.autoStartNext)

                    Button("Apply") {
                        viewModel.saveAutoStartNext()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .panelSectionStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sync")
                        .font(.subheadline.weight(.semibold))

                    detailRow(title: "Connectivity", value: viewModel.syncStatus.isOnlinePlaceholder ? "Online" : "Offline")
                    detailRow(title: "Pending", value: "\(viewModel.syncStatus.pendingOperations)")
                    detailRow(title: "Last sync", value: viewModel.syncStatus.lastSyncText)

                    Button(viewModel.isSyncingNow ? "Syncing..." : "Sync now") {
                        viewModel.syncNow()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isSyncingNow)
                }
                .panelSectionStyle()

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

