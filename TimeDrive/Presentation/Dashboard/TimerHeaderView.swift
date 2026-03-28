import SwiftUI

struct TimerHeaderView: View {
    let snapshot: ActiveTimerSnapshot?
    let displayedMode: TimerMode
    let idleWorkDurationSec: Int
    let idleBreakDurationSec: Int
    let currentTaskTitle: String?
    let activePanel: DashboardPanel?
    let errorMessage: String?
    let onToggleTimer: () -> Void
    let onSelectPanel: (DashboardPanel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(mainTimerText)
                        .font(.system(size: 78, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(mainTimerColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                        .accessibilityLabel(String(localized: "timer.current"))
                        .accessibilityValue(mainTimerText)

                    if let currentTaskTitle, !currentTaskTitle.isEmpty {
                        Text(currentTaskTitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                Button(action: onToggleTimer) {
                    Image(systemName: snapshot == nil ? "play.fill" : "pause.fill")
                        .font(.system(size: 30, weight: .bold))
                        .frame(width: 88, height: 88)
                        .foregroundStyle(.white)
                        .background(snapshot == nil ? Color.accentColor : Color.orange)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .focusEffectDisabled()
                .accessibilityLabel(snapshot == nil ? String(localized: "timer.start") : String(localized: "timer.pause"))
                .accessibilityHint(String(localized: "timer.actionHint"))
            }

            HStack(spacing: 0) {
                ForEach(DashboardPanel.allCases) { panel in
                    Button {
                        onSelectPanel(panel)
                    } label: {
                        Text(panel.title)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 7)
                        .foregroundStyle(activePanel == panel ? Color.white : Color.primary)
                        .background(activePanel == panel ? Color.accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(panel.title)
                    .accessibilityValue(activePanel == panel ? String(localized: "selection.selected") : String(localized: "selection.notSelected"))
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.leading, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .padding(.trailing, 20)
    }

    private var mainTimerText: String {
        guard let snapshot else {
            let idleDuration: Int
            switch displayedMode {
            case .work:
                idleDuration = idleWorkDurationSec
            case .break:
                idleDuration = idleBreakDurationSec
            }
            return formatClock(max(0, idleDuration))
        }
        if snapshot.isInExtraTime {
            return formatClock(snapshot.extraSec)
        }
        return formatClock(max(0, snapshot.remainingSec))
    }

    private var mainTimerColor: Color {
        guard let snapshot, snapshot.isInExtraTime else {
            return .primary
        }

        return Color(red: 0.9, green: 0.4, blue: 0.4)
    }

    private func formatClock(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
