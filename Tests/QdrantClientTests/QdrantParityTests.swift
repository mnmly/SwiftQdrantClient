import XCTest
@testable import QdrantClient

/// Parity features on the local backend + cross-client migrate — no server.
final class QdrantParityTests: XCTestCase {
    private func seed() async throws -> QdrantLocalClient {
        let c = QdrantLocalClient()
        try await c.createCollection(name: "c", size: 3, distance: .cosine)
        try await c.upsert(collection: "c", points: [
            .init(id: 1, vector: [1, 0, 0], payload: ["cat": "a", "n": 1]),
            .init(id: 2, vector: [0, 1, 0], payload: ["cat": "b", "n": 2]),
            .init(id: 3, vector: [0.9, 0.1, 0], payload: ["cat": "a", "n": 3]),
        ])
        return c
    }

    func testPayloadIndexNoThrow() async throws {
        let c = try await seed()
        _ = try await c.createPayloadIndex(collection: "c", fieldName: "cat", fieldType: .keyword, wait: true)
        _ = try await c.deletePayloadIndex(collection: "c", fieldName: "cat", wait: true)
    }

    func testFacet() async throws {
        let c = try await seed()
        let hits = try await c.facet(collection: "c", key: "cat", filter: nil, limit: nil, exact: true)
        let map = Dictionary(uniqueKeysWithValues: hits.map { ($0.value, $0.count) })
        XCTAssertEqual(map[.string("a")], 2)
        XCTAssertEqual(map[.string("b")], 1)
    }

    func testAliases() async throws {
        let c = try await seed()
        _ = try await c.updateAliases([.create(collection: "c", alias: "c_alias")])
        let aliases = try await c.listAliases()
        XCTAssertEqual(aliases.first?.aliasName, "c_alias")
        // Query through the alias resolves to the real collection.
        let hits = try await c.query(collection: "c_alias", vector: [1, 0, 0], limit: 1)
        XCTAssertEqual(hits.first?.id, .int(1))
    }

    func testUpdateAndDeleteVectors() async throws {
        let c = QdrantLocalClient()
        try await c.createCollection(name: "n", vectors: .named(["a": .init(size: 2), "b": .init(size: 2)]),
                                     sparseVectors: nil, hnswConfig: nil, optimizersConfig: nil,
                                     onDiskPayload: nil, shardNumber: nil, replicationFactor: nil)
        try await c.upsert(collection: "n", points: [.init(id: 1, vectors: ["a": .dense([1, 0]), "b": .dense([0, 1])])])
        _ = try await c.updateVectors(collection: "n", points: [(id: .int(1), vectors: .named(["a": .dense([0, 1])]))], wait: true)
        _ = try await c.deleteVectors(collection: "n", vectorNames: ["b"], selector: .ids([1]), wait: true)
        let got = try await c.retrieve(collection: "n", ids: [1], withPayload: false, withVectors: true)
        XCTAssertEqual(got.first?.vectors["a"], .dense([0, 1]))
        XCTAssertNil(got.first?.vectors["b"])
    }

    func testBatchUpdate() async throws {
        let c = try await seed()
        let results = try await c.batchUpdate(collection: "c", operations: [
            .setPayload(payload: ["tag": "x"], selector: .ids([1])),
            .delete(.ids([2])),
        ], wait: true)
        XCTAssertEqual(results.count, 2)
        let count = try await c.count(collection: "c", filter: nil, exact: true)
        XCTAssertEqual(count, 2)
        let got = try await c.retrieve(collection: "c", ids: [1], withPayload: true, withVectors: false)
        XCTAssertEqual(got.first?.payload["tag"], "x")
    }

    func testQueryGroups() async throws {
        let c = try await seed()
        let groups = try await c.queryGroups(
            collection: "c", groupBy: "cat", query: .nearest(.dense([1, 0, 0])), using: nil, prefetch: [],
            filter: nil, params: nil, scoreThreshold: nil, limit: 10, groupSize: 5,
            withPayload: true, withVectors: false)
        let byId = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.hits.count) })
        XCTAssertEqual(byId[.string("a")], 2)
        XCTAssertEqual(byId[.string("b")], 1)
    }

    func testDiscoverLocal() async throws {
        let c = try await seed()
        let hits = try await c.query(
            collection: "c",
            query: .discover(target: .dense([1, 0, 0]),
                             context: [.init(positive: .dense([1, 0, 0]), negative: .dense([0, 1, 0]))]),
            using: nil, prefetch: [], filter: nil, params: nil, scoreThreshold: nil,
            limit: 1, offset: 0, withPayload: false, withVectors: false)
        XCTAssertEqual(hits.first?.id, .int(1))
    }

    func testUploadAndRecreate() async throws {
        let c = QdrantLocalClient()
        _ = try await c.recreateCollection(name: "u", vectors: .single(.init(size: 2, distance: .dot)))
        try await c.uploadCollection(collection: "u", vectors: [[1, 0], [0, 1], [1, 1]],
                                     payloads: nil, ids: nil, batchSize: 2, wait: true)
        let count = try await c.count(collection: "u", filter: nil, exact: true)
        XCTAssertEqual(count, 3)
    }

    func testMigrateBetweenLocalClients() async throws {
        let src = try await seed()
        let dst = QdrantLocalClient()
        try await src.migrate(to: dst, collectionNames: ["c"], batchSize: 2, recreateOnCollision: true)
        let count = try await dst.count(collection: "c", filter: nil, exact: true)
        XCTAssertEqual(count, 3)
        let hits = try await dst.query(collection: "c", vector: [1, 0, 0], limit: 1)
        XCTAssertEqual(hits.first?.id, .int(1))
        XCTAssertEqual(hits.first?.payload["cat"], "a")
    }

    func testInfoLocal() async throws {
        let c = QdrantLocalClient()
        let info = try await c.info()
        XCTAssertEqual(info.version, "local")
    }
}
