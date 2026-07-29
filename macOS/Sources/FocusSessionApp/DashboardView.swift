import FocusSessionCore
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    SummaryRow(
                        title: "Sessions",
                        value: "\(model.summary.sessionCount)"
                    )
                    SummaryRow(
                        title: "Protected session time",
                        value: DurationText.readable(
                            model.summary.totalFocusedSeconds
                        )
                    )
                    SummaryRow(
                        title: "Focus intervals",
                        value: "\(model.summary.completedFocusIntervals)"
                    )
                    SummaryRow(
                        title: "Breaks",
                        value: "\(model.summary.breaksTaken)"
                    )
                    SummaryRow(
                        title: "Break time used",
                        value: DurationText.readable(
                            model.summary.breakSecondsUsed
                        )
                    )
                    SummaryRow(
                        title: "Shot-clock extensions",
                        value: "\(model.summary.breakExtensions)"
                    )
                    SummaryRow(
                        title: "Extension time",
                        value: DurationText.readable(
                            model.summary.breakOvertimeSeconds
                        )
                    )
                    SummaryRow(
                        title: "Early endings",
                        value: "\(model.summary.earlyEndings)"
                    )
                } header: {
                    Text("Overview")
                } footer: {
                    Text(
                        "Protected session time is elapsed wall-clock session "
                            + "time minus claimed break time. It can include "
                            + "sleep, lock, or time away; it does not measure "
                            + "attention or productive work."
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                Text("Session history")
                    .font(.title2.weight(.semibold))

                if model.history.isEmpty {
                    ContentUnavailableView(
                        "No sessions yet",
                        systemImage: "chart.bar",
                        description: Text(
                            "Completed and early-ended sessions appear here."
                        )
                    )
                } else {
                    Table(model.history) {
                        TableColumn("Started") { record in
                            Text(
                                record.startedAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                        }
                        TableColumn("Result") { record in
                            Text(
                                record.endReason == .completed
                                    ? "Completed"
                                    : "Ended early"
                            )
                        }
                        TableColumn("Breaks") { record in
                            Text("\(record.counters.breaksTaken)")
                        }
                        TableColumn("Extensions") { record in
                            Text("\(record.counters.breakExtensions)")
                        }
                        TableColumn("") { record in
                            Button(role: .destructive) {
                                model.deleteHistoryRecord(id: record.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this local session record")
                        }
                        .width(36)
                    }
                }

                if !model.summary.blockedAttempts.isEmpty {
                    Divider()
                    Text("Blocked attempts")
                        .font(.headline)
                    aggregateRows(model.summary.blockedAttempts)
                }

                if !model.summary.restrictedServiceSeconds.isEmpty {
                    Divider()
                    Text("Restricted-service time during breaks")
                        .font(.headline)
                    durationRows(model.summary.restrictedServiceSeconds)
                }
            }
            .padding(24)
        }
        .onAppear {
            model.refresh()
        }
    }

    private func aggregateRows(_ values: [String: Int]) -> some View {
        VStack(spacing: 6) {
            ForEach(
                values.sorted { $0.value > $1.value },
                id: \.key
            ) { item in
                HStack {
                    Text(item.key)
                    Spacer()
                    Text("\(item.value)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func durationRows(
        _ values: [String: TimeInterval]
    ) -> some View {
        VStack(spacing: 6) {
            ForEach(
                values.sorted { $0.value > $1.value },
                id: \.key
            ) { item in
                HStack {
                    Text(item.key)
                    Spacer()
                    Text(DurationText.readable(item.value))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
