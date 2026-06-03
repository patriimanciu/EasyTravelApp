import SwiftUI

// MARK: - Home & layout

struct HomeHeaderView: View {
    var greeting: String = "Hello"
    var subtitle: String = "Where to next?"
    var onAddTrip: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.peachDeep, AppTheme.peach],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.charcoal.opacity(0.7))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.title2.weight(.bold))
            }

            Spacer()

            if let onAddTrip {
                Button(action: onAddTrip) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.charcoal)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: Circle())
                        .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add trip")
            }
        }
    }
}

struct PlanHeroCard: View {
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan smarter")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.charcoal)
                    Text("Import a travel video or build a trip, then let AI split stops across days.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.charcoal.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                heroIllustration
            }

            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.body.weight(.semibold))
                    Text("Start plan with AI")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(AppTheme.charcoal)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.pillRadius, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.cardPadding + 4)
        .background(
            LinearGradient(
                colors: [AppTheme.peachDeep.opacity(0.95), AppTheme.peach],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous)
        )
        .shadow(color: AppTheme.peachDeep.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private var heroIllustration: some View {
        ZStack {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.charcoal.opacity(0.12))
            Image(systemName: "building.2.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.charcoal.opacity(0.25))
                .offset(x: -18, y: 12)
            Image(systemName: "airplane")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.charcoal.opacity(0.35))
                .offset(x: 20, y: -14)
        }
        .frame(width: 72, height: 72)
    }
}

struct ImportHeroCard: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.sky)
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(red: 0.28, green: 0.52, blue: 0.88))
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Import from video")
                        .font(.headline)
                        .foregroundStyle(AppTheme.charcoal)
                    Text("Extract places from TikTok or YouTube")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .softCard()
        }
        .buttonStyle(.plain)
    }
}

struct CategoryFilterScroll: View {
    @Binding var selectedCategory: LocationItem.Category?

    private let featured: [LocationItem.Category] = [
        .hotel, .landmark, .restaurant, .museum, .park, .cafe,
    ]

    private var chipSize: CGFloat { AppTheme.categoryChipSize }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    filterChip(
                        title: "All",
                        symbolName: "square.grid.2x2",
                        tint: AppTheme.charcoal,
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(featured) { category in
                        filterChip(
                            title: category.quickActionTitle,
                            symbolName: category.symbolName,
                            tint: AppTheme.categoryTint(category),
                            fill: AppTheme.categoryPastelFill(category),
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.leading, AppTheme.pagePadding)
                .padding(.trailing, AppTheme.pagePadding + chipSize * 0.35)
            }

            LinearGradient(
                colors: [AppTheme.screenBackground.opacity(0), AppTheme.screenBackground],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 36)
            .allowsHitTesting(false)
        }
    }

    private func filterChip(
        title: String,
        symbolName: String,
        tint: Color,
        fill: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(fill ?? AppTheme.elevatedFill)
                        .frame(width: chipSize, height: chipSize)
                    Image(systemName: symbolName)
                        .font(.system(size: chipSize * 0.38, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(AppTheme.charcoal, lineWidth: 2.5)
                            .frame(width: chipSize, height: chipSize)
                    }
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppTheme.charcoal : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.charcoal)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Trip cards & detail

struct MetaPill: View {
    let icon: String
    let text: String
    var tint: Color = AppTheme.charcoal

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct TripListingCard: View {
    let trip: Trip

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            tripThumbnail

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    MetaPill(
                        icon: "mappin.and.ellipse",
                        text: "\(trip.locations.count) place\(trip.locations.count == 1 ? "" : "s")",
                        tint: AppTheme.categoryTint(.landmark)
                    )
                    if let days = trip.inclusiveDayCount {
                        MetaPill(icon: "calendar", text: "\(days) day\(days == 1 ? "" : "s")", tint: AppTheme.categoryTint(.city))
                    }
                }

                Text(trip.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.charcoal)
                    .lineLimit(2)

                if let start = trip.startDate, let end = trip.endDate {
                    Text("\(Self.dateFormatter.string(from: start)) – \(Self.dateFormatter.string(from: end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if trip.accommodation != nil {
                    Text("Hub: \(trip.accommodation!.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .softCard()
    }

    private var tripThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.tripGradient(seed: trip.id))
            Image(systemName: "airplane.departure")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: 76, height: 76)
    }
}

struct TripHeroBanner: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss

    private var bannerHeight: CGFloat { AppTheme.tripHeroHeight }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.charcoal)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.92), in: Circle())
                            .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    heroMetaPill(icon: "mappin.and.ellipse", text: "\(trip.locations.count) stops")
                    if let days = trip.inclusiveDayCount {
                        heroMetaPill(icon: "calendar", text: "\(days) days")
                    }
                }

                Text(trip.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .padding(.top, 10)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, AppTheme.tripHeroOverlap + 16)
            .safeAreaPadding(.top, 10)
        }
        .frame(height: bannerHeight)
        .frame(maxWidth: .infinity)
        .background {
            AppTheme.tripGradient(seed: trip.id)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .topTrailing) {
            heroDecor
        }
    }

    private func heroMetaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(AppTheme.charcoal.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.92), in: Capsule())
    }

    private var heroDecor: some View {
        ZStack {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 72))
                .foregroundStyle(.white.opacity(0.18))
                .offset(x: 24, y: 28)
            Image(systemName: "cloud.fill")
                .font(.title)
                .foregroundStyle(.white.opacity(0.22))
                .offset(x: -20, y: 36)
        }
        .padding(.trailing, AppTheme.pagePadding)
        .padding(.top, 52)
    }
}

struct PrimaryCharcoalButton: View {
    let title: String
    var icon: String = "sparkles"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.charcoal, in: RoundedRectangle(cornerRadius: AppTheme.pillRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - List rows

struct CategoryIconBadge: View {
    let category: LocationItem.Category
    var size: CGFloat = 40

    var body: some View {
        let tint = AppTheme.categoryTint(category)
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(AppTheme.categoryPastelFill(category), in: Circle())
    }
}

struct InboxLocationCard: View {
    let location: LocationItem
    var showCheckmark: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: AppTheme.rowSpacing) {
            if showCheckmark {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.charcoal : .secondary)
            }

            CategoryIconBadge(category: location.category, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.charcoal)
                if let notes = location.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if !showCheckmark {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .softCard(cardPadding: 14)
    }
}

struct DayChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : AppTheme.charcoal)
                .background(
                    isSelected ? AnyShapeStyle(AppTheme.charcoal) : AnyShapeStyle(Color.white),
                    in: Capsule()
                )
                .shadow(color: isSelected ? .clear : AppTheme.cardShadow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct RouteStopIndexBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.charcoal)
            .frame(minWidth: 28, minHeight: 28)
            .background(AppTheme.mint, in: Circle())
    }
}

struct PriorityPill: View {
    let priority: LocationItem.VisitPriority

    var body: some View {
        let tint = AppTheme.priorityTint(priority)
        Text(priority.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct AppTipBanner: View {
    let text: String
    var systemImage: String = "sparkles"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.peachDeep)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.peach.opacity(0.5), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

struct AppEmptyState: View {
    let title: String
    let systemImage: String
    var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.peachDeep)
            Text(title)
                .font(.title3.weight(.semibold))
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Previews

#Preview("Trip card") {
    TripListingCard(trip: PreviewData.parisTrip)
        .padding()
        .appScreenBackground()
}

#Preview("Plan hero") {
    PlanHeroCard(action: {})
        .padding()
        .appScreenBackground()
}

#Preview("Category badges") {
    HStack(spacing: 12) {
        CategoryIconBadge(category: .museum, size: 44)
        CategoryIconBadge(category: .restaurant, size: 44)
        CategoryIconBadge(category: .landmark, size: 44)
    }
    .padding()
    .appScreenBackground()
}

#Preview("Day chips") {
    HStack {
        DayChip(title: "Day 1", isSelected: true, action: {})
        DayChip(title: "Day 2", isSelected: false, action: {})
    }
    .padding()
    .appScreenBackground()
}

#Preview("Category filter") {
    @Previewable @State var filter: LocationItem.Category? = .landmark
    CategoryFilterScroll(selectedCategory: $filter)
        .padding(.horizontal, -AppTheme.pagePadding)
        .appPagePadding()
        .padding(.vertical)
        .appScreenBackground()
}

#Preview("Floating tab bar") {
    @Previewable @State var tab: AppTab = .trips
    FloatingTabBar(selection: $tab, inboxBadge: 3)
        .padding()
        .appScreenBackground()
}
