import Foundation
import QdrantProtos

/// Full points API. Mirrors the points-related methods of the Python client.
extension QdrantClient {
    // MARK: - Retrieve / scroll / count

    /// Retrieve points by id.
    public func retrieve(
        collection: String,
        ids: [PointID],
        withPayload: Bool = true,
        withVectors: Bool = false
    ) async throws -> [RetrievedPoint] {
        var request = Qdrant_GetPoints()
        request.collectionName = collection
        request.ids = ids.map(\.proto)
        request.withPayload = Self.payloadSelector(withPayload)
        request.withVectors = Self.vectorsSelector(withVectors)
        let response = try await call { try await points.get(request) }
        return response.result.map(RetrievedPoint.init)
    }

    /// Scroll (page) through points, optionally filtered. Returns the page and
    /// the offset to pass as `offset` for the next page (`nil` when exhausted).
    public func scroll(
        collection: String,
        filter: Filter? = nil,
        limit: UInt32 = 10,
        offset: PointID? = nil,
        withPayload: Bool = true,
        withVectors: Bool = false,
        orderBy: OrderBy? = nil
    ) async throws -> (points: [RetrievedPoint], nextOffset: PointID?) {
        var request = Qdrant_ScrollPoints()
        request.collectionName = collection
        request.limit = limit
        request.withPayload = Self.payloadSelector(withPayload)
        request.withVectors = Self.vectorsSelector(withVectors)
        if let filter { request.filter = filter.proto }
        if let offset { request.offset = offset.proto }
        if let orderBy { request.orderBy = orderBy.proto }
        let response = try await call { try await points.scroll(request) }
        let next = response.hasNextPageOffset ? PointID(response.nextPageOffset) : nil
        return (response.result.map(RetrievedPoint.init), next)
    }

    /// Count points, optionally filtered.
    public func count(
        collection: String,
        filter: Filter? = nil,
        exact: Bool = true
    ) async throws -> UInt64 {
        var request = Qdrant_CountPoints()
        request.collectionName = collection
        request.exact = exact
        if let filter { request.filter = filter.proto }
        let response = try await call { try await points.count(request) }
        return response.result.count
    }

    // MARK: - Delete points

    /// Delete points by id or filter.
    @discardableResult
    public func delete(
        collection: String,
        selector: PointsSelector,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_DeletePoints()
        request.collectionName = collection
        request.wait = wait
        request.points = selector.proto
        let response = try await call { try await points.delete(request) }
        return UpdateResult(response.result)
    }

    /// Delete points by id.
    @discardableResult
    public func delete(
        collection: String,
        ids: [PointID],
        wait: Bool = true
    ) async throws -> UpdateResult {
        try await delete(collection: collection, selector: .ids(ids), wait: wait)
    }

    // MARK: - Payload operations

    /// Set (merge) payload on the selected points.
    @discardableResult
    public func setPayload(
        collection: String,
        payload: Payload,
        selector: PointsSelector,
        key: String? = nil,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_SetPayloadPoints()
        request.collectionName = collection
        request.wait = wait
        request.payload = payload.proto
        request.pointsSelector = selector.proto
        if let key { request.key = key }
        let response = try await call { try await points.setPayload(request) }
        return UpdateResult(response.result)
    }

    /// Overwrite (replace) payload on the selected points.
    @discardableResult
    public func overwritePayload(
        collection: String,
        payload: Payload,
        selector: PointsSelector,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_SetPayloadPoints()
        request.collectionName = collection
        request.wait = wait
        request.payload = payload.proto
        request.pointsSelector = selector.proto
        let response = try await call { try await points.overwritePayload(request) }
        return UpdateResult(response.result)
    }

    /// Delete payload keys from the selected points.
    @discardableResult
    public func deletePayload(
        collection: String,
        keys: [String],
        selector: PointsSelector,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_DeletePayloadPoints()
        request.collectionName = collection
        request.wait = wait
        request.keys = keys
        request.pointsSelector = selector.proto
        let response = try await call { try await points.deletePayload(request) }
        return UpdateResult(response.result)
    }

    /// Clear all payload from the selected points.
    @discardableResult
    public func clearPayload(
        collection: String,
        selector: PointsSelector,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_ClearPayloadPoints()
        request.collectionName = collection
        request.wait = wait
        request.points = selector.proto
        let response = try await call { try await points.clearPayload(request) }
        return UpdateResult(response.result)
    }

    // MARK: - Payload field indexes

    /// Create a payload field index.
    @discardableResult
    public func createPayloadIndex(
        collection: String,
        fieldName: String,
        fieldType: FieldType,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_CreateFieldIndexCollection()
        request.collectionName = collection
        request.fieldName = fieldName
        request.fieldType = fieldType.proto
        request.wait = wait
        let response = try await call { try await points.createFieldIndex(request) }
        return UpdateResult(response.result)
    }

    /// Delete a payload field index.
    @discardableResult
    public func deletePayloadIndex(
        collection: String,
        fieldName: String,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_DeleteFieldIndexCollection()
        request.collectionName = collection
        request.fieldName = fieldName
        request.wait = wait
        let response = try await call { try await points.deleteFieldIndex(request) }
        return UpdateResult(response.result)
    }

    // MARK: - Selector helpers

    static func payloadSelector(_ enable: Bool) -> Qdrant_WithPayloadSelector {
        var s = Qdrant_WithPayloadSelector()
        s.selectorOptions = .enable(enable)
        return s
    }

    static func vectorsSelector(_ enable: Bool) -> Qdrant_WithVectorsSelector {
        var s = Qdrant_WithVectorsSelector()
        s.selectorOptions = .enable(enable)
        return s
    }
}

// MARK: - OrderBy

/// Order results by a payload field. Mirrors Python `models.OrderBy`.
public struct OrderBy: Sendable {
    public enum Direction: Sendable { case asc, desc }
    public var key: String
    public var direction: Direction?

    public init(key: String, direction: Direction? = nil) {
        self.key = key
        self.direction = direction
    }

    var proto: Qdrant_OrderBy {
        var o = Qdrant_OrderBy()
        o.key = key
        if let direction {
            o.direction = direction == .asc ? .asc : .desc
        }
        return o
    }
}
