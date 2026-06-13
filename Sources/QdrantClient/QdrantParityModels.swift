import Foundation

/// Server version information. Mirrors Python `models.VersionInfo`.
public struct VersionInfo: Sendable {
    public let title: String
    public let version: String
    public let commit: String?

    public init(title: String, version: String, commit: String? = nil) {
        self.title = title
        self.version = version
        self.commit = commit
    }
}

/// Configuration for a newly added named vector. Mirrors Python `VectorNameConfig`
/// — equivalent to ``VectorParams``.
public typealias VectorNameConfig = VectorParams

/// One operation in a `batchUpdate` call. Mirrors Python `models.UpdateOperation`.
public enum UpdateOperation: Sendable {
    case upsert([PointStruct])
    case delete(PointsSelector)
    case setPayload(payload: Payload, selector: PointsSelector, key: String? = nil)
    case overwritePayload(payload: Payload, selector: PointsSelector)
    case deletePayload(keys: [String], selector: PointsSelector)
    case clearPayload(PointsSelector)
    case updateVectors([(id: PointID, vectors: PointVectors)])
    case deleteVectors(names: [String], selector: PointsSelector)
}

/// A cluster shard operation. Mirrors Python `models.ClusterOperations`.
public enum ClusterOperation: Sendable {
    case moveShard(shardId: UInt32, fromPeer: UInt64, toPeer: UInt64)
    case replicateShard(shardId: UInt32, fromPeer: UInt64, toPeer: UInt64)
    case abortTransfer(shardId: UInt32, fromPeer: UInt64, toPeer: UInt64)
    case dropReplica(shardId: UInt32, peerId: UInt64)
}
