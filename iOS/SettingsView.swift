import SwiftUI

private struct Weekday: Identifiable {
    let calendarValue: Int
    let label: String
    let shortLabel: String
    var id: Int { calendarValue }

    static var ordered: [Weekday] {
        let symbols = Calendar.current.weekdaySymbols
        let shortSymbols = Calendar.current.shortWeekdaySymbols
        return (0..<7).map { offset in
            let value = ((Calendar.current.firstWeekday - 1 + offset) % 7) + 1
            return Weekday(
                calendarValue: value,
                label: symbols[value - 1],
                shortLabel: shortSymbols[value - 1]
            )
        }
    }
}

private enum TimeDisplay {
    static func date(for minutes: Int) -> Date {
        let anchor = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15))!
        return Calendar.current.date(byAdding: .minute, value: minutes, to: anchor)!
    }

    static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func text(for minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date(for: minutes))
    }
}

final class PhoneSettingsModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published var errorMessage: String?
    let sync = PhoneWatchSync()

    init() {
        settings = SettingsStore.load() ?? AppSettings(
            plans: [],
            snoozeMinutes: AppSettings.defaultSnoozeMinutes
        )
        sync.publish(settings)
    }

    @discardableResult
    func save(_ proposed: AppSettings) -> Bool {
        if let error = proposed.validationErrors().first {
            errorMessage = error.localizedDescription
            return false
        }
        do {
            try SettingsStore.save(proposed)
            settings = proposed
            errorMessage = nil
            sync.publish(proposed)
            return true
        } catch {
            errorMessage = "Could not save settings: \(error.localizedDescription)"
            return false
        }
    }

    func upsert(_ plan: SchedulePlan) -> Bool {
        var proposed = settings
        if let index = proposed.plans.firstIndex(where: { $0.id == plan.id }) {
            proposed.plans[index] = plan
        } else {
            proposed.plans.append(plan)
        }
        return save(proposed)
    }

    func remove(at offsets: IndexSet) {
        var proposed = settings
        proposed.plans.remove(atOffsets: offsets)
        _ = save(proposed)
    }

    func setEnabled(_ enabled: Bool, for plan: SchedulePlan) {
        var changed = plan
        changed.isEnabled = enabled
        _ = upsert(changed)
    }

    func setSnoozeMinutes(_ minutes: Int) {
        var proposed = settings
        proposed.snoozeMinutes = minutes
        _ = save(proposed)
    }
}

struct SettingsView: View {
    @StateObject private var model = PhoneSettingsModel()
    @State private var editingPlan: SchedulePlan?
    @State private var showingNewPlan = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.settings.plans.isEmpty {
                        Text("Add a plan to choose when your watch reminds you to take breaks.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.settings.plans, id: \.id) { plan in
                        HStack(spacing: 12) {
                            Button {
                                editingPlan = plan
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(TimeDisplay.text(for: plan.startMinutes))–\(TimeDisplay.text(for: plan.endMinutes))")
                                        .font(.headline)
                                    Text(daysText(for: plan))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Toggle("Enabled", isOn: Binding(
                                get: { plan.isEnabled },
                                set: { model.setEnabled($0, for: plan) }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onDelete(perform: model.remove)
                    Button("Add Plan", systemImage: "plus") {
                        showingNewPlan = true
                    }
                } header: {
                    Text("Plans")
                } footer: {
                    Text("Each plan uses one time window for its selected days. Overnight windows belong to the day they start. Active windows cannot overlap.")
                }

                Section("Reminders") {
                    Picker("Snooze duration", selection: Binding(
                        get: { model.settings.snoozeMinutes },
                        set: { model.setSnoozeMinutes($0) }
                    )) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                }

                Section("Apple Watch") {
                    WatchSyncStatusView(sync: model.sync)
                }
            }
            .navigationTitle("promodoro20")
            .sheet(item: $editingPlan) { plan in
                PlanEditor(plan: plan, onSave: savePlan)
            }
            .sheet(isPresented: $showingNewPlan) {
                PlanEditor(
                    plan: SchedulePlan(
                        weekdays: Set([2, 3, 4, 5, 6]),
                        startMinutes: 9 * 60,
                        endMinutes: 17 * 60
                    ),
                    onSave: savePlan
                )
            }
            .alert("Cannot Save Settings", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func daysText(for plan: SchedulePlan) -> String {
        let selected = Weekday.ordered.filter { plan.weekdays.contains($0.calendarValue) }
        if selected.count == 7 { return "Every day" }
        return selected.map(\.shortLabel).joined(separator: ", ")
    }

    private func savePlan(_ plan: SchedulePlan) -> String? {
        guard !model.upsert(plan) else { return nil }
        let message = model.errorMessage ?? "Could not save this plan."
        model.errorMessage = nil
        return message
    }
}

private struct WatchSyncStatusView: View {
    @ObservedObject var sync: PhoneWatchSync

    var body: some View {
        Text(sync.status)
            .foregroundStyle(.secondary)
    }
}

private struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var plan: SchedulePlan
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var localError: String?
    let onSave: (SchedulePlan) -> String?

    init(plan: SchedulePlan, onSave: @escaping (SchedulePlan) -> String?) {
        _plan = State(initialValue: plan)
        _startTime = State(initialValue: TimeDisplay.date(for: plan.startMinutes))
        _endTime = State(initialValue: TimeDisplay.date(for: plan.endMinutes))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Repeat") {
                    ForEach(Weekday.ordered) { day in
                        Toggle(day.label, isOn: Binding(
                            get: { plan.weekdays.contains(day.calendarValue) },
                            set: { selected in
                                if selected { plan.weekdays.insert(day.calendarValue) }
                                else { plan.weekdays.remove(day.calendarValue) }
                            }
                        ))
                    }
                }

                Section {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Time window")
                } footer: {
                    Text("An end time before the start time means the window ends the next day.")
                }

                Section {
                    Toggle("Enabled", isOn: $plan.isEnabled)
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .alert("Check This Plan", isPresented: Binding(
                get: { localError != nil },
                set: { if !$0 { localError = nil } }
            )) {
                Button("OK") { localError = nil }
            } message: {
                Text(localError ?? "")
            }
        }
    }

    private func save() {
        guard !plan.weekdays.isEmpty else {
            localError = "Select at least one day."
            return
        }
        plan.startMinutes = TimeDisplay.minutes(from: startTime)
        plan.endMinutes = TimeDisplay.minutes(from: endTime)
        guard plan.startMinutes != plan.endMinutes else {
            localError = "Choose different start and end times."
            return
        }
        if let error = onSave(plan) {
            localError = error
        } else {
            dismiss()
        }
    }
}
