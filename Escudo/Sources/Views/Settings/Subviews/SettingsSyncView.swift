//
//  SettingsSyncView.swift
//  Escudo
//

import SwiftUI
import BackgroundTasks

struct SettingsSyncView: View {
    @Environment(\.presentationMode) var presentationMode

    @AppStorage("autoSyncEnabled", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
    var autoSyncEnabled: Bool = false

    @AppStorage("syncHour", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
    var syncHour: Int = 8

    @AppStorage("syncMinute", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
    var syncMinute: Int = 0

    var selectedTime: Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = syncHour
        comps.minute = syncMinute
        return Calendar.current.date(from: comps) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Auto Sync")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(Color.PrimaryText)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button { presentationMode.wrappedValue.dismiss() } label: {
                        SettingsBackButton()
                    }
                }
                .padding(.bottom, 20)

            VStack(spacing: 0) {
                HStack {
                    Text("Enable Auto Sync")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(Color.PrimaryText)
                    Spacer()
                    Toggle("", isOn: $autoSyncEnabled)
                        .labelsHidden()
                        .tint(Color.IncomeGreen)
                        .onChange(of: autoSyncEnabled) { enabled in
                            if enabled {
                                BankSyncCoordinator.scheduleBackgroundSync()
                            } else {
                                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.sugarhashira.Escudo.sync")
                            }
                        }
                }
                .padding(13)

                if autoSyncEnabled {
                    Divider().padding(.leading, 13)

                    HStack {
                        Text("Sync Time")
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(Color.PrimaryText)
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { selectedTime },
                                set: { date in
                                    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                                    syncHour = comps.hour ?? 8
                                    syncMinute = comps.minute ?? 0
                                    BankSyncCoordinator.scheduleBackgroundSync()
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(13)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
            .animation(.easeInOut(duration: 0.2), value: autoSyncEnabled)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
        .navigationBarHidden(true)
    }
}
