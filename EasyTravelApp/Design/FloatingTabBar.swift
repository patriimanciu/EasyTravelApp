import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case trips
    case inbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trips: "Trips"
        case .inbox: "Inbox"
        }
    }

    var icon: String {
        switch self {
        case .trips: "house.fill"
        case .inbox: "tray.full.fill"
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var inboxBadge: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .semibold))
                            if tab == .inbox, inboxBadge > 0 {
                                Text(inboxBadge > 99 ? "99+" : "\(inboxBadge)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 8, y: -6)
                            }
                        }
                        Text(tab.title)
                            .font(.caption2.weight(selection == tab ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == tab ? AppTheme.accent : AppTheme.accent.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(AppTheme.cardBackground, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
    }
}
