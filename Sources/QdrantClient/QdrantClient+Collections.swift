import Foundation
import QdrantProtos

/// Richer collections API. Mirrors the collections methods of the Python client.
extension QdrantClient {
    /// Create a collection with full vector configuration (named/sparse vectors,
    /// HNSW/optimizer tuning, sharding/replication).
    @discardableResult
    public func createCollection(
        name: String,
        vectors: VectorsConfiguration,
        sparseVectors: [String: SparseVectorParams]? = nil,
        hnswConfig: HnswConfig? = nil,
        optimizersConfig: OptimizersConfig? = nil,
        onDiskPayload: Bool? = nil,
        shardNumber: UInt32? = nil,
        replicationFactor: UInt32? = nil
    ) async throws -> Bool {
        var request = Qdrant_CreateCollection()
        request.collectionName = name
        request.vectorsConfig = vectors.proto
        if let sparseVectors {
            var sc = Qdrant_SparseVectorConfig()
            sc.map = sparseVectors.mapValues(\.proto)
            request.sparseVectorsConfig = sc
        }
        if let hnswConfig { request.hnswConfig = hnswConfig.proto }
        if let optimizersConfig { request.optimizersConfig = optimizersConfig.proto }
        if let onDiskPayload { request.onDiskPayload = onDiskPayload }
        if let shardNumber { request.shardNumber = shardNumber }
        if let replicationFactor { request.replicationFactor = replicationFactor }

        let response = try await call { try await collections.create(request) }
        return response.result
    }

    /// Get detailed information about a collection.
    public func getCollection(_ name: String) async throws -> CollectionInfo {
        var request = Qdrant_GetCollectionInfoRequest()
        request.collectionName = name
        let response = try await call { try await collections.get(request) }
        return CollectionInfo(response.result)
    }

    /// Update a collection's optimizer/HNSW/params configuration.
    @discardableResult
    public func updateCollection(
        name: String,
        optimizersConfig: OptimizersConfig? = nil,
        hnswConfig: HnswConfig? = nil
    ) async throws -> Bool {
        var request = Qdrant_UpdateCollection()
        request.collectionName = name
        if let optimizersConfig { request.optimizersConfig = optimizersConfig.proto }
        if let hnswConfig { request.hnswConfig = hnswConfig.proto }
        let response = try await call { try await collections.update(request) }
        return response.result
    }

    // MARK: - Aliases

    /// Apply a batch of alias mutations atomically.
    @discardableResult
    public func updateAliases(_ actions: [AliasOperation]) async throws -> Bool {
        var request = Qdrant_ChangeAliases()
        request.actions = actions.map(\.proto)
        let response = try await call { try await collections.updateAliases(request) }
        return response.result
    }

    /// Create an alias for a collection.
    @discardableResult
    public func createAlias(collection: String, alias: String) async throws -> Bool {
        try await updateAliases([.create(collection: collection, alias: alias)])
    }

    /// Delete an alias.
    @discardableResult
    public func deleteAlias(_ alias: String) async throws -> Bool {
        try await updateAliases([.delete(alias: alias)])
    }

    /// List aliases for a single collection.
    public func listCollectionAliases(_ collection: String) async throws -> [AliasDescription] {
        var request = Qdrant_ListCollectionAliasesRequest()
        request.collectionName = collection
        let response = try await call { try await collections.listCollectionAliases(request) }
        return response.aliases.map(AliasDescription.init)
    }

    /// List aliases across all collections.
    public func listAliases() async throws -> [AliasDescription] {
        let response = try await call { try await collections.listAliases(Qdrant_ListAliasesRequest()) }
        return response.aliases.map(AliasDescription.init)
    }

    // MARK: - Shard keys

    /// Create a custom shard key on a collection.
    @discardableResult
    public func createShardKey(
        collection: String,
        shardKey: ShardKey,
        shardsNumber: UInt32? = nil,
        replicationFactor: UInt32? = nil
    ) async throws -> Bool {
        var create = Qdrant_CreateShardKey()
        create.shardKey = shardKey.proto
        if let shardsNumber { create.shardsNumber = shardsNumber }
        if let replicationFactor { create.replicationFactor = replicationFactor }
        var request = Qdrant_CreateShardKeyRequest()
        request.collectionName = collection
        request.request = create
        let response = try await call { try await collections.createShardKey(request) }
        return response.result
    }

    /// Delete a custom shard key.
    @discardableResult
    public func deleteShardKey(collection: String, shardKey: ShardKey) async throws -> Bool {
        var del = Qdrant_DeleteShardKey()
        del.shardKey = shardKey.proto
        var request = Qdrant_DeleteShardKeyRequest()
        request.collectionName = collection
        request.request = del
        let response = try await call { try await collections.deleteShardKey(request) }
        return response.result
    }

    /// List custom shard keys of a collection.
    public func listShardKeys(collection: String) async throws -> [ShardKey] {
        var request = Qdrant_ListShardKeysRequest()
        request.collectionName = collection
        let response = try await call { try await collections.listShardKeys(request) }
        return response.shardKeys.map { ShardKey($0.key) }
    }
}
