import XCTest
@testable import QdrantClient

final class QdrantModelTests: XCTestCase {
    // Pure model/proto-conversion tests — no server required.

    func testPointIDRoundTrip() {
        XCTAssertEqual(PointID(PointID.int(42).proto), .int(42))
        XCTAssertEqual(PointID(PointID.uuid("abc").proto), .uuid("abc"))
    }

    func testValueRoundTrip() {
        let value: QdrantValue = ["city": "Berlin", "pop": 3_500_000, "tags": ["a", "b"], "ok": true]
        let restored = QdrantValue(value.proto)
        XCTAssertEqual(restored, value)
    }

    func testPointStructProto() {
        let p = PointStruct(id: 1, vector: [0.1, 0.2], payload: ["k": "v"])
        let proto = p.proto
        XCTAssertEqual(proto.id.num, 1)
        if case .vector(let v) = proto.vectors.vectorsOptions, case .dense(let dense)? = v.vector {
            XCTAssertEqual(dense.data, [0.1, 0.2])
        } else {
            XCTFail("expected single dense vector")
        }
        XCTAssertEqual(proto.payload["k"]?.stringValue, "v")
    }

    func testSparseAndNamedVectorProto() {
        let sparse = PointStruct(id: 2, vector: .sparse(indices: [0, 5], values: [1.0, 2.0]))
        if case .vector(let v) = sparse.proto.vectors.vectorsOptions, case .sparse(let s)? = v.vector {
            XCTAssertEqual(s.indices, [0, 5])
            XCTAssertEqual(s.values, [1.0, 2.0])
        } else { XCTFail("expected sparse vector") }

        let named = PointStruct(id: 3, vectors: ["text": .dense([1, 2]), "img": .multiDense([[1, 2], [3, 4]])])
        guard case .vectors(let nv)? = named.proto.vectors.vectorsOptions else {
            return XCTFail("expected named vectors")
        }
        XCTAssertEqual(nv.vectors.count, 2)
        if case .multiDense(let m)? = nv.vectors["img"]?.vector {
            XCTAssertEqual(m.vectors.map(\.data), [[1, 2], [3, 4]])
        } else { XCTFail("expected multi-dense") }
    }

    func testFilterProto() {
        let f = Filter(
            must: [.match("city", "Berlin"), .range("pop", gte: 1000)],
            should: [.match("country", "DE")],
            mustNot: [.isEmpty(key: "name")]
        )
        let proto = f.proto
        XCTAssertEqual(proto.must.count, 2)
        XCTAssertEqual(proto.should.count, 1)
        XCTAssertEqual(proto.mustNot.count, 1)
        XCTAssertEqual(proto.must.first?.field.match.keyword, "Berlin")
        XCTAssertEqual(proto.must.last?.field.range.gte, 1000)
    }

    func testQueryProto() {
        if case .recommend(let r) = Query.recommend(.init(positive: [.id(1)], negative: [.dense([0.1])])).proto.variant {
            XCTAssertEqual(r.positive.first?.id.num, 1)
            XCTAssertEqual(r.negative.first?.dense.data, [0.1])
        } else { XCTFail("expected recommend") }

        if case .fusion(let fus) = Query.fusion(.rrf).proto.variant {
            XCTAssertEqual(fus, .rrf)
        } else { XCTFail("expected fusion") }
    }
}

/// Integration test — runs only when QDRANT_INTEGRATION=1 and a server is reachable.
final class QdrantIntegrationTests: XCTestCase {
    func testCreateUpsertQuery() async throws {
        guard ProcessInfo.processInfo.environment["QDRANT_INTEGRATION"] == "1" else {
            throw XCTSkip("Set QDRANT_INTEGRATION=1 with a running Qdrant on :6334 to run.")
        }
        let client = try QdrantClient(host: "localhost")
        let name = "swift_qdrant_smoke"
        _ = try? await client.deleteCollection(name)
        let created = try await client.createCollection(name: name, size: 4, distance: .cosine)
        XCTAssertTrue(created)
        let exists = try await client.collectionExists(name)
        XCTAssertTrue(exists)

        try await client.upsert(collection: name, points: [
            .init(id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: ["city": "Berlin"]),
            .init(id: 2, vector: [0.9, 0.8, 0.7, 0.6], payload: ["city": "Tokyo"]),
        ])

        let hits = try await client.query(collection: name, vector: [0.1, 0.2, 0.3, 0.4], limit: 1)
        XCTAssertEqual(hits.first?.id, .int(1))
        XCTAssertEqual(hits.first?.payload["city"], "Berlin")

        // Filtered query: only Tokyo should come back.
        let filtered = try await client.query(
            collection: name,
            vector: [0.1, 0.2, 0.3, 0.4],
            limit: 5,
            filter: Filter(must: [.match("city", "Tokyo")])
        )
        XCTAssertEqual(filtered.map(\.id), [.int(2)])

        // Count + scroll.
        let total = try await client.count(collection: name)
        XCTAssertEqual(total, 2)
        let page = try await client.scroll(collection: name, limit: 1)
        XCTAssertEqual(page.points.count, 1)
        XCTAssertNotNil(page.nextOffset)

        // Retrieve + payload ops.
        let fetched = try await client.retrieve(collection: name, ids: [1])
        XCTAssertEqual(fetched.first?.payload["city"], "Berlin")
        try await client.setPayload(collection: name, payload: ["country": "DE"], selector: .ids([1]))
        let updated = try await client.retrieve(collection: name, ids: [1])
        XCTAssertEqual(updated.first?.payload["country"], "DE")

        // Payload index + collection info.
        try await client.createPayloadIndex(collection: name, fieldName: "city", fieldType: .keyword)
        let info = try await client.getCollection(name)
        XCTAssertEqual(info.pointsCount, 2)

        // Recommend (positive example = point 1) should surface point 2.
        let recommended = try await client.recommend(collection: name, positive: [.id(1)], limit: 1)
        XCTAssertEqual(recommended.first?.id, .int(2))

        // Discover. Use raw vectors for context so no point ids are excluded
        // (recommend/discover exclude any point ids used as examples).
        let discovered = try await client.discover(
            collection: name,
            target: .dense([0.1, 0.2, 0.3, 0.4]),
            context: [.init(positive: .dense([0.1, 0.2, 0.3, 0.4]),
                            negative: .dense([0.9, 0.8, 0.7, 0.6]))],
            limit: 2)
        XCTAssertFalse(discovered.isEmpty)

        // Batch query.
        let batch = try await client.queryBatch(collection: name, queries: [
            .init(query: .nearest(.dense([0.1, 0.2, 0.3, 0.4])), limit: 1),
            .init(query: .nearest(.dense([0.9, 0.8, 0.7, 0.6])), limit: 1),
        ])
        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(batch[0].first?.id, .int(1))
        XCTAssertEqual(batch[1].first?.id, .int(2))

        // Facet on the indexed "city" field.
        let facets = try await client.facet(collection: name, key: "city", exact: true)
        XCTAssertEqual(Set(facets.map(\.value)), [.string("Berlin"), .string("Tokyo")])

        // Aliases.
        try await client.createAlias(collection: name, alias: "\(name)_alias")
        let aliases = try await client.listCollectionAliases(name)
        XCTAssertEqual(aliases.first?.aliasName, "\(name)_alias")
        try await client.deleteAlias("\(name)_alias")

        // Snapshots.
        let snap = try await client.createSnapshot(collection: name)
        XCTAssertNotNil(snap)
        let snaps = try await client.listSnapshots(collection: name)
        XCTAssertFalse(snaps.isEmpty)
        if let snapName = snap?.name {
            try await client.deleteSnapshot(collection: name, snapshotName: snapName)
        }

        try await client.deleteCollection(name)
        try await client.close()
    }

    // Named + sparse vectors end-to-end.
    func testNamedAndSparseVectors() async throws {
        guard ProcessInfo.processInfo.environment["QDRANT_INTEGRATION"] == "1" else {
            throw XCTSkip("Set QDRANT_INTEGRATION=1 with a running Qdrant on :6334 to run.")
        }
        let client = try QdrantClient(host: "localhost")
        let name = "swift_qdrant_named"
        _ = try? await client.deleteCollection(name)
        let created = try await client.createCollection(
            name: name,
            vectors: .named(["dense": .init(size: 3, distance: .cosine)]),
            sparseVectors: ["sparse": .init()])
        XCTAssertTrue(created)

        try await client.upsert(collection: name, points: [
            .init(id: 1, vectors: ["dense": .dense([0.1, 0.2, 0.3]),
                                   "sparse": .sparse(indices: [0, 2], values: [1.0, 0.5])]),
            .init(id: 2, vectors: ["dense": .dense([0.9, 0.8, 0.7]),
                                   "sparse": .sparse(indices: [1, 3], values: [0.4, 0.9])]),
        ])

        let denseHits = try await client.query(
            collection: name, query: .nearest(.dense([0.1, 0.2, 0.3])), using: "dense", limit: 1)
        XCTAssertEqual(denseHits.first?.id, .int(1))

        let sparseHits = try await client.query(
            collection: name,
            query: .nearest(.sparse(indices: [0, 2], values: [1.0, 0.5])),
            using: "sparse", limit: 1)
        XCTAssertEqual(sparseHits.first?.id, .int(1))

        try await client.deleteCollection(name)
        try await client.close()
    }
}
