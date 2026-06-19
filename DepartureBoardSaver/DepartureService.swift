//
//  DepartureService.swift
//  DepartureBoardSaver
//
//  Talks to the raildata.org.uk departure board REST API and maps the JSON
//  response into the fields needed by the dot-matrix board.
//
//  If no personal API key is configured, requests are routed through a shared
//  Cloudflare Worker that injects the key server-side — so users get live data
//  out of the box without needing to register.
//

import Foundation

struct DepartureResult: Sendable {
    let stationName: String
    let departures: [Departure]
}

enum DepartureServiceError: Error {
    case badStatus(Int)
    case parseFailure
}

actor DepartureService {

    private let apiKey: String
    private let crs: String
    private let session: URLSession

    // URL of the shared Cloudflare Worker proxy.
    // Update this after deploying the worker from the cloudflare-worker/ directory.
    static let workerBaseURL = "https://departure-board-api.justynhenman.com"

    init(apiKey: String, crs: String) {
        self.apiKey = apiKey
        self.crs = crs.uppercased()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func fetch() async throws -> DepartureResult {
        var request = URLRequest(url: makeURL())
        request.httpMethod = "GET"
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw DepartureServiceError.badStatus(http.statusCode)
        }

        return try Self.parse(data)
    }

    private func makeURL() -> URL {
        let encoded = crs.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? crs
        if apiKey.isEmpty {
            return URL(string: "\(Self.workerBaseURL)/GetDepBoardWithDetails/\(encoded)?numRows=10")!
        } else {
            return URL(string: "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120/GetDepBoardWithDetails/\(encoded)?numRows=10")!
        }
    }

    // MARK: - JSON parsing

    private static func parse(_ data: Data) throws -> DepartureResult {
        let response: APIResponse
        do {
            response = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw DepartureServiceError.parseFailure
        }

        var departures: [Departure] = []

        for service in response.trainServices ?? [] {
            let scheduled = service.std ?? ""
            let expected  = service.etd ?? ""
            let platform  = service.platform ?? ""

            let destination = service.destination
                .map { stripParens($0.locationName) }
                .joined(separator: " & ")

            let callingAt = service.subsequentCallingPoints?
                .flatMap { $0.callingPoint }
                .map { stripParens($0.locationName) } ?? []

            let status = mapStatus(
                expected: expected,
                scheduled: scheduled,
                isCancelled: service.isCancelled
            )

            departures.append(Departure(
                scheduled: scheduled,
                destination: destination,
                platform: platform,
                status: status,
                callingAt: callingAt
            ))
        }

        return DepartureResult(stationName: response.locationName, departures: departures)
    }

    private static func mapStatus(expected: String, scheduled: String, isCancelled: Bool) -> DepartureStatus {
        if isCancelled { return .cancelled }
        switch expected {
        case "On time", "": return .onTime
        case "Cancelled":   return .cancelled
        case "Delayed":     return .delayed
        default:
            if expected == scheduled { return .onTime }
            return .expected(expected)
        }
    }

    private static func stripParens(_ s: String) -> String {
        if let r = s.range(of: " (") { return String(s[..<r.lowerBound]) }
        return s
    }

    // MARK: - Codable models

    private struct APIResponse: Decodable {
        let locationName: String
        let trainServices: [ServiceItem]?
    }

    private struct ServiceItem: Decodable {
        let std: String?
        let etd: String?
        let platform: String?
        let destination: [LocationItem]
        let isCancelled: Bool
        let subsequentCallingPoints: [CallingPointList]?
    }

    private struct LocationItem: Decodable {
        let locationName: String
    }

    private struct CallingPointList: Decodable {
        let callingPoint: [CallingPoint]
    }

    private struct CallingPoint: Decodable {
        let locationName: String
    }
}
