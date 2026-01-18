//
//  SearchView.swift
//  mchacks
//
//  Waze-style search panel
//

import SwiftUI
import CoreLocation
import MapboxSearch

struct SearchView: View {
    @Binding var isPresented: Bool
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @Binding var selectedPlaceName: String

    @State private var searchText = ""
    @State private var suggestions: [PlaceAutocomplete.Suggestion] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @FocusState private var isSearchFocused: Bool

    private let placeAutocomplete = PlaceAutocomplete(accessToken: "sk.eyJ1Ijoib21hcmxhaG1pbWkiLCJhIjoiY21rY3V6ZGJrMDVsZDNmcTh1bmlmZHh4cSJ9.HDp0rzKa9umGwh7YuMYpQg")

    private let recentLocations: [PresetLocation] = [
        PresetLocation(name: "Montreal Downtown", address: "Montreal, QC", coordinate: CLLocationCoordinate2D(latitude: 45.5017, longitude: -73.5673), icon: "arrow.counterclockwise"),
        PresetLocation(name: "McGill University", address: "845 Sherbrooke St W", coordinate: CLLocationCoordinate2D(latitude: 45.5048, longitude: -73.5772), icon: "arrow.counterclockwise"),
        PresetLocation(name: "Old Port of Montreal", address: "Montreal, QC", coordinate: CLLocationCoordinate2D(latitude: 45.5075, longitude: -73.5540), icon: "arrow.counterclockwise"),
        PresetLocation(name: "Mount Royal Park", address: "Montreal, QC", coordinate: CLLocationCoordinate2D(latitude: 45.5048, longitude: -73.5877), icon: "arrow.counterclockwise"),
        PresetLocation(name: "Olympic Stadium", address: "4545 Pierre De Coubertin Ave", coordinate: CLLocationCoordinate2D(latitude: 45.5579, longitude: -73.5515), icon: "arrow.counterclockwise"),
        PresetLocation(name: "Montreal Airport (YUL)", address: "975 Romeo-Vachon Blvd N", coordinate: CLLocationCoordinate2D(latitude: 45.4657, longitude: -73.7455), icon: "arrow.counterclockwise"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top search bar with back button (Waze style)
            HStack(spacing: 14) {
                Button(action: { isPresented = false }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }

                TextField("Where to?", text: $searchText)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(AppColors.textPrimary)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        suggestions = []
                        errorMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(AppColors.textTertiary)
                    }
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(AppColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.error)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Results
            ScrollView {
                LazyVStack(spacing: 0) {
                    if searchText.isEmpty {
                        // Recent section
                        SectionHeader(title: "Recent")

                        ForEach(Array(recentLocations.enumerated()), id: \.element.id) { index, location in
                            VStack(spacing: 0) {
                                RecentLocationRow(
                                    name: location.name,
                                    address: location.address
                                )
                                .onTapGesture {
                                    selectPresetLocation(location)
                                }

                                        // Divider (not on last item)
                                if index < recentLocations.count - 1 {
                                    Divider()
                                        .background(AppColors.border)
                                        .padding(.leading, 62)
                                }
                            }
                        }
                    } else if suggestions.isEmpty && !isSearching {
                        // No results
                        EmptySearchState()
                    } else {
                        // Search results
                        ForEach(Array(suggestions.enumerated()), id: \.element.mapboxId) { index, suggestion in
                            VStack(spacing: 0) {
                                RecentLocationRow(
                                    name: suggestion.name,
                                    address: suggestion.description
                                )
                                .onTapGesture {
                                    selectSuggestion(suggestion)
                                }

                                if index < suggestions.count - 1 {
                                    Divider()
                                        .background(AppColors.border)
                                        .padding(.leading, 62)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .background(AppColors.backgroundPrimary)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isSearchFocused = true
            }
        }
    }

    // MARK: - Search Functions

    private func performSearch(query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            suggestions = []
            isSearching = false
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }
            guard searchText == query else { return }

            placeAutocomplete.suggestions(for: query) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let results):
                        self.suggestions = results
                    case .failure(let error):
                        print("Search error: \(error)")
                        self.suggestions = []
                        self.errorMessage = "Search failed. Please try again."
                    }
                    self.isSearching = false
                }
            }
        }
    }

    private func selectSuggestion(_ suggestion: PlaceAutocomplete.Suggestion) {
        placeAutocomplete.select(suggestion: suggestion) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let selectedResult):
                    self.selectedCoordinate = selectedResult.coordinate
                    self.selectedPlaceName = selectedResult.name
                    self.isPresented = false
                case .failure(let error):
                    print("Selection error: \(error)")
                    if let coordinate = suggestion.coordinate {
                        self.selectedCoordinate = coordinate
                        self.selectedPlaceName = suggestion.name
                        self.isPresented = false
                    } else {
                        self.errorMessage = "Could not get location details"
                    }
                }
            }
        }
    }

    private func selectPresetLocation(_ location: PresetLocation) {
        selectedCoordinate = location.coordinate
        selectedPlaceName = location.name
        isPresented = false
    }

    private func iconForSuggestion(_ suggestion: PlaceAutocomplete.Suggestion) -> String {
        let name = suggestion.name.lowercased()

        if name.contains("airport") || name.contains("aeroport") {
            return "airplane"
        } else if name.contains("hospital") || name.contains("hopital") {
            return "cross.case"
        } else if name.contains("university") || name.contains("universite") || name.contains("college") {
            return "graduationcap"
        } else if name.contains("park") || name.contains("parc") {
            return "leaf"
        } else if name.contains("restaurant") || name.contains("cafe") {
            return "fork.knife"
        } else if name.contains("hotel") {
            return "bed.double"
        } else if name.contains("station") || name.contains("gare") {
            return "tram"
        } else if name.contains("mall") || name.contains("shop") {
            return "bag"
        } else {
            return "mappin"
        }
    }
}

// MARK: - Section Header (Waze Style)
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 10)
    }
}

// MARK: - Recent Location Row (Waze Style with history icon)
struct RecentLocationRow: View {
    let name: String
    let address: String?

    var body: some View {
        HStack(spacing: 18) {
            // History icon from assets
            Image("history")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundColor(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                if let address = address, !address.isEmpty {
                    Text(address)
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Location Row (Legacy)
struct LocationRow: View {
    let name: String
    let address: String?
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                if let address = address, !address.isEmpty {
                    Text(address)
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Empty Search State
struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(AppColors.textMuted)

            Text("No results found")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Models
struct PresetLocation: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let icon: String
}

// Keep old struct names for compatibility
typealias SuggestionRow = LocationRow
typealias PresetLocationRow = LocationRow
