import Foundation
import QdrantProtos

/// A snapshot's metadata. Mirrors Python `models.SnapshotDescription`.
public struct SnapshotDescription: Sendable {
    public let name: String
    public let creationTime: Date?
    public let size: Int64
    public let checksum: String?

    public init(name: String, creationTime: Date? = nil, size: Int64 = 0, checksum: String? = nil) {
        self.name = name
        self.creationTime = creationTime
        self.size = size
        self.checksum = checksum
    }

    init(_ proto: Qdrant_SnapshotDescription) {
        self.name = proto.name
        self.creationTime = proto.hasCreationTime ? proto.creationTime.date : nil
        self.size = proto.size
        self.checksum = proto.hasChecksum ? proto.checksum : nil
    }
}

/// Snapshots API. Mirrors the snapshot methods of the Python client.
extension QdrantClient {
    // MARK: - Collection snapshots

    /// Create a snapshot of a collection.
    @discardableResult
    public func createSnapshot(collection: String) async throws -> SnapshotDescription? {
        var request = Qdrant_CreateSnapshotRequest()
        request.collectionName = collection
        let response = try await call { try await snapshots.create(request) }
        return response.hasSnapshotDescription ? SnapshotDescription(response.snapshotDescription) : nil
    }

    /// List snapshots of a collection.
    public func listSnapshots(collection: String) async throws -> [SnapshotDescription] {
        var request = Qdrant_ListSnapshotsRequest()
        request.collectionName = collection
        let response = try await call { try await snapshots.list(request) }
        return response.snapshotDescriptions.map(SnapshotDescription.init)
    }

    /// Delete a collection snapshot by name.
    public func deleteSnapshot(collection: String, snapshotName: String) async throws {
        var request = Qdrant_DeleteSnapshotRequest()
        request.collectionName = collection
        request.snapshotName = snapshotName
        _ = try await call { try await snapshots.delete(request) }
    }

    // MARK: - Full (whole-storage) snapshots

    /// Create a snapshot of the entire storage.
    @discardableResult
    public func createFullSnapshot() async throws -> SnapshotDescription? {
        let response = try await call { try await snapshots.createFull(Qdrant_CreateFullSnapshotRequest()) }
        return response.hasSnapshotDescription ? SnapshotDescription(response.snapshotDescription) : nil
    }

    /// List full storage snapshots.
    public func listFullSnapshots() async throws -> [SnapshotDescription] {
        let response = try await call { try await snapshots.listFull(Qdrant_ListFullSnapshotsRequest()) }
        return response.snapshotDescriptions.map(SnapshotDescription.init)
    }

    /// Delete a full storage snapshot by name.
    public func deleteFullSnapshot(snapshotName: String) async throws {
        var request = Qdrant_DeleteFullSnapshotRequest()
        request.snapshotName = snapshotName
        _ = try await call { try await snapshots.deleteFull(request) }
    }
}
