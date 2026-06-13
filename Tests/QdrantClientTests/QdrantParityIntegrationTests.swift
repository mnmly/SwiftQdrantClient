import XCTest
@testable import QdrantClient

/// Live parity checks for the new methods on the remote backends.
final class QdrantParityIntegrationTests: XCTestCase {
    private func skipUnlessIntegration() throws {
        guard ProcessInfo.processInfo.environment["QDRANT_INTEGRATION"] == "1" else {
            throw XCTSkip("integration only")
        }
    }

    func testRESTParitySurface() async throws {
        try skipUnlessIntegration()
        let c = QdrantRESTClient(host: "localhost", port: 6333)
        let name = "swift_parity_rest"
        _ = try? await c.deleteCollection(name)
        _ = try await c.createCollection(name: name, size: 4, distance: .cosine)

        try await c.upsert(collection: name, points: [
            .init(id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: ["city": "Berlin", "tag": "x"]),
            .init(id: 2, vector: [0.9, 0.8, 0.7, 0.6], payload: ["city": "Tokyo", "tag": "x"]),
        ])

        // Payload index + facet.
        _ = try await c.createPayloadIndex(collection: name, fieldName: "city", fieldType: .keyword, wait: true)
        let facets = try await c.facet(collection: name, key: "city", filter: nil, limit: nil, exact: true)
        XCTAssertEqual(Set(facets.map(\.value)), [.string("Berlin"), .string("Tokyo")])

        // overwrite / delete / clear payload.
        _ = try await c.overwritePayload(collection: name, payload: ["only": "this"], selector: .ids([1]), wait: true)
        var got = try await c.retrieve(collection: name, ids: [1], withPayload: true, withVectors: false)
        XCTAssertNil(got.first?.payload["city"])
        XCTAssertEqual(got.first?.payload["only"], "this")
        _ = try await c.deletePayload(collection: name, keys: ["only"], selector: .ids([1]), wait: true)
        got = try await c.retrieve(collection: name, ids: [1], withPayload: true, withVectors: false)
        XCTAssertNil(got.first?.payload["only"])

        // query batch + groups.
        let batch = try await c.queryBatch(collection: name, queries: [
            .init(query: .nearest(.dense([0.1, 0.2, 0.3, 0.4])), limit: 1),
            .init(query: .nearest(.dense([0.9, 0.8, 0.7, 0.6])), limit: 1),
        ])
        XCTAssertEqual(batch[0].first?.id, .int(1))
        XCTAssertEqual(batch[1].first?.id, .int(2))

        let groups = try await c.queryGroups(
            collection: name, groupBy: "tag", query: .nearest(.dense([0.1, 0.2, 0.3, 0.4])),
            using: nil, prefetch: [], filter: nil, params: nil, scoreThreshold: nil,
            limit: 10, groupSize: 5, withPayload: true, withVectors: false)
        XCTAssertEqual(groups.first?.id, .string("x"))

        // aliases.
        _ = try await c.updateAliases([.create(collection: name, alias: "\(name)_a")])
        let aliases = try await c.listCollectionAliases(name)
        XCTAssertEqual(aliases.first?.aliasName, "\(name)_a")
        _ = try await c.updateAliases([.delete(alias: "\(name)_a")])

        // update collection.
        let updated = try await c.updateCollection(name: name, optimizersConfig: .init(defaultSegmentNumber: 2), hnswConfig: nil)
        XCTAssertTrue(updated)

        // snapshots.
        let snap = try await c.createSnapshot(collection: name)
        XCTAssertNotNil(snap)
        let snaps = try await c.listSnapshots(collection: name)
        XCTAssertFalse(snaps.isEmpty)
        if let s = snap?.name { try await c.deleteSnapshot(collection: name, snapshotName: s) }

        // service / cluster info (just assert they return without error).
        let info = try await c.info()
        XCTAssertFalse(info.version.isEmpty)
        _ = try await c.clusterStatus()
        _ = try await c.collectionClusterInfo(collection: name)
        _ = try await c.getOptimizations(collection: name)

        _ = try await c.deleteCollection(name)
        try await c.close()
    }

    func testGRPCInfoAndVectorName() async throws {
        try skipUnlessIntegration()
        let c = try QdrantClient(host: "localhost")
        let info = try await c.info()
        XCTAssertFalse(info.version.isEmpty)

        let name = "swift_parity_grpc"
        _ = try? await c.deleteCollection(name)
        _ = try await c.createCollection(name: name, vectors: .named(["a": .init(size: 2, distance: .cosine)]),
                                         sparseVectors: nil, hnswConfig: nil, optimizersConfig: nil,
                                         onDiskPayload: nil, shardNumber: nil, replicationFactor: nil)
        _ = try await c.createVectorName(collection: name, vectorName: "b", config: .init(size: 3, distance: .dot), wait: true)
        _ = try await c.deleteVectorName(collection: name, vectorName: "b", wait: true)
        _ = try await c.deleteCollection(name)
        try await c.close()
    }

    /// Payload-field selectors + enriched CollectionInfo (payloadSchema) live.
    func testSelectorsAndPayloadSchemaLive() async throws {
        try skipUnlessIntegration()
        let c = try QdrantClient(host: "localhost")
        let name = "swift_selectors"
        _ = try? await c.deleteCollection(name)
        _ = try await c.createCollection(name: name, size: 3, distance: .cosine)
        try await c.upsert(collection: name, points: [
            .init(id: 1, vector: [1, 0, 0], payload: ["city": "Berlin", "country": "DE", "pop": 3_500_000]),
        ])
        _ = try await c.createPayloadIndex(collection: name, fieldName: "city", fieldType: .keyword, wait: true)

        // with_payload include subset
        let hits = try await c.query(collection: name, query: .nearest(.dense([1, 0, 0])),
                                     using: nil, prefetch: [], filter: nil, params: nil, scoreThreshold: nil,
                                     limit: 1, offset: 0, withPayload: ["city"], withVectors: false)
        XCTAssertEqual(hits.first?.payload.keys.sorted(), ["city"])

        // enriched CollectionInfo carries the indexed field schema
        let info = try await c.getCollection(name)
        XCTAssertEqual(info.payloadSchema["city"], .keyword)

        _ = try await c.deleteCollection(name)
        try await c.close()
    }

    /// Create a collection with quantization + full HNSW/optimizer config (the
    /// model surface that was previously missing) and confirm the server accepts it.
    func testQuantizationConfigLive() async throws {
        try skipUnlessIntegration()
        let c = try QdrantClient(host: "localhost")
        let name = "swift_quant"
        _ = try? await c.deleteCollection(name)
        let created = try await c.createCollection(
            name: name,
            vectors: .single(.init(size: 8, distance: .cosine, onDisk: true, datatype: .float16,
                                   hnswConfig: .init(m: 16, efConstruct: 100, payloadM: 8),
                                   quantizationConfig: .scalar(.init(type: .int8, quantile: 0.99, alwaysRam: true)))),
            optimizersConfig: .init(defaultSegmentNumber: 2, indexingThreshold: 10_000),
            walConfig: .init(walCapacityMb: 32))
        XCTAssertTrue(created)

        // Update quantization to binary, then verify the collection is still green.
        _ = try await c.updateCollection(name: name, quantizationConfig: .binary(.init(alwaysRam: true)))
        let info = try await c.getCollection(name)
        XCTAssertNotEqual(info.status, .red)

        _ = try await c.deleteCollection(name)
        try await c.close()
    }

    /// Migrate a collection from a remote (gRPC) client into an in-memory local client.
    func testMigrateRemoteToLocal() async throws {
        try skipUnlessIntegration()
        let remote = try QdrantClient(host: "localhost")
        let name = "swift_parity_migrate"
        _ = try? await remote.deleteCollection(name)
        _ = try await remote.createCollection(name: name, size: 3, distance: .cosine)
        try await remote.upsert(collection: name, points: [
            .init(id: 1, vector: [1, 0, 0], payload: ["k": "v1"]),
            .init(id: 2, vector: [0, 1, 0], payload: ["k": "v2"]),
        ])

        let local = QdrantLocalClient()
        try await remote.migrate(to: local, collectionNames: [name], batchSize: 100, recreateOnCollision: true)
        let count = try await local.count(collection: name, filter: nil, exact: true)
        XCTAssertEqual(count, 2)
        let hits = try await local.query(collection: name, vector: [1, 0, 0], limit: 1)
        XCTAssertEqual(hits.first?.id, .int(1))
        XCTAssertEqual(hits.first?.payload["k"], "v1")

        _ = try await remote.deleteCollection(name)
        try await remote.close()
    }
}
