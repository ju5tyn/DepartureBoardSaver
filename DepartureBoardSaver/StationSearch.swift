//
//  StationSearch.swift
//  DepartureBoardSaver
//

import Foundation

struct StationEntry {
    let name: String
    let crs: String
}

@MainActor
final class StationSearch {
    static let shared = StationSearch()

    private let stations: [StationEntry]

    private init() {
        guard
            let url = Bundle(for: ConfigureSheetController.self)
                .url(forResource: "Stations", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { stations = []; return }

        struct Raw: Decodable { let name: String; let crs: String }
        guard let raws = try? JSONDecoder().decode([Raw].self, from: data) else {
            stations = []
            return
        }
        stations = raws.map { StationEntry(name: $0.name, crs: $0.crs) }
    }

    func search(_ query: String) -> [StationEntry] {
        guard query.count >= 2 else { return [] }
        let q = query.lowercased()
        let results = stations.filter {
            $0.name.lowercased().contains(q) || $0.crs.lowercased() == q
        }
        return Array(results.prefix(50))
    }

    func exactMatch(byName name: String) -> StationEntry? {
        let n = name.lowercased()
        return stations.first { $0.name.lowercased() == n }
    }

    func entry(forCRS crs: String) -> StationEntry? {
        let c = crs.uppercased()
        return stations.first { $0.crs == c }
    }
}
