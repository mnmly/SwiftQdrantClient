import Foundation
import QdrantProtos

/// Remaining gRPC-native methods for full parity with the Python client.
extension QdrantClient {
    /// Server version info (from the gRPC health check).
    public func info() async throws -> VersionInfo {
        let reply = try await healthCheck()
        return VersionInfo(title: reply.title, version: reply.version,
                           commit: reply.hasCommit ? reply.commit : nil)
    }

    /// Add a new named dense vector to an existing collection.
    @discardableResult
    public func createVectorName(
        collection: String, vectorName: String, config: VectorNameConfig, wait: Bool = true
    ) async throws -> UpdateResult {
        var dense = Qdrant_DenseVectorCreationConfig()
        dense.size = config.size
        dense.distance = config.distance.proto
        if let datatype = config.datatype { dense.datatype = datatype.proto }
        var request = Qdrant_CreateVectorNameRequest()
        request.collectionName = collection
        request.vectorName = vectorName
        request.denseConfig = dense
        request.wait = wait
        let response = try await call { try await points.createVectorName(request) }
        return UpdateResult(response.result)
    }

    /// Remove a named vector from a collection.
    @discardableResult
    public func deleteVectorName(
        collection: String, vectorName: String, wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_DeleteVectorNameRequest()
        request.collectionName = collection
        request.vectorName = vectorName
        request.wait = wait
        let response = try await call { try await points.deleteVectorName(request) }
        return UpdateResult(response.result)
    }

    /// Cluster info for a collection (decoded as JSON).
    public func collectionClusterInfo(collection: String) async throws -> JSONValue {
        var request = Qdrant_CollectionClusterInfoRequest()
        request.collectionName = collection
        let response = try await call { try await collections.collectionClusterInfo(request) }
        return .object([
            "peer_id": .int(Int64(response.peerID)),
            "shard_count": .int(Int64(response.shardCount)),
        ])
    }

    /// Apply a cluster shard operation to a collection.
    @discardableResult
    public func clusterCollectionUpdate(collection: String, operation: ClusterOperation) async throws -> Bool {
        var request = Qdrant_UpdateCollectionClusterSetupRequest()
        request.collectionName = collection
        switch operation {
        case .moveShard(let shardId, let from, let to):
            var op = Qdrant_MoveShard()
            op.shardID = shardId; op.fromPeerID = from; op.toPeerID = to
            request.moveShard = op
        case .replicateShard(let shardId, let from, let to):
            var op = Qdrant_ReplicateShard()
            op.shardID = shardId; op.fromPeerID = from; op.toPeerID = to
            request.replicateShard = op
        case .abortTransfer(let shardId, let from, let to):
            var op = Qdrant_AbortShardTransfer()
            op.shardID = shardId; op.fromPeerID = from; op.toPeerID = to
            request.abortTransfer = op
        case .dropReplica(let shardId, let peerId):
            var op = Qdrant_Replica()
            op.shardID = shardId; op.peerID = peerId
            request.dropReplica = op
        }
        let response = try await call { try await collections.updateCollectionClusterSetup(request) }
        return response.result
    }

    // MARK: - REST-only operations (delegated to the internal REST client)

    @discardableResult
    public func recoverSnapshot(collection: String, location: String) async throws -> Bool {
        try await rest.recoverSnapshot(collection: collection, location: location)
    }
    public func listShardSnapshots(collection: String, shardId: UInt32) async throws -> [SnapshotDescription] {
        try await rest.listShardSnapshots(collection: collection, shardId: shardId)
    }
    @discardableResult
    public func createShardSnapshot(collection: String, shardId: UInt32) async throws -> SnapshotDescription? {
        try await rest.createShardSnapshot(collection: collection, shardId: shardId)
    }
    public func deleteShardSnapshot(collection: String, shardId: UInt32, snapshotName: String) async throws {
        try await rest.deleteShardSnapshot(collection: collection, shardId: shardId, snapshotName: snapshotName)
    }
    @discardableResult
    public func recoverShardSnapshot(collection: String, shardId: UInt32, location: String) async throws -> Bool {
        try await rest.recoverShardSnapshot(collection: collection, shardId: shardId, location: location)
    }
    public func clusterStatus() async throws -> JSONValue { try await rest.clusterStatus() }
    @discardableResult
    public func recoverCurrentPeer() async throws -> Bool { try await rest.recoverCurrentPeer() }
    @discardableResult
    public func removePeer(peerId: UInt64, force: Bool = false) async throws -> Bool {
        try await rest.removePeer(peerId: peerId, force: force)
    }
    public func getOptimizations(collection: String) async throws -> JSONValue {
        try await rest.getOptimizations(collection: collection)
    }
    public func clusterTelemetry() async throws -> JSONValue { try await rest.clusterTelemetry() }
}
