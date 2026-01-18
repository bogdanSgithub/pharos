//
//  RestStopSearchView.swift
//  mchacks
//

import SwiftUI
import CoreLocation
import MapboxSearch

struct RestStopSearchView: View {
    @Binding var isPresented: Bool
    let userLocation: CLLocation?
    let onSelectStop: (CLLocationCoordinate2D, String) -> Void

    @State private var suggestions: [PlaceAutocomplete.Suggestion] = []
    @State private var isSearching = false
    @State private var selectedCategory: RestStopCategory = .all

    private let placeAutocomplete = PlaceAutocomplete(accessToken: "sk.eyJ1Ijoib21hcmxhaG1pbWkiLCJhIjoiY21rY3V6ZGJrMDVsZDNmcTh1bmlmZHh4cSJ9.HDp0rzKa9umGwh7YuMYpQg")

    enum RestStopCategory: String, CaseIterable {
        case all = "All"
        case gasStation = "Gas Station"
        case coffee = "Coffee"
        case restaurant = "Restaurant"
        case restArea = "Rest Area"

        var searchQuery: String {
            switch self {
            case .all: return "rest stop"
            case .gasStation: return "gas station"
            case .coffee: return "coffee shop"
            case .restaurant: return "restaurant"
            case .restArea: return "rest area"
            }
        }

        var icon: String {
            switch self {
            case .all: return "bed.double"
            case .gasStation: return "fuelpump"
            case .coffee: return "cup.and.saucer"
            case .restaurant: return "fork.knife"
            case .restArea: return "parkingsign"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(RestStopCategory.allCases, id: \.self) { category in
                            CategoryButton(
                                category: category,
                                isSelected: selectedCategory == category,
                                onTap: {
                                    selectedCategory = category
                                    searchForStops()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(AppColors.backgroundSecondary)

                // Results
                if isSearching {
                    VStack(spacing: 16) {
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(AppColors.textMuted, lineWidth: 4)
                                .frame(width: 44, height: 44)

                            Circle()
                                .trim(from: 0, to: 0.3)
                                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 44, height: 44)
                                .rotationEffect(Angle(degrees: -90))
                        }
                        Text("Searching nearby...")
                            .font(.system(size: 15))
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                    }
                } else if suggestions.isEmpty {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(AppColors.backgroundCard)
                                .frame(width: 80, height: 80)

                            Image(systemName: "mappin.slash")
                                .font(.system(size: 32))
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Text("No rest stops found nearby")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                        Text("Try a different category")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(suggestions, id: \.mapboxId) { suggestion in
                                RestStopRow(suggestion: suggestion, userLocation: userLocation)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectStop(suggestion)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Find a Rest Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.backgroundSecondary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(AppColors.accent)
                }
            }
            .onAppear {
                searchForStops()
            }
        }
    }

    private func searchForStops() {
        guard let location = userLocation else {
            print("RestStopSearch: No user location available")
            return
        }

        isSearching = true
        suggestions = []

        // Include city/area hint for better local results
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let query = selectedCategory.searchQuery
        print("RestStopSearch: Searching for '\(query)' near (\(lat), \(lon))")

        placeAutocomplete.suggestions(for: query) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let results):
                    print("RestStopSearch: Got \(results.count) results")
                    for (index, r) in results.prefix(5).enumerated() {
                        print("RestStopSearch: Result \(index): \(r.name), hasCoord: \(r.coordinate != nil)")
                    }

                    // Filter results that have coordinates and are within reasonable distance (100km)
                    let nearbyResults = results.filter { suggestion in
                        guard let coord = suggestion.coordinate else { return false }
                        let suggestionLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let distance = location.distance(from: suggestionLocation)
                        let isNearby = distance < 100_000 // 100km max
                        if !isNearby {
                            print("RestStopSearch: Filtered out \(suggestion.name) - too far (\(Int(distance/1000))km)")
                        }
                        return isNearby
                    }

                    print("RestStopSearch: \(nearbyResults.count) results are nearby")

                    // Sort by distance
                    let sortedResults = nearbyResults.sorted { a, b in
                        guard let coordA = a.coordinate, let coordB = b.coordinate else { return false }
                        let distA = location.distance(from: CLLocation(latitude: coordA.latitude, longitude: coordA.longitude))
                        let distB = location.distance(from: CLLocation(latitude: coordB.latitude, longitude: coordB.longitude))
                        return distA < distB
                    }

                    self.suggestions = sortedResults
                case .failure(let error):
                    print("RestStopSearch: Search error: \(error)")
                    self.suggestions = []
                }
                self.isSearching = false
            }
        }
    }

    private func selectStop(_ suggestion: PlaceAutocomplete.Suggestion) {
        placeAutocomplete.select(suggestion: suggestion) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let selectedResult):
                    if let coordinate = selectedResult.coordinate {
                        onSelectStop(coordinate, selectedResult.name)
                        isPresented = false
                    }
                case .failure(let error):
                    print("Selection error: \(error)")
                    // Fallback to suggestion coordinate if available
                    if let coordinate = suggestion.coordinate {
                        onSelectStop(coordinate, suggestion.name)
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Category Button
struct CategoryButton: View {
    let category: RestStopSearchView.RestStopCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .medium))
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? AppColors.accent : AppColors.backgroundCard)
            .foregroundColor(isSelected ? .black : AppColors.textSecondary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Rest Stop Row
struct RestStopRow: View {
    let suggestion: PlaceAutocomplete.Suggestion
    let userLocation: CLLocation?

    private var iconColor: Color {
        let name = suggestion.name.lowercased()
        if name.contains("gas") || name.contains("shell") || name.contains("esso") || name.contains("petro") {
            return AppColors.accent
        } else if name.contains("coffee") || name.contains("starbucks") || name.contains("tim hortons") || name.contains("café") {
            return AppColors.warning
        } else if name.contains("mcdonald") || name.contains("restaurant") || name.contains("wendy") || name.contains("burger") {
            return AppColors.warning
        } else {
            return AppColors.success
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: iconForSuggestion)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let description = suggestion.description {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }

                    if let distance = distanceText {
                        if suggestion.description != nil {
                            Text("•")
                                .foregroundColor(AppColors.textMuted)
                        }
                        Text(distance)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 36, height: 36)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .padding(16)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconForSuggestion: String {
        let name = suggestion.name.lowercased()

        if name.contains("gas") || name.contains("shell") || name.contains("esso") || name.contains("petro") {
            return "fuelpump.fill"
        } else if name.contains("coffee") || name.contains("starbucks") || name.contains("tim hortons") || name.contains("café") {
            return "cup.and.saucer.fill"
        } else if name.contains("mcdonald") || name.contains("restaurant") || name.contains("wendy") || name.contains("burger") {
            return "fork.knife"
        } else if name.contains("rest") || name.contains("service") {
            return "bed.double.fill"
        } else {
            return "mappin.circle.fill"
        }
    }

    private var distanceText: String? {
        guard let userLoc = userLocation,
              let stopCoord = suggestion.coordinate else {
            return nil
        }

        let stopLocation = CLLocation(latitude: stopCoord.latitude, longitude: stopCoord.longitude)
        let distanceMeters = userLoc.distance(from: stopLocation)

        if distanceMeters < 1000 {
            return String(format: "%.0f m", distanceMeters)
        } else {
            let distanceKm = distanceMeters / 1000
            return String(format: "%.1f km", distanceKm)
        }
    }
}
