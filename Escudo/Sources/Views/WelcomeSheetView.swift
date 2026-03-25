import Foundation
import SwiftUI
import UIKit

struct WelcomeStartView: View {
    var onBack: () -> Void
    var onDismiss: () -> Void

    @State private var showImport = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(Color.SubtitleText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.horizontal, 30)

            Spacer()

            Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.bottom, 24)

            Text("How would you like to start?")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundColor(Color.PrimaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.bottom, 8)

            Text("You can always import data later from Settings.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(Color.SubtitleText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 14) {
                Button(action: onDismiss) {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start Fresh")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text("Begin with an empty account")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .opacity(0.7)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.5)
                    }
                    .foregroundColor(Color.LightIcon)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.DarkBackground))
                }

                Button {
                    showImport = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Import from File")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text("Load a CSV or OFX statement")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .opacity(0.7)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.5)
                    }
                    .foregroundColor(Color.PrimaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.SecondaryBackground))
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
        .fullScreenCover(isPresented: $showImport) {
            ImportDataView()
        }
    }
}

struct WelcomeSheetFeatureRow: Hashable {
    let icon: String
    let header: String
    let subtitle: String
}

struct WelcomeSheetView: View {
    @Environment(\.dismiss) var dismiss

    @FetchRequest(sortDescriptors: [
        SortDescriptor(\.dateCreated)
    ]) private var categories: FetchedResults<Category>

    @State var firstPage = true
    @State var visibleLines: Int = 0

    let timer = Timer.publish(every: 0.16, on: .main, in: .common).autoconnect()

    let welcomeFeatures = [
        WelcomeSheetFeatureRow(icon: "building.columns.fill", header: "Connect your banks", subtitle: "Link Trading 212, Revolut, Bankinter PT and SIBS via secure Open Banking."),
        WelcomeSheetFeatureRow(icon: "chart.bar.xaxis", header: "Track spending & investments", subtitle: "See your net worth, budgets, and portfolio in one place."),
        WelcomeSheetFeatureRow(icon: "lock.shield.fill", header: "Everything stays on your phone", subtitle: "No account, no backend. Your data lives in the iOS Keychain and on-device storage.")
    ]

    var body: some View {
        VStack {
            if firstPage {
                VStack(spacing: 50) {
                    VStack(spacing: 2) {
                        Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                            .resizable()
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .padding(.bottom, 20)

                        Text("Escudo")
                            .font(.system(size: 30, weight: .medium, design: .rounded))
                            .foregroundColor(Color.PrimaryText)

                        Text("Version \(UIApplication.appVersion ?? "") (\(UIApplication.buildNumber ?? ""))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Color.SubtitleText)
                            .padding(.bottom, 15)
                    }
                    .frame(height: UIScreen.main.bounds.height / 3.4, alignment: .bottom)
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(welcomeFeatures.indices, id: \.self) { rowIndex in
                            if rowIndex < visibleLines {
                                HStack(alignment: .top, spacing: 15) {
                                    Image(systemName: welcomeFeatures[rowIndex].icon)
                                        .font(.system(size: 25, weight: .regular))
                                        .foregroundColor(Color.SubtitleText)
                                        .frame(width: 40, alignment: .leading)
                                        .offset(y: 2)

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(welcomeFeatures[rowIndex].header)
                                            .font(.system(size: 18, weight: .medium, design: .rounded))
                                            .foregroundColor(Color.PrimaryText)

                                        Text(welcomeFeatures[rowIndex].subtitle)
                                            .font(.system(size: 16, weight: .regular, design: .rounded))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                }
                                .transition(AnyTransition.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onReceive(timer) { _ in
                        withAnimation(.easeInOut(duration: 0.4)) {
                            if visibleLines < 3 {
                                visibleLines += 1
                            } else {
                                timer.upstream.connect().cancel()
                            }
                        }
                    }

                    Button {
                        withAnimation {
                            firstPage = false
                        }
                    } label: {
                        Text("Get Started")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.LightIcon)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.DarkBackground))
                    }
                }
                .padding(30)
            } else {
                WelcomeStartView(onBack: {
                    withAnimation { firstPage = true }
                }, onDismiss: {
                    dismiss()
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.PrimaryBackground)
    }
}
