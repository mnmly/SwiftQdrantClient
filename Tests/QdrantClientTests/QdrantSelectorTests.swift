import XCTest
@testable import QdrantClient

/// Payload/vector selectors + enriched response fields — local backend, no server.
final class QdrantSelectorTests: XCTestCase {
    private func seed() async throws -> QdrantLocalClient {
        let c = QdrantLocalClient()
        try await c.createCollection(name: "c", size: 3, distance: .cosine)
        try await c.upsert(collection: "c", points: [
            .init(id: 1, vector: [1, 0, 0], payload: ["city": "Berlin", "country": "DE", "pop": 3_500_000]),
        ])
        return c
    }

    func testWithPayloadIncludeSubset() async throws {
        let c = try await seed()
        let hits = try await c.query(collection: "c", query: .nearest(.dense([1, 0, 0])),
                                     using: nil, prefetch: [], filter: nil, params: nil, scoreThreshold: nil,
                                     limit: 1, offset: 0, withPayload: ["city"], withVectors: false)
        XCTAssertEqual(hits.first?.payload.keys.sorted(), ["city"])
        XCTAssertEqual(hits.first?.payload["city"], "Berlin")
    }

    func testWithPayloadExclude() async throws {
        let c = try await seed()
        let got = try await c.retrieve(collection: "c", ids: [1],
                                       withPayload: .exclude(["pop"]), withVectors: false)
        XCTAssertEqual(got.first?.payload.keys.sorted(), ["city", "country"])
    }

    func testWithVectorsNamesSubset() async throws {
        let c = QdrantLocalClient()
        try await c.createCollection(name: "n", vectors: .named(["a": .init(size: 2), "b": .init(size: 2)]),
                                     sparseVectors: nil, quantizationConfig: nil, hnswConfig: nil,
                                     optimizersConfig: nil, walConfig: nil, onDiskPayload: nil,
                                     shardNumber: nil, shardingMethod: nil, replicationFactor: nil,
                                     writeConsistencyFactor: nil)
        try await c.upsert(collection: "n", points: [.init(id: 1, vectors: ["a": .dense([1, 0]), "b": .dense([0, 1])])])
        let got = try await c.retrieve(collection: "n", ids: [1], withPayload: false, withVectors: ["a"])
        XCTAssertEqual(got.first?.vectors.keys.sorted(), ["a"])
    }

    func testSelectorProtoAndRest() {
        // proto
        if case .include(let inc)? = WithPayload.include(["x", "y"]).proto.selectorOptions {
            XCTAssertEqual(inc.fields, ["x", "y"])
        } else { XCTFail("expected include") }
        if case .enable(let b)? = (true as WithPayload).proto.selectorOptions {
            XCTAssertTrue(b)
        } else { XCTFail("expected enable") }
        if case .include(let sel)? = WithVectors.names(["v"]).proto.selectorOptions {
            XCTAssertEqual(sel.names, ["v"])
        } else { XCTFail("expected vectors include") }
        // rest json
        XCTAssertEqual(WithPayload.include(["a"]).restJSON.arrayValue?.first?.stringValue, "a")
        XCTAssertEqual((false as WithVectors).restJSON.boolValue, false)
    }

    func testCollectionInfoPayloadSchemaLocalEmpty() async throws {
        // Local doesn't surface schema, but the field exists and is well-formed.
        let c = try await seed()
        let info = try await c.getCollection("c")
        XCTAssertEqual(info.pointsCount, 1)
        XCTAssertTrue(info.optimizerStatusOK)
        XCTAssertTrue(info.payloadSchema.isEmpty)
    }
}
