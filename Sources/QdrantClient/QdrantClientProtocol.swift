import Foundation

/// A transport-agnostic Qdrant client surface.
///
/// Three backends conform to this protocol, so application code can swap between
/// them without changes:
/// - ``QdrantClient`` — remote, over gRPC.
/// - ``QdrantRESTClient`` — remote, over the REST/HTTP API.
/// - ``QdrantLocalClient`` — in-process, in-memory (no server).
///
/// The protocol is written against the library's transport-neutral model types
/// (``PointStruct``, ``Filter``, ``Query``, ``ScoredPoint``, …). Concrete types
/// provide ergonomic default arguments; when calling through the protocol type
/// all arguments must be supplied.
public protocol QdrantClientProtocol: Sendable {
    // MARK: Collections
    func createCollection(
        name: String,
        vectors: VectorsConfiguration,
        sparseVectors: [String: SparseVectorParams]?,
        quantizationConfig: QuantizationConfig?,
        hnswConfig: HnswConfig?,
        optimizersConfig: OptimizersConfig?,
        walConfig: WalConfig?,
        onDiskPayload: Bool?,
        shardNumber: UInt32?,
        shardingMethod: ShardingMethod?,
        replicationFactor: UInt32?,
        writeConsistencyFactor: UInt32?,
        strictModeConfig: StrictModeConfig?
    ) async throws -> Bool

    func collectionExists(_ name: String) async throws -> Bool
    func listCollections() async throws -> [String]
    func deleteCollection(_ name: String) async throws -> Bool
    func getCollection(_ name: String) async throws -> CollectionInfo

    // MARK: Points (write)
    func upsert(collection: String, points: [PointStruct], wait: Bool) async throws -> UpdateResult
    func delete(collection: String, selector: PointsSelector, wait: Bool) async throws -> UpdateResult
    func setPayload(
        collection: String, payload: Payload, selector: PointsSelector, key: String?, wait: Bool
    ) async throws -> UpdateResult

    // MARK: Points (read)
    func retrieve(
        collection: String, ids: [PointID], withPayload: WithPayload, withVectors: WithVectors
    ) async throws -> [RetrievedPoint]
    func scroll(
        collection: String, filter: Filter?, limit: UInt32, offset: PointID?,
        withPayload: WithPayload, withVectors: WithVectors, orderBy: OrderBy?
    ) async throws -> (points: [RetrievedPoint], nextOffset: PointID?)
    func count(collection: String, filter: Filter?, exact: Bool) async throws -> UInt64

    // MARK: Query
    func query(
        collection: String, query: Query?, using: String?, prefetch: [Prefetch],
        filter: Filter?, params: SearchParams?, scoreThreshold: Float?,
        limit: UInt64, offset: UInt64, withPayload: WithPayload, withVectors: WithVectors
    ) async throws -> [ScoredPoint]

    // MARK: Payload (extended)
    func overwritePayload(collection: String, payload: Payload, selector: PointsSelector, wait: Bool) async throws -> UpdateResult
    func deletePayload(collection: String, keys: [String], selector: PointsSelector, wait: Bool) async throws -> UpdateResult
    func clearPayload(collection: String, selector: PointsSelector, wait: Bool) async throws -> UpdateResult
    func createPayloadIndex(collection: String, fieldName: String, fieldType: FieldType, wait: Bool) async throws -> UpdateResult
    func deletePayloadIndex(collection: String, fieldName: String, wait: Bool) async throws -> UpdateResult

    // MARK: Vectors (extended)
    func updateVectors(collection: String, points: [(id: PointID, vectors: PointVectors)], wait: Bool) async throws -> UpdateResult
    func deleteVectors(collection: String, vectorNames: [String], selector: PointsSelector, wait: Bool) async throws -> UpdateResult
    func createVectorName(collection: String, vectorName: String, config: VectorNameConfig, wait: Bool) async throws -> UpdateResult
    func deleteVectorName(collection: String, vectorName: String, wait: Bool) async throws -> UpdateResult

    // MARK: Batch
    func batchUpdate(collection: String, operations: [UpdateOperation], wait: Bool) async throws -> [UpdateResult]

    // MARK: Query (extended)
    func facet(collection: String, key: String, filter: Filter?, limit: UInt64?, exact: Bool) async throws -> [FacetHit]
    func queryBatch(collection: String, queries: [QueryRequest]) async throws -> [[ScoredPoint]]
    func queryGroups(
        collection: String, groupBy: String, query: Query?, using: String?, prefetch: [Prefetch],
        filter: Filter?, params: SearchParams?, scoreThreshold: Float?, limit: UInt64,
        groupSize: UInt64, withPayload: WithPayload, withVectors: WithVectors
    ) async throws -> [PointGroup]
    func searchMatrixPairs(collection: String, filter: Filter?, sample: UInt64, limit: UInt64, using: String?) async throws -> [SearchMatrixPair]
    func searchMatrixOffsets(collection: String, filter: Filter?, sample: UInt64, limit: UInt64, using: String?) async throws -> SearchMatrixOffsets

    // MARK: Collections (extended)
    func updateCollection(name: String, optimizersConfig: OptimizersConfig?, hnswConfig: HnswConfig?, quantizationConfig: QuantizationConfig?, strictModeConfig: StrictModeConfig?) async throws -> Bool
    func getCollections() async throws -> [String]
    func updateAliases(_ actions: [AliasOperation]) async throws -> Bool
    func listCollectionAliases(_ collection: String) async throws -> [AliasDescription]
    func listAliases() async throws -> [AliasDescription]
    func createShardKey(collection: String, shardKey: ShardKey, shardsNumber: UInt32?, replicationFactor: UInt32?) async throws -> Bool
    func deleteShardKey(collection: String, shardKey: ShardKey) async throws -> Bool
    func listShardKeys(collection: String) async throws -> [ShardKey]

    // MARK: Snapshots
    func createSnapshot(collection: String) async throws -> SnapshotDescription?
    func listSnapshots(collection: String) async throws -> [SnapshotDescription]
    func deleteSnapshot(collection: String, snapshotName: String) async throws
    func createFullSnapshot() async throws -> SnapshotDescription?
    func listFullSnapshots() async throws -> [SnapshotDescription]
    func deleteFullSnapshot(snapshotName: String) async throws
    func recoverSnapshot(collection: String, location: String) async throws -> Bool
    func listShardSnapshots(collection: String, shardId: UInt32) async throws -> [SnapshotDescription]
    func createShardSnapshot(collection: String, shardId: UInt32) async throws -> SnapshotDescription?
    func deleteShardSnapshot(collection: String, shardId: UInt32, snapshotName: String) async throws
    func recoverShardSnapshot(collection: String, shardId: UInt32, location: String) async throws -> Bool

    // MARK: Cluster / service
    func info() async throws -> VersionInfo
    func collectionClusterInfo(collection: String) async throws -> JSONValue
    func clusterCollectionUpdate(collection: String, operation: ClusterOperation) async throws -> Bool
    func clusterStatus() async throws -> JSONValue
    func recoverCurrentPeer() async throws -> Bool
    func removePeer(peerId: UInt64, force: Bool) async throws -> Bool
    func getOptimizations(collection: String) async throws -> JSONValue
    func clusterTelemetry() async throws -> JSONValue

    // MARK: Bulk upload / lifecycle
    func recreateCollection(
        name: String, vectors: VectorsConfiguration, sparseVectors: [String: SparseVectorParams]?
    ) async throws -> Bool
    func uploadPoints(collection: String, points: [PointStruct], batchSize: Int, wait: Bool) async throws
    func uploadCollection(
        collection: String, vectors: [[Float]], payloads: [Payload]?, ids: [PointID]?,
        batchSize: Int, wait: Bool
    ) async throws
    func migrate(to dest: any QdrantClientProtocol, collectionNames: [String]?, batchSize: Int, recreateOnCollision: Bool) async throws

    // MARK: Lifecycle
    func close() async throws
}

/// The gRPC client conforms to the shared protocol.
extension QdrantClient: QdrantClientProtocol {}

// MARK: - Shared ergonomic helpers

extension QdrantClientProtocol {
    /// Create a collection with a single unnamed dense vector.
    @discardableResult
    public func createCollection(
        name: String, size: UInt64, distance: Distance = .cosine
    ) async throws -> Bool {
        try await createCollection(
            name: name,
            vectors: .single(.init(size: size, distance: distance)),
            sparseVectors: nil, quantizationConfig: nil, hnswConfig: nil, optimizersConfig: nil,
            walConfig: nil, onDiskPayload: nil, shardNumber: nil, shardingMethod: nil,
            replicationFactor: nil, writeConsistencyFactor: nil, strictModeConfig: nil)
    }

    /// Nearest-neighbour query by a dense vector.
    public func query(
        collection: String, vector: [Float], limit: UInt64 = 10,
        using: String? = nil, filter: Filter? = nil,
        withPayload: WithPayload = true, withVectors: WithVectors = false
    ) async throws -> [ScoredPoint] {
        try await query(
            collection: collection, query: .nearest(.dense(vector)), using: using,
            prefetch: [], filter: filter, params: nil, scoreThreshold: nil,
            limit: limit, offset: 0, withPayload: withPayload, withVectors: withVectors)
    }

    // MARK: Real shared defaults (work on every backend)

    /// `get_collections` — alias of ``listCollections()``.
    public func getCollections() async throws -> [String] { try await listCollections() }

    /// Delete (if present) then create a collection.
    @discardableResult
    public func recreateCollection(
        name: String, vectors: VectorsConfiguration, sparseVectors: [String: SparseVectorParams]? = nil
    ) async throws -> Bool {
        _ = try? await deleteCollection(name)
        return try await createCollection(
            name: name, vectors: vectors, sparseVectors: sparseVectors,
            quantizationConfig: nil, hnswConfig: nil, optimizersConfig: nil,
            walConfig: nil, onDiskPayload: nil, shardNumber: nil, shardingMethod: nil,
            replicationFactor: nil, writeConsistencyFactor: nil, strictModeConfig: nil)
    }

    /// Upload points in batches (chunked upsert).
    public func uploadPoints(collection: String, points: [PointStruct], batchSize: Int = 64, wait: Bool = true) async throws {
        var i = 0
        while i < points.count {
            let chunk = Array(points[i..<min(i + batchSize, points.count)])
            _ = try await upsert(collection: collection, points: chunk, wait: wait)
            i += batchSize
        }
    }

    /// Upload raw vectors (with optional payloads/ids) in batches.
    public func uploadCollection(
        collection: String, vectors: [[Float]], payloads: [Payload]? = nil, ids: [PointID]? = nil,
        batchSize: Int = 64, wait: Bool = true
    ) async throws {
        let points = vectors.enumerated().map { index, vec in
            PointStruct(id: ids?[index] ?? .int(UInt64(index)),
                        vector: vec, payload: payloads?[index] ?? [:])
        }
        try await uploadPoints(collection: collection, points: points, batchSize: batchSize, wait: wait)
    }

    /// Batch update via individual operations (default: apply sequentially).
    @discardableResult
    public func batchUpdate(collection: String, operations: [UpdateOperation], wait: Bool = true) async throws -> [UpdateResult] {
        var results: [UpdateResult] = []
        for op in operations {
            switch op {
            case .upsert(let pts):
                results.append(try await upsert(collection: collection, points: pts, wait: wait))
            case .delete(let sel):
                results.append(try await delete(collection: collection, selector: sel, wait: wait))
            case .setPayload(let payload, let sel, let key):
                results.append(try await setPayload(collection: collection, payload: payload, selector: sel, key: key, wait: wait))
            case .overwritePayload(let payload, let sel):
                results.append(try await overwritePayload(collection: collection, payload: payload, selector: sel, wait: wait))
            case .deletePayload(let keys, let sel):
                results.append(try await deletePayload(collection: collection, keys: keys, selector: sel, wait: wait))
            case .clearPayload(let sel):
                results.append(try await clearPayload(collection: collection, selector: sel, wait: wait))
            case .updateVectors(let pts):
                results.append(try await updateVectors(collection: collection, points: pts, wait: wait))
            case .deleteVectors(let names, let sel):
                results.append(try await deleteVectors(collection: collection, vectorNames: names, selector: sel, wait: wait))
            }
        }
        return results
    }

    /// Copy collections (schema + points) from this client into `dest`.
    public func migrate(
        to dest: any QdrantClientProtocol, collectionNames: [String]? = nil,
        batchSize: Int = 100, recreateOnCollision: Bool = false
    ) async throws {
        let names: [String]
        if let collectionNames { names = collectionNames } else { names = try await listCollections() }
        for name in names {
            let exists = try await dest.collectionExists(name)
            if exists {
                if recreateOnCollision { _ = try await dest.deleteCollection(name) }
                else { continue }
            }
            // Recreate schema from the source collection's vector config.
            let cfg = try await collectionVectorsConfig(name)
            _ = try await dest.createCollection(
                name: name, vectors: cfg, sparseVectors: nil, quantizationConfig: nil,
                hnswConfig: nil, optimizersConfig: nil, walConfig: nil, onDiskPayload: nil,
                shardNumber: nil, shardingMethod: nil, replicationFactor: nil, writeConsistencyFactor: nil, strictModeConfig: nil)
            // Copy points by scrolling.
            var offset: PointID? = nil
            repeat {
                let page = try await scroll(
                    collection: name, filter: nil, limit: UInt32(batchSize), offset: offset,
                    withPayload: true, withVectors: true, orderBy: nil)
                let points = page.points.map { rec -> PointStruct in
                    if !rec.vectors.isEmpty {
                        return PointStruct(id: rec.id, vectors: rec.vectors, payload: rec.payload)
                    }
                    return PointStruct(id: rec.id, vector: rec.vector ?? [], payload: rec.payload)
                }
                if !points.isEmpty {
                    _ = try await dest.upsert(collection: name, points: points, wait: true)
                }
                offset = page.nextOffset
            } while offset != nil
        }
    }

    /// Best-effort source vector config for `migrate` (single dense by default).
    private func collectionVectorsConfig(_ name: String) async throws -> VectorsConfiguration {
        // The protocol's CollectionInfo summary doesn't carry full vector params,
        // so infer dimension from a sample point.
        let sample = try await scroll(collection: name, filter: nil, limit: 1, offset: nil,
                                      withPayload: false, withVectors: true, orderBy: nil)
        if let first = sample.points.first {
            if let v = first.vector {
                return .single(.init(size: UInt64(v.count), distance: .cosine))
            }
            if let named = first.vectors.first, case .dense(let d) = named.value {
                return .named([named.key: .init(size: UInt64(d.count), distance: .cosine)])
            }
        }
        return .single(.init(size: 1, distance: .cosine))
    }

    // MARK: Unsupported-by-default (backends override what they support)

    public func overwritePayload(collection: String, payload: Payload, selector: PointsSelector, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("overwritePayload") }
    public func deletePayload(collection: String, keys: [String], selector: PointsSelector, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("deletePayload") }
    public func clearPayload(collection: String, selector: PointsSelector, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("clearPayload") }
    public func createPayloadIndex(collection: String, fieldName: String, fieldType: FieldType, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("createPayloadIndex") }
    public func deletePayloadIndex(collection: String, fieldName: String, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("deletePayloadIndex") }
    public func updateVectors(collection: String, points: [(id: PointID, vectors: PointVectors)], wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("updateVectors") }
    public func deleteVectors(collection: String, vectorNames: [String], selector: PointsSelector, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("deleteVectors") }
    public func createVectorName(collection: String, vectorName: String, config: VectorNameConfig, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("createVectorName") }
    public func deleteVectorName(collection: String, vectorName: String, wait: Bool) async throws -> UpdateResult { throw QdrantError.unsupported("deleteVectorName") }
    public func facet(collection: String, key: String, filter: Filter?, limit: UInt64?, exact: Bool) async throws -> [FacetHit] { throw QdrantError.unsupported("facet") }
    public func queryBatch(collection: String, queries: [QueryRequest]) async throws -> [[ScoredPoint]] { throw QdrantError.unsupported("queryBatch") }
    public func queryGroups(collection: String, groupBy: String, query: Query?, using: String?, prefetch: [Prefetch], filter: Filter?, params: SearchParams?, scoreThreshold: Float?, limit: UInt64, groupSize: UInt64, withPayload: WithPayload, withVectors: WithVectors) async throws -> [PointGroup] { throw QdrantError.unsupported("queryGroups") }
    public func searchMatrixPairs(collection: String, filter: Filter?, sample: UInt64, limit: UInt64, using: String?) async throws -> [SearchMatrixPair] { throw QdrantError.unsupported("searchMatrixPairs") }
    public func searchMatrixOffsets(collection: String, filter: Filter?, sample: UInt64, limit: UInt64, using: String?) async throws -> SearchMatrixOffsets { throw QdrantError.unsupported("searchMatrixOffsets") }
    public func updateCollection(name: String, optimizersConfig: OptimizersConfig?, hnswConfig: HnswConfig?, quantizationConfig: QuantizationConfig?, strictModeConfig: StrictModeConfig?) async throws -> Bool { throw QdrantError.unsupported("updateCollection") }
    public func updateAliases(_ actions: [AliasOperation]) async throws -> Bool { throw QdrantError.unsupported("updateAliases") }
    public func listCollectionAliases(_ collection: String) async throws -> [AliasDescription] { throw QdrantError.unsupported("listCollectionAliases") }
    public func listAliases() async throws -> [AliasDescription] { throw QdrantError.unsupported("listAliases") }
    public func createShardKey(collection: String, shardKey: ShardKey, shardsNumber: UInt32?, replicationFactor: UInt32?) async throws -> Bool { throw QdrantError.unsupported("createShardKey") }
    public func deleteShardKey(collection: String, shardKey: ShardKey) async throws -> Bool { throw QdrantError.unsupported("deleteShardKey") }
    public func listShardKeys(collection: String) async throws -> [ShardKey] { throw QdrantError.unsupported("listShardKeys") }
    public func createSnapshot(collection: String) async throws -> SnapshotDescription? { throw QdrantError.unsupported("createSnapshot") }
    public func listSnapshots(collection: String) async throws -> [SnapshotDescription] { throw QdrantError.unsupported("listSnapshots") }
    public func deleteSnapshot(collection: String, snapshotName: String) async throws { throw QdrantError.unsupported("deleteSnapshot") }
    public func createFullSnapshot() async throws -> SnapshotDescription? { throw QdrantError.unsupported("createFullSnapshot") }
    public func listFullSnapshots() async throws -> [SnapshotDescription] { throw QdrantError.unsupported("listFullSnapshots") }
    public func deleteFullSnapshot(snapshotName: String) async throws { throw QdrantError.unsupported("deleteFullSnapshot") }
    public func recoverSnapshot(collection: String, location: String) async throws -> Bool { throw QdrantError.unsupported("recoverSnapshot") }
    public func listShardSnapshots(collection: String, shardId: UInt32) async throws -> [SnapshotDescription] { throw QdrantError.unsupported("listShardSnapshots") }
    public func createShardSnapshot(collection: String, shardId: UInt32) async throws -> SnapshotDescription? { throw QdrantError.unsupported("createShardSnapshot") }
    public func deleteShardSnapshot(collection: String, shardId: UInt32, snapshotName: String) async throws { throw QdrantError.unsupported("deleteShardSnapshot") }
    public func recoverShardSnapshot(collection: String, shardId: UInt32, location: String) async throws -> Bool { throw QdrantError.unsupported("recoverShardSnapshot") }
    public func info() async throws -> VersionInfo { throw QdrantError.unsupported("info") }
    public func collectionClusterInfo(collection: String) async throws -> JSONValue { throw QdrantError.unsupported("collectionClusterInfo") }
    public func clusterCollectionUpdate(collection: String, operation: ClusterOperation) async throws -> Bool { throw QdrantError.unsupported("clusterCollectionUpdate") }
    public func clusterStatus() async throws -> JSONValue { throw QdrantError.unsupported("clusterStatus") }
    public func recoverCurrentPeer() async throws -> Bool { throw QdrantError.unsupported("recoverCurrentPeer") }
    public func removePeer(peerId: UInt64, force: Bool) async throws -> Bool { throw QdrantError.unsupported("removePeer") }
    public func getOptimizations(collection: String) async throws -> JSONValue { throw QdrantError.unsupported("getOptimizations") }
    public func clusterTelemetry() async throws -> JSONValue { throw QdrantError.unsupported("clusterTelemetry") }
}
