import XCTest
@testable import QdrantClient

/// Local in-memory backend — no server required.
final class QdrantLocalTests: XCTestCase {
    func makeClient() async throws -> QdrantLocalClient {
        let client = QdrantLocalClient()
        try await client.createCollection(name: "c", size: 4, distance: .cosine)
        try await client.upsert(collection: "c", points: [
            .init(id: 1, vector: [1, 0, 0, 0], payload: ["city": "Berlin", "pop": 3_500_000]),
            .init(id: 2, vector: [0, 1, 0, 0], payload: ["city": "Tokyo", "pop": 14_000_000]),
            .init(id: 3, vector: [0.9, 0.1, 0, 0], payload: ["city": "Munich", "pop": 1_500_000]),
        ])
        return client
    }

    func testNearestQuery() async throws {
        let client = try await makeClient()
        let hits = try await client.query(collection: "c", vector: [1, 0, 0, 0], limit: 2)
        XCTAssertEqual(hits.map(\.id), [.int(1), .int(3)]) // Berlin then Munich
        XCTAssertEqual(hits.first?.payload["city"], "Berlin")
        XCTAssertGreaterThan(hits[0].score, hits[1].score)
    }

    func testFilteredQuery() async throws {
        let client = try await makeClient()
        let hits = try await client.query(
            collection: "c", query: .nearest(.dense([1, 0, 0, 0])), using: nil, prefetch: [],
            filter: Filter(must: [.range("pop", gte: 2_000_000)]),
            params: nil, scoreThreshold: nil, limit: 5, offset: 0,
            withPayload: true, withVectors: false)
        XCTAssertEqual(Set(hits.map(\.id)), [.int(1), .int(2)]) // pop >= 2M excludes Munich
    }

    func testCountAndScroll() async throws {
        let client = try await makeClient()
        let count = try await client.count(collection: "c", filter: nil, exact: true)
        XCTAssertEqual(count, 3)
        let page = try await client.scroll(
            collection: "c", filter: nil, limit: 2, offset: nil,
            withPayload: true, withVectors: false, orderBy: nil)
        XCTAssertEqual(page.points.map(\.id), [.int(1), .int(2)])
        XCTAssertEqual(page.nextOffset, .int(3))
    }

    func testPayloadUpdateAndDelete() async throws {
        let client = try await makeClient()
        try await client.setPayload(collection: "c", payload: ["country": "DE"], selector: .ids([1]), key: nil, wait: true)
        let fetched = try await client.retrieve(collection: "c", ids: [1], withPayload: true, withVectors: false)
        XCTAssertEqual(fetched.first?.payload["country"], "DE")

        try await client.delete(collection: "c", selector: .ids([2]), wait: true)
        let count = try await client.count(collection: "c", filter: nil, exact: true)
        XCTAssertEqual(count, 2)
    }

    func testRecommend() async throws {
        let client = try await makeClient()
        // Positive example = point 1; it is excluded, nearest remaining is Munich (3).
        let hits = try await client.query(
            collection: "c", query: .recommend(.init(positive: [.id(1)])),
            using: nil, prefetch: [], filter: nil, params: nil, scoreThreshold: nil,
            limit: 1, offset: 0, withPayload: true, withVectors: false)
        XCTAssertEqual(hits.first?.id, .int(3))
    }

    func testWithVectors() async throws {
        let client = try await makeClient()
        let hits = try await client.query(
            collection: "c", query: .nearest(.dense([1, 0, 0, 0])), using: nil, prefetch: [],
            filter: nil, params: nil, scoreThreshold: nil, limit: 1, offset: 0,
            withPayload: false, withVectors: true)
        XCTAssertEqual(hits.first?.vector, [1, 0, 0, 0])
    }

    func testNamedAndSparseLocal() async throws {
        let client = QdrantLocalClient()
        try await client.createCollection(
            name: "n",
            vectors: .named(["dense": .init(size: 2, distance: .dot)]),
            sparseVectors: ["sparse": .init()],
            hnswConfig: nil, optimizersConfig: nil, onDiskPayload: nil,
            shardNumber: nil, replicationFactor: nil)
        try await client.upsert(collection: "n", points: [
            .init(id: 1, vectors: ["dense": .dense([1, 0]), "sparse": .sparse(indices: [0, 2], values: [1, 1])]),
            .init(id: 2, vectors: ["dense": .dense([0, 1]), "sparse": .sparse(indices: [1, 3], values: [1, 1])]),
        ])
        let dense = try await client.query(
            collection: "n", query: .nearest(.dense([1, 0])), using: "dense", prefetch: [],
            filter: nil, params: nil, scoreThreshold: nil, limit: 1, offset: 0,
            withPayload: false, withVectors: false)
        XCTAssertEqual(dense.first?.id, .int(1))

        let sparse = try await client.query(
            collection: "n", query: .nearest(.sparse(indices: [0, 2], values: [1, 1])), using: "sparse",
            prefetch: [], filter: nil, params: nil, scoreThreshold: nil, limit: 1, offset: 0,
            withPayload: false, withVectors: false)
        XCTAssertEqual(sparse.first?.id, .int(1))
    }
}
