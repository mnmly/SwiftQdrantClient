import XCTest
@testable import QdrantClient

/// REST backend — runs only when QDRANT_INTEGRATION=1 (Qdrant REST on :6333).
final class QdrantRESTTests: XCTestCase {
    func testRESTRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment["QDRANT_INTEGRATION"] == "1" else {
            throw XCTSkip("Set QDRANT_INTEGRATION=1 with a running Qdrant on :6333 to run.")
        }
        let client = QdrantRESTClient(host: "localhost", port: 6333)
        let name = "swift_qdrant_rest"
        _ = try? await client.deleteCollection(name)

        let created = try await client.createCollection(name: name, size: 4, distance: .cosine)
        XCTAssertTrue(created)
        let exists = try await client.collectionExists(name)
        XCTAssertTrue(exists)
        let names = try await client.listCollections()
        XCTAssertTrue(names.contains(name))

        try await client.upsert(collection: name, points: [
            .init(id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: ["city": "Berlin", "pop": 3_500_000]),
            .init(id: 2, vector: [0.9, 0.8, 0.7, 0.6], payload: ["city": "Tokyo", "pop": 14_000_000]),
        ])

        // Nearest + filtered query.
        let hits = try await client.query(collection: name, vector: [0.1, 0.2, 0.3, 0.4], limit: 1)
        XCTAssertEqual(hits.first?.id, .int(1))
        XCTAssertEqual(hits.first?.payload["city"], "Berlin")

        let filtered = try await client.query(
            collection: name, query: .nearest(.dense([0.1, 0.2, 0.3, 0.4])), using: nil, prefetch: [],
            filter: Filter(must: [.range("pop", gte: 10_000_000)]), params: nil, scoreThreshold: nil,
            limit: 5, offset: 0, withPayload: true, withVectors: false)
        XCTAssertEqual(filtered.map(\.id), [.int(2)])

        // Count, scroll, retrieve, payload.
        let count = try await client.count(collection: name, filter: nil, exact: true)
        XCTAssertEqual(count, 2)
        let page = try await client.scroll(
            collection: name, filter: nil, limit: 1, offset: nil,
            withPayload: true, withVectors: false, orderBy: nil)
        XCTAssertEqual(page.points.count, 1)
        XCTAssertNotNil(page.nextOffset)

        try await client.setPayload(collection: name, payload: ["country": "DE"], selector: .ids([1]), key: nil, wait: true)
        let fetched = try await client.retrieve(collection: name, ids: [1], withPayload: true, withVectors: true)
        XCTAssertEqual(fetched.first?.payload["country"], "DE")
        XCTAssertEqual(fetched.first?.vector?.count, 4)

        // recommend (via query)
        let rec = try await client.query(
            collection: name, query: .recommend(.init(positive: [.id(1)])), using: nil, prefetch: [],
            filter: nil, params: nil, scoreThreshold: nil, limit: 1, offset: 0,
            withPayload: true, withVectors: false)
        XCTAssertEqual(rec.first?.id, .int(2))

        try await client.deleteCollection(name)
        try await client.close()
    }

    /// The same workload runs identically through the protocol type, regardless
    /// of backend (REST here; could be gRPC or local).
    func testProtocolPolymorphism() async throws {
        guard ProcessInfo.processInfo.environment["QDRANT_INTEGRATION"] == "1" else {
            throw XCTSkip("integration only")
        }
        let backends: [any QdrantClientProtocol] = [
            QdrantRESTClient(host: "localhost", port: 6333),
            QdrantLocalClient(),
        ]
        for client in backends {
            let name = "swift_qdrant_poly"
            _ = try? await client.deleteCollection(name)
            _ = try await client.createCollection(name: name, size: 3, distance: .cosine)
            _ = try await client.upsert(collection: name, points: [
                .init(id: 1, vector: [1, 0, 0]), .init(id: 2, vector: [0, 1, 0]),
            ], wait: true)
            let hits = try await client.query(collection: name, vector: [1, 0, 0], limit: 1)
            XCTAssertEqual(hits.first?.id, .int(1))
            _ = try await client.deleteCollection(name)
            try await client.close()
        }
    }
}
