//
//  QuickRestStopView.swift
//  mchacks
//

import SwiftUI
import CoreLocation
import MapboxSearch
import Combine

// MARK: - Singleton Search Manager
class RestStopSearchManager {
    static let shared = RestStopSearchManager()

    let searchEngine: CategorySearchEngine

    private init() {
        searchEngine = CategorySearchEngine(accessToken: "sk.eyJ1Ijoib21hcmxhaG1pbWkiLCJhIjoiY21rY3V6ZGJrMDVsZDNmcTh1bmlmZHh4cSJ9.HDp0rzKa9umGwh7YuMYpQg")
        print("RestStopSearchManager: Initialized singleton")
    }
}

// MARK: - Model for a rest stop with category info
struct RestStopOption: Identifiable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let category: StopCategory

    enum StopCategory: String, CaseIterable {
        case food = "Food"
        case gas = "Gas"
        case rest = "Rest Area"

        var icon: String {
            switch self {
            case .food: return "fork.knife"
            case .gas: return "fuelpump.fill"
            case .rest: return "bed.double.fill"
            }
        }

        var color: Color {
            switch self {
            case .food: return .orange
            case .gas: return .blue
            case .rest: return .green
            }
        }

        // Canonical category names for Mapbox Category Search API
        var canonicalName: String {
            switch self {
            case .food: return "restaurant"
            case .gas: return "gas_station"
            case .rest: return "parking"
            }
        }
    }
}

// MARK: - View Model
class QuickRestStopViewModel: ObservableObject {
    @Published var stopOptions: [RestStopOption] = []
    @Published var isLoading = true

    private let searchManager = RestStopSearchManager.shared
    private let maxDistance: CLLocationDistance = 20000 // 20km

    func searchForNearbyStops(location: CLLocation) {
        print("QuickRestStopVM: Starting search near \(location.coordinate.latitude), \(location.coordinate.longitude)")

        isLoading = true
        stopOptions = []

        // Search sequentially to avoid cancellation
        searchSequentially(
            categories: [.food, .gas, .rest],
            location: location,
            results: []
        )
    }

    private func searchSequentially(
        categories: [RestStopOption.StopCategory],
        location: CLLocation,
        results: [RestStopOption]
    ) {
        // Base case: no more categories to search
        guard let currentCategory = categories.first else {
            DispatchQueue.main.async {
                self.stopOptions = results.sorted { $0.distance < $1.distance }
                self.isLoading = false
                print("QuickRestStopVM: Finished! Found \(self.stopOptions.count) options")
                for opt in self.stopOptions {
                    print("QuickRestStopVM: - \(opt.category.rawValue): \(opt.name) at \(Int(opt.distance))m")
                }
            }
            return
        }

        let remainingCategories = Array(categories.dropFirst())

        searchCategory(currentCategory, location: location) { [weak self] result in
            guard let self = self else { return }

            var newResults = results
            if let option = result {
                newResults.append(option)
            }

            // Small delay before next search to avoid rate limiting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.searchSequentially(
                    categories: remainingCategories,
                    location: location,
                    results: newResults
                )
            }
        }
    }

    private func searchCategory(
        _ category: RestStopOption.StopCategory,
        location: CLLocation,
        completion: @escaping (RestStopOption?) -> Void
    ) {
        let categoryName = category.canonicalName
        print("QuickRestStopVM: Searching '\(categoryName)'...")

        let options = SearchOptions(proximity: location.coordinate)

        searchManager.searchEngine.search(categoryName: categoryName, options: options) { [weak self] response in
            guard let self = self else {
                completion(nil)
                return
            }

            do {
                let results = try response.get()
                print("QuickRestStopVM: '\(categoryName)' returned \(results.count) results")

                // Log first few for debugging
                for (i, r) in results.prefix(3).enumerated() {
                    let dist = location.distance(from: CLLocation(latitude: r.coordinate.latitude, longitude: r.coordinate.longitude))
                    print("QuickRestStopVM: Result \(i): \(r.name) at \(Int(dist))m")
                }

                // Filter by distance and find closest
                let validResults = results.compactMap { searchResult -> RestStopOption? in
                    let stopLocation = CLLocation(
                        latitude: searchResult.coordinate.latitude,
                        longitude: searchResult.coordinate.longitude
                    )
                    let distance = location.distance(from: stopLocation)

                    guard distance <= self.maxDistance else {
                        return nil
                    }

                    return RestStopOption(
                        name: searchResult.name,
                        address: searchResult.address?.formattedAddress(style: .short),
                        coordinate: searchResult.coordinate,
                        distance: distance,
                        category: category
                    )
                }

                let closest = validResults.min { $0.distance < $1.distance }
                if let c = closest {
                    print("QuickRestStopVM: '\(categoryName)' BEST: \(c.name) at \(Int(c.distance))m")
                } else {
                    print("QuickRestStopVM: '\(categoryName)' no results within \(Int(self.maxDistance))m")
                }
                completion(closest)

            } catch {
                print("QuickRestStopVM: '\(categoryName)' error: \(error)")
                completion(nil)
            }
        }
    }
}

// MARK: - View
struct QuickRestStopView: View {
    @Binding var isPresented: Bool
    let userLocation: CLLocation?
    let reason: String
    let onSelectStop: (CLLocationCoordinate2D, String) -> Void

    @StateObject private var viewModel = QuickRestStopViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Handle indicator
            Capsule()
                .fill(AppColors.textMuted)
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            // Header
            Text("Take a break?")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
                .padding(.bottom, 12)

            // Content
            if viewModel.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    Text("Finding nearby stops...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else if viewModel.stopOptions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textSecondary)
                    Text("No stops nearby")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.vertical, 16)
            } else {
                // Show options
                VStack(spacing: 8) {
                    ForEach(viewModel.stopOptions) { stop in
                        QuickRestStopRow(stop: stop)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectStop(stop.coordinate, stop.name)
                                isPresented = false
                            }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Continue Driving button - full width
            Button(action: {
                isPresented = false
            }) {
                Text("Continue Driving")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.backgroundSecondary)
        .onAppear {
            if let location = userLocation {
                viewModel.searchForNearbyStops(location: location)
            } else {
                viewModel.isLoading = false
            }
        }
    }
}

// MARK: - Quick Rest Stop Row
struct QuickRestStopRow: View {
    let stop: RestStopOption

    private var iconName: String {
        switch stop.category {
        case .food: return "food"
        case .gas: return "gas"
        case .rest: return "rest"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Category icon from assets
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundColor(AppColors.textSecondary)

            // Info - Title + distance on top, address below
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(stop.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppColors.textMuted)

                    Text(formatDistance(stop.distance))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()
                }

                if let address = stop.address, !address.isEmpty {
                    Text(address)
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}
