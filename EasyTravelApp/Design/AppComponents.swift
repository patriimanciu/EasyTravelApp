import SwiftUI

// MARK: - Home & layout

struct HomeHeaderView: View {
    var greeting: String = "Hello"
    var subtitle: String = "Where to next?"
    var onAddTrip: (() -> Void)?
    var addButtonAccessibilityLabel: String = "Add trip"

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
                .accessibilityLabel(addButtonAccessibilityLabel)
            }
        }
    }
}

struct PlanHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan smarter")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.charcoal)
                    Text("Import a video or build a trip, then let AI split stops across days.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.charcoal.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                heroIllustration
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                Text("Open a trip to start planning")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppTheme.charcoal.opacity(0.72))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: AppTheme.pillRadius, style: .continuous))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan smarter. Import a travel video or build a trip, then use Plan route inside a trip to split stops across days.")
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

struct CountryFilterScroll: View {
    let countries: [String]
    @Binding var selectedCountry: String?

    private var chipSize: CGFloat { AppTheme.categoryChipSize }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    countryChip(
                        title: "All",
                        symbolName: "square.grid.2x2",
                        tint: AppTheme.charcoal,
                        fill: AppTheme.elevatedFill,
                        isSelected: selectedCountry == nil
                    ) {
                        selectedCountry = nil
                    }
                    ForEach(countries, id: \.self) { country in
                        countryChip(
                            title: country,
                            symbolName: "globe.americas.fill",
                            tint: AppTheme.categoryTint(.city),
                            fill: AppTheme.categoryPastelFill(.city),
                            isSelected: selectedCountry == country
                        ) {
                            selectedCountry = country
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

    private func countryChip(
        title: String,
        symbolName: String,
        tint: Color,
        fill: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(fill)
                        .frame(width: chipSize, height: chipSize)
                    Image(systemName: symbolName)
                        .font(.system(size: chipSize * 0.34, weight: .semibold))
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
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: chipSize + 12)
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

// MARK: - Video import banner

struct VideoImportTopBanner: View {
    let phase: VideoImportPhase
    var onDismiss: (() -> Void)?
    var onOpenInbox: (() -> Void)?

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .running(let message, let progress):
            bannerShell(showProgress: true, progress: progress, tint: AppTheme.charcoal) {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        case .success(let count):
            bannerShell(showProgress: false, progress: 1, tint: Color(red: 0.28, green: 0.62, blue: 0.48)) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(red: 0.28, green: 0.62, blue: 0.48))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Added to Inbox")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.charcoal)
                        Text(
                            count == 1
                                ? "1 location is ready — assign it to a trip when you like."
                                : "\(count) locations are ready — assign them to a trip when you like."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    bannerDismissButton
                }
            }
            .onTapGesture {
                onOpenInbox?()
            }
        case .failure(let message):
            bannerShell(showProgress: false, progress: nil, tint: Color(red: 0.92, green: 0.35, blue: 0.32)) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.32))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.charcoal)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    bannerDismissButton
                }
            }
        }
    }

    @ViewBuilder
    private var bannerDismissButton: some View {
        if let onDismiss {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    @ViewBuilder
    private func bannerShell<Content: View>(
        showProgress: Bool,
        progress: Double?,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            if showProgress {
                Group {
                    if let progress {
                        ProgressView(value: min(1, max(0, progress)))
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
                .tint(tint)
                .frame(height: 4)
            }
            content()
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBackground)
        .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
    }
}

// MARK: - Route planning overlay

struct RoutePlanCenterOverlay: View {
    let phase: RoutePlanPhase
    var onDismiss: () -> Void

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .running(let message, let progress):
            overlayScrim {
                VStack(spacing: 18) {
                    Group {
                        if let progressValue = progressValue(progress) {
                            ProgressView(value: progressValue)
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                        }
                    }
                    .tint(AppTheme.charcoal)
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.charcoal)
                        .multilineTextAlignment(.center)
                }
            }
        case .success:
            overlayScrim {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(red: 0.28, green: 0.62, blue: 0.48))
                    Text("Route saved")
                        .font(.headline)
                        .foregroundStyle(AppTheme.charcoal)
                    Text("Your day split and map routes are ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        case .failure(let message):
            overlayScrim {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.32))
                    Text("Could not plan route")
                        .font(.headline)
                        .foregroundStyle(AppTheme.charcoal)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("OK", action: onDismiss)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.charcoal)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func progressValue(_ progress: Double?) -> Double? {
        guard let progress else { return nil }
        return min(1, max(0, progress))
    }

    @ViewBuilder
    private func overlayScrim<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
            content()
                .padding(28)
                .frame(maxWidth: 300)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                .shadow(color: AppTheme.cardShadow, radius: 20, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

// MARK: - Themed forms (sheets & edit screens)

struct AppFormSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard()
            if let footer {
                AppFormFooterText(footer)
            }
        }
    }
}

struct AppFormFooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppCharcoalButton: View {
    let title: String
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                disabled ? AppTheme.charcoal.opacity(0.35) : AppTheme.charcoal,
                in: RoundedRectangle(cornerRadius: AppTheme.pillRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
    }
}

struct AppFormBanner: View {
    enum Style {
        case error, success, info

        var tint: Color {
            switch self {
            case .error: Color(red: 0.92, green: 0.35, blue: 0.32)
            case .success: Color(red: 0.28, green: 0.62, blue: 0.48)
            case .info: AppTheme.charcoal
            }
        }

        var fill: Color { tint.opacity(0.12) }
    }

    let text: String
    var style: Style = .info

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(style.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(style.fill, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

/// Short hero for modal sheets (add trip, add location, etc.).
struct AppSheetIntro: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accent: Color = AppTheme.peachDeep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.charcoal)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.charcoal.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 56, height: 56)
        }
        .padding(AppTheme.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.42), accent.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
        )
    }
}

struct AppFormField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>? = nil
    var autocapitalizeWords: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Group {
                if let lineLimit {
                    TextField(placeholder, text: $text, axis: axis)
                        .lineLimit(lineLimit)
                } else {
                    TextField(placeholder, text: $text, axis: axis)
                }
            }
            .textInputAutocapitalization(autocapitalizeWords ? .words : .sentences)
            .padding(12)
            .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct AppFormToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.charcoal)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(AppTheme.charcoal)
        .padding(12)
        .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AppFormDateRow: View {
    let label: String
    @Binding var date: Date

    var body: some View {
        HStack {
            Text(label)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.charcoal)
            Spacer()
            DatePicker("", selection: $date, displayedComponents: [.date])
                .labelsHidden()
                .tint(AppTheme.charcoal)
        }
        .padding(12)
        .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Map search field — icon badge + text (matches stay search styling).
struct AppFormSearchBar: View {
    @Binding var text: String
    var category: LocationItem.Category
    var isSearching: Bool = false
    var placeholder: String = "Search place…"
    var onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconBadge(category: category, size: 44)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !text.isEmpty, let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: AppTheme.cardShadowRadius, x: 0, y: AppTheme.cardShadowY)
    }
}

struct AppSelectablePlaceRow: View {
    let title: String
    var subtitle: String?
    let category: LocationItem.Category
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.rowSpacing) {
            CategoryIconBadge(category: category, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.charcoal)
                    .multilineTextAlignment(.leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                .font(isSelected ? .title3 : .caption.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.categoryTint(category) : Color.secondary.opacity(0.55))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: AppTheme.cardShadowRadius, x: 0, y: AppTheme.cardShadowY)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.categoryTint(category).opacity(0.55), lineWidth: 2)
            }
        }
    }
}

struct CategoryPickerChips: View {
    @Binding var selection: LocationItem.Category

    private let featured: [LocationItem.Category] = [
        .landmark, .museum, .restaurant, .cafe, .park, .hotel, .shopping, .nightlife, .other,
    ]

    private var chipSize: CGFloat { 56 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(featured) { cat in
                    categoryChip(cat)
                }
            }
        }
    }

    private func categoryChip(_ cat: LocationItem.Category) -> some View {
        let isSelected = selection == cat
        return Button {
            selection = cat
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.categoryPastelFill(cat))
                        .frame(width: chipSize, height: chipSize)
                    Image(systemName: cat.symbolName)
                        .font(.system(size: chipSize * 0.36, weight: .semibold))
                        .foregroundStyle(AppTheme.categoryTint(cat))
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(AppTheme.charcoal, lineWidth: 2.5)
                            .frame(width: chipSize, height: chipSize)
                    }
                }
                Text(cat.title)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppTheme.charcoal : .secondary)
                    .lineLimit(1)
            }
            .frame(width: chipSize + 8)
        }
        .buttonStyle(.plain)
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

                if !trip.trimmedCountry.isEmpty {
                    Text(trip.placeFilterSummary ?? trip.trimmedCountry)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let start = trip.startDate, let end = trip.endDate {
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
                if let placeLine = location.inboxPlaceSubtitle {
                    Text(placeLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let notes = location.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
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
    PlanHeroCard()
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
