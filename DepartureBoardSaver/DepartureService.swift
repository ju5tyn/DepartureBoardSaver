//
//  DepartureService.swift
//  DepartureBoardSaver
//
//  Swift port of trains.py — talks to the OpenLDBWS SOAP endpoint and
//  parses out the fields we need for the dot-matrix board.
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
    private let endpoint = URL(string: "https://lite.realtime.nationalrail.co.uk/OpenLDBWS/ldb11.asmx")!
    private let session: URLSession

    init(apiKey: String, crs: String) {
        self.apiKey = apiKey
        self.crs = crs.uppercased()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func fetch() async throws -> DepartureResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = soapEnvelope().data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw DepartureServiceError.badStatus(http.statusCode)
        }

        let doc = try XMLDocument(data: data)
        return try Self.parse(doc)
    }

    private func soapEnvelope() -> String {
        let escapedKey = Self.escapeXML(apiKey)
        let escapedCrs = Self.escapeXML(crs)
        return """
        <x:Envelope xmlns:x="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ldb="http://thalesgroup.com/RTTI/2017-10-01/ldb/" xmlns:typ4="http://thalesgroup.com/RTTI/2013-11-28/Token/types">
        <x:Header>
        <typ4:AccessToken><typ4:TokenValue>\(escapedKey)</typ4:TokenValue></typ4:AccessToken>
        </x:Header>
        <x:Body>
        <ldb:GetDepBoardWithDetailsRequest>
        <ldb:numRows>10</ldb:numRows>
        <ldb:crs>\(escapedCrs)</ldb:crs>
        <ldb:timeOffset>0</ldb:timeOffset>
        <ldb:filterType>to</ldb:filterType>
        <ldb:timeWindow>120</ldb:timeWindow>
        </ldb:GetDepBoardWithDetailsRequest>
        </x:Body>
        </x:Envelope>
        """
    }

    private static func escapeXML(_ value: String) -> String {
        var v = value
        v = v.replacingOccurrences(of: "&", with: "&amp;")
        v = v.replacingOccurrences(of: "<", with: "&lt;")
        v = v.replacingOccurrences(of: ">", with: "&gt;")
        v = v.replacingOccurrences(of: "\"", with: "&quot;")
        v = v.replacingOccurrences(of: "'", with: "&apos;")
        return v
    }

    // MARK: - XML parsing

    private static func parse(_ doc: XMLDocument) throws -> DepartureResult {
        // SOAP fault check
        if let fault = firstNode(doc.rootElement(), localName: "faultstring"),
           let msg = fault.stringValue, !msg.isEmpty {
            throw NSError(domain: "OpenLDBWS", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let result = firstNode(doc.rootElement(), localName: "GetStationBoardResult") else {
            throw DepartureServiceError.parseFailure
        }

        let stationName = firstNode(result, localName: "locationName")?.stringValue ?? ""

        let serviceNodes = allNodes(result, localName: "service")
        var departures: [Departure] = []

        for node in serviceNodes {
            let scheduled = firstNode(node, localName: "std")?.stringValue ?? ""
            let expected = firstNode(node, localName: "etd")?.stringValue ?? ""
            let platform = firstNode(node, localName: "platform")?.stringValue ?? ""

            let destinationName = destinationName(in: node)
            let callingAt = callingPoints(in: node)
            let status = mapStatus(expected: expected, scheduled: scheduled)

            departures.append(Departure(
                scheduled: scheduled,
                destination: stripParens(destinationName),
                platform: platform,
                status: status,
                callingAt: callingAt
            ))
        }

        return DepartureResult(stationName: stationName, departures: departures)
    }

    private static func destinationName(in service: XMLNode) -> String {
        let destination = firstNode(service, localName: "destination")
        let locations = childElements(destination, localName: "location")
        let names = locations.compactMap { firstNode($0, localName: "locationName")?.stringValue }
        if names.isEmpty { return "" }
        return names.map(stripParens).joined(separator: " & ")
    }

    private static func callingPoints(in service: XMLNode) -> [String] {
        guard let subsequent = firstNode(service, localName: "subsequentCallingPoints") else {
            return []
        }
        // There may be multiple callingPointList entries (when a service splits).
        let lists = childElements(subsequent, localName: "callingPointList")
        var collected: [String] = []
        for list in lists {
            let points = childElements(list, localName: "callingPoint")
            for p in points {
                if let n = firstNode(p, localName: "locationName")?.stringValue {
                    collected.append(stripParens(n))
                }
            }
        }
        return collected
    }

    private static func mapStatus(expected: String, scheduled: String) -> DepartureStatus {
        switch expected {
        case "On time": return .onTime
        case "Cancelled": return .cancelled
        case "Delayed": return .delayed
        case "": return .onTime
        default:
            // "13:42" style — show as Exp HH:MM unless it equals scheduled
            if expected == scheduled { return .onTime }
            return .expected(expected)
        }
    }

    private static func stripParens(_ s: String) -> String {
        // Mirrors removeBrackets() in trains.py — drops " (CIE)" style suffixes.
        if let r = s.range(of: " (") {
            return String(s[..<r.lowerBound])
        }
        return s
    }

    // MARK: - XMLNode helpers (local-name matching, namespace-agnostic)

    private static func firstNode(_ node: XMLNode?, localName: String) -> XMLNode? {
        guard let node else { return nil }
        if let element = node as? XMLElement, element.localName == localName {
            return element
        }
        guard let children = node.children else { return nil }
        for child in children {
            if let match = firstNode(child, localName: localName) {
                return match
            }
        }
        return nil
    }

    private static func allNodes(_ node: XMLNode, localName: String) -> [XMLElement] {
        var matches: [XMLElement] = []
        if let element = node as? XMLElement, element.localName == localName {
            matches.append(element)
        }
        for child in node.children ?? [] {
            matches.append(contentsOf: allNodes(child, localName: localName))
        }
        return matches
    }

    private static func childElements(_ node: XMLNode?, localName: String) -> [XMLElement] {
        guard let children = node?.children else { return [] }
        return children.compactMap { child in
            guard let element = child as? XMLElement, element.localName == localName else { return nil }
            return element
        }
    }
}
