import SwiftUI

/// Soft travel UI — pastel accents, white cards, charcoal primary actions (reference-inspired).
enum AppTheme {
    static let accent = Color("AccentColor")

    static let screenBackground = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let cardBackground = Color.white
    static let elevatedFill = Color(red: 0.94, green: 0.94, blue: 0.96)
    static let charcoal = Color(red: 0.14, green: 0.14, blue: 0.16)

    static let peach = Color(red: 1.0, green: 0.88, blue: 0.82)
    static let peachDeep = Color(red: 0.98, green: 0.72, blue: 0.62)
    static let mint = Color(red: 0.82, green: 0.95, blue: 0.90)
    static let sky = Color(red: 0.82, green: 0.91, blue: 0.98)
    static let lavender = Color(red: 0.90, green: 0.86, blue: 0.98)

    static let cornerRadius: CGFloat = 22
    static let cardCornerRadius: CGFloat = 20
    static let pillRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let pagePadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    static let listRowVerticalPadding: CGFloat = 8
    static let floatingTabClearance: CGFloat = 88
    static let embeddedMapHeight: CGFloat = 220
    static let tripHeroHeight: CGFloat = 210
    static let tripHeroOverlap: CGFloat = 16
    static let categoryChipSize: CGFloat = 64

    static let cardShadow = Color.black.opacity(0.06)
    static let cardShadowRadius: CGFloat = 14
    static let cardShadowY: CGFloat = 6

    static func categoryTint(_ category: LocationItem.Category) -> Color {
        switch category {
        case .landmark: Color(red: 0.35, green: 0.55, blue: 0.95)
        case .museum: Color(red: 0.58, green: 0.42, blue: 0.90)
        case .park: Color(red: 0.32, green: 0.72, blue: 0.52)
        case .neighborhood: Color(red: 0.22, green: 0.62, blue: 0.58)
        case .city: Color(red: 0.30, green: 0.58, blue: 0.88)
        case .restaurant: Color(red: 0.95, green: 0.45, blue: 0.38)
        case .cafe: Color(red: 0.92, green: 0.58, blue: 0.28)
        case .shopping: Color(red: 0.92, green: 0.42, blue: 0.62)
        case .nightlife: Color(red: 0.48, green: 0.40, blue: 0.92)
        case .hotel: Color(red: 0.28, green: 0.62, blue: 0.72)
        case .other: Color.secondary
        }
    }

    static func categoryPastelFill(_ category: LocationItem.Category) -> Color {
        categoryTint(category).opacity(0.18)
    }

    static func priorityTint(_ priority: LocationItem.VisitPriority) -> Color {
        switch priority {
        case .mustSee: Color(red: 0.95, green: 0.52, blue: 0.28)
        case .high: Color(red: 0.28, green: 0.58, blue: 0.88)
        case .normal: .secondary
        case .ifTime: Color(red: 0.35, green: 0.72, blue: 0.58)
        case .low: Color(uiColor: .tertiaryLabel)
        }
    }

    /// Stable gradient per trip for hero / listing thumbnails.
    static func tripGradient(seed: UUID) -> LinearGradient {
        let palettes: [(Color, Color)] = [
            (Color(red: 0.55, green: 0.78, blue: 0.95), Color(red: 0.72, green: 0.88, blue: 0.98)),
            (Color(red: 0.98, green: 0.72, blue: 0.62), Color(red: 1.0, green: 0.88, blue: 0.78)),
            (Color(red: 0.65, green: 0.88, blue: 0.78), Color(red: 0.82, green: 0.95, blue: 0.88)),
            (Color(red: 0.78, green: 0.70, blue: 0.95), Color(red: 0.90, green: 0.86, blue: 0.98)),
        ]
        let i = abs(seed.hashValue) % palettes.count
        let pair = palettes[i]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension LocationItem.Category {
    var symbolName: String {
        switch self {
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        case .museum: "building.columns.fill"
        case .landmark: "star.fill"
        case .park: "leaf.fill"
        case .neighborhood: "map.fill"
        case .city: "building.2.fill"
        case .shopping: "bag.fill"
        case .nightlife: "moon.stars.fill"
        case .hotel: "bed.double.fill"
        case .other: "mappin.circle.fill"
        }
    }

    var quickActionTitle: String {
        switch self {
        case .hotel: "Stay"
        case .restaurant: "Food"
        case .landmark: "Sights"
        case .museum: "Culture"
        case .park: "Nature"
        default: title
        }
    }
}

extension Trip {
    var inclusiveDayCount: Int? {
        guard let start = startDate, let end = endDate else { return nil }
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: end)
        guard e >= s else { return nil }
        return (cal.dateComponents([.day], from: s, to: e).day ?? 0) + 1
    }
}

extension View {
    func appScreenBackground() -> some View {
        background(AppTheme.screenBackground.ignoresSafeArea())
    }

    func softCard(cardPadding: CGFloat = AppTheme.cardPadding) -> some View {
        padding(cardPadding)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: AppTheme.cardShadowRadius, x: 0, y: AppTheme.cardShadowY)
    }

    func appPagePadding() -> some View {
        padding(.horizontal, AppTheme.pagePadding)
    }

    func appBottomTabPadding() -> some View {
        padding(.bottom, AppTheme.floatingTabClearance)
    }
}
