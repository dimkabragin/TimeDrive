import SwiftUI

struct CompactSettingsPanel: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "settings.title"))
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "settings.timer.section"))
                        .font(.subheadline.weight(.semibold))

                    Stepper(value: $viewModel.workDurationMinutes, in: 1...180) {
                        Text(String(format: String(localized: "settings.workFormat"), String(viewModel.workDurationMinutes)))
                    }

                    Stepper(value: $viewModel.breakDurationMinutes, in: 1...60) {
                        Text(String(format: String(localized: "settings.breakFormat"), String(viewModel.breakDurationMinutes)))
                    }

                    Button(String(localized: "settings.saveDurations")) {
                        viewModel.saveDurations()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .panelSectionStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "settings.behavior.section"))
                        .font(.subheadline.weight(.semibold))

                    Toggle(String(localized: "settings.autoStart"), isOn: $viewModel.autoStartNext)

                    Button(String(localized: "settings.apply")) {
                        viewModel.saveAutoStartNext()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .panelSectionStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "settings.sync.section"))
                        .font(.subheadline.weight(.semibold))

                    detailRow(title: String(localized: "sync.connectivity"), value: viewModel.syncStatus.isOnlinePlaceholder ? String(localized: "sync.online") : String(localized: "sync.offline"))
                    detailRow(title: String(localized: "sync.pending"), value: "\(viewModel.syncStatus.pendingOperations)")
                    detailRow(title: String(localized: "sync.lastSync"), value: viewModel.syncStatus.lastSyncText)

                    Button(viewModel.isSyncingNow ? String(localized: "sync.syncing") : String(localized: "sync.now")) {
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
