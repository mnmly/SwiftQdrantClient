import Foundation
import QdrantProtos

/// Query / search / recommend / discover / facet APIs.
/// Mirrors the search-related methods of the Python client.
extension QdrantClient {
    // MARK: - Universal query

    /// The universal query entry point. Covers nearest/recommend/discover/context/
    /// order-by/fusion/sample queries, named vectors (`using`), hybrid `prefetch`,
    /// filtering, and paging.
    public func query(
        collection: String,
        query: Query? = nil,
        using: String? = nil,
        prefetch: [Prefetch] = [],
        filter: Filter? = nil,
        params: SearchParams? = nil,
        scoreThreshold: Float? = nil,
        limit: UInt64 = 10,
        offset: UInt64 = 0,
        withPayload: WithPayload = true,
        withVectors: WithVectors = false
    ) async throws -> [ScoredPoint] {
        let request = buildQueryRequest(
            collection: collection, query: query, using: using, prefetch: prefetch,
            filter: filter, params: params, scoreThreshold: scoreThreshold,
            limit: limit, offset: offset, withPayload: withPayload, withVectors: withVectors)
        let response = try await call { try await points.query(request) }
        return response.result.map(ScoredPoint.init)
    }

    /// Run several queries in one round-trip. Returns one result list per query.
    public func queryBatch(
        collection: String,
        queries: [QueryRequest]
    ) async throws -> [[ScoredPoint]] {
        var request = Qdrant_QueryBatchPoints()
        request.collectionName = collection
        request.queryPoints = queries.map { $0.buildProto(collection: collection) }
        let response = try await call { try await points.queryBatch(request) }
        return response.result.map { $0.result.map(ScoredPoint.init) }
    }

    /// Query and group results by a payload field.
    public func queryGroups(
        collection: String,
        groupBy: String,
        query: Query? = nil,
        using: String? = nil,
        prefetch: [Prefetch] = [],
        filter: Filter? = nil,
        params: SearchParams? = nil,
        scoreThreshold: Float? = nil,
        limit: UInt64 = 10,
        groupSize: UInt64 = 3,
        withPayload: WithPayload = true,
        withVectors: WithVectors = false
    ) async throws -> [PointGroup] {
        var request = Qdrant_QueryPointGroups()
        request.collectionName = collection
        request.groupBy = groupBy
        request.limit = limit
        request.groupSize = groupSize
        request.withPayload = Self.payloadSelector(withPayload)
        request.withVectors = Self.vectorsSelector(withVectors)
        request.prefetch = prefetch.map(\.proto)
        if let query { request.query = query.proto }
        if let using { request.using = using }
        if let filter { request.filter = filter.proto }
        if let params { request.params = params.proto }
        if let scoreThreshold { request.scoreThreshold = scoreThreshold }
        let response = try await call { try await points.queryGroups(request) }
        return response.result.groups.map(PointGroup.init)
    }

    // MARK: - Convenience: recommend / discover

    /// Recommend points from positive/negative examples (built on `query`).
    public func recommend(
        collection: String,
        positive: [VectorInput] = [],
        negative: [VectorInput] = [],
        strategy: RecommendStrategy? = nil,
        using: String? = nil,
        filter: Filter? = nil,
        limit: UInt64 = 10,
        withPayload: WithPayload = true,
        withVectors: WithVectors = false
    ) async throws -> [ScoredPoint] {
        try await query(
            collection: collection,
            query: .recommend(.init(positive: positive, negative: negative, strategy: strategy)),
            using: using, filter: filter, limit: limit,
            withPayload: withPayload, withVectors: withVectors)
    }

    /// Discover points steering toward `target` using context pairs (built on `query`).
    public func discover(
        collection: String,
        target: VectorInput,
        context: [ContextPair] = [],
        using: String? = nil,
        filter: Filter? = nil,
        limit: UInt64 = 10,
        withPayload: WithPayload = true,
        withVectors: WithVectors = false
    ) async throws -> [ScoredPoint] {
        try await query(
            collection: collection,
            query: .discover(target: target, context: context),
            using: using, filter: filter, limit: limit,
            withPayload: withPayload, withVectors: withVectors)
    }

    // MARK: - Facets

    /// Count distinct values of a payload field.
    public func facet(
        collection: String,
        key: String,
        filter: Filter? = nil,
        limit: UInt64? = nil,
        exact: Bool = false
    ) async throws -> [FacetHit] {
        var request = Qdrant_FacetCounts()
        request.collectionName = collection
        request.key = key
        request.exact = exact
        if let filter { request.filter = filter.proto }
        if let limit { request.limit = limit }
        let response = try await call { try await points.facet(request) }
        return response.hits.map(FacetHit.init)
    }

    // MARK: - Distance matrix

    /// Sampled pairwise distance matrix, as scored pairs.
    public func searchMatrixPairs(
        collection: String,
        filter: Filter? = nil,
        sample: UInt64 = 10,
        limit: UInt64 = 3,
        using: String? = nil
    ) async throws -> [SearchMatrixPair] {
        let request = buildMatrixRequest(collection: collection, filter: filter,
                                         sample: sample, limit: limit, using: using)
        let response = try await call { try await points.searchMatrixPairs(request) }
        return response.result.pairs.map(SearchMatrixPair.init)
    }

    /// Sampled pairwise distance matrix, in offset-encoded form.
    public func searchMatrixOffsets(
        collection: String,
        filter: Filter? = nil,
        sample: UInt64 = 10,
        limit: UInt64 = 3,
        using: String? = nil
    ) async throws -> SearchMatrixOffsets {
        let request = buildMatrixRequest(collection: collection, filter: filter,
                                         sample: sample, limit: limit, using: using)
        let response = try await call { try await points.searchMatrixOffsets(request) }
        return SearchMatrixOffsets(response.result)
    }

    // MARK: - Vector updates

    /// Update (replace) the vectors of existing points.
    @discardableResult
    public func updateVectors(
        collection: String,
        points pts: [(id: PointID, vectors: PointVectors)],
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_UpdatePointVectors()
        request.collectionName = collection
        request.wait = wait
        request.points = pts.map { pair in
            var pv = Qdrant_PointVectors()
            pv.id = pair.id.proto
            pv.vectors = pair.vectors.proto
            return pv
        }
        let response = try await call { try await points.updateVectors(request) }
        return UpdateResult(response.result)
    }

    /// Delete named vectors from the selected points.
    @discardableResult
    public func deleteVectors(
        collection: String,
        vectorNames: [String],
        selector: PointsSelector,
        wait: Bool = true
    ) async throws -> UpdateResult {
        var request = Qdrant_DeletePointVectors()
        request.collectionName = collection
        request.wait = wait
        request.pointsSelector = selector.proto
        var vs = Qdrant_VectorsSelector()
        vs.names = vectorNames
        request.vectors = vs
        let response = try await call { try await points.deleteVectors(request) }
        return UpdateResult(response.result)
    }

    // MARK: - Request builders

    private func buildQueryRequest(
        collection: String, query: Query?, using: String?, prefetch: [Prefetch],
        filter: Filter?, params: SearchParams?, scoreThreshold: Float?,
        limit: UInt64, offset: UInt64, withPayload: WithPayload, withVectors: WithVectors
    ) -> Qdrant_QueryPoints {
        var request = Qdrant_QueryPoints()
        request.collectionName = collection
        request.limit = limit
        request.offset = offset
        request.withPayload = Self.payloadSelector(withPayload)
        request.withVectors = Self.vectorsSelector(withVectors)
        request.prefetch = prefetch.map(\.proto)
        if let query { request.query = query.proto }
        if let using { request.using = using }
        if let filter { request.filter = filter.proto }
        if let params { request.params = params.proto }
        if let scoreThreshold { request.scoreThreshold = scoreThreshold }
        return request
    }

    private func buildMatrixRequest(
        collection: String, filter: Filter?, sample: UInt64, limit: UInt64, using: String?
    ) -> Qdrant_SearchMatrixPoints {
        var request = Qdrant_SearchMatrixPoints()
        request.collectionName = collection
        request.sample = sample
        request.limit = limit
        if let filter { request.filter = filter.proto }
        if let using { request.using = using }
        return request
    }
}

// MARK: - QueryRequest (for batch)

/// One entry in a ``QdrantClient/queryBatch(collection:queries:)`` call.
public struct QueryRequest: Sendable {
    public var query: Query?
    public var using: String?
    public var prefetch: [Prefetch]
    public var filter: Filter?
    public var params: SearchParams?
    public var scoreThreshold: Float?
    public var limit: UInt64
    public var offset: UInt64
    public var withPayload: WithPayload
    public var withVectors: WithVectors

    public init(
        query: Query? = nil,
        using: String? = nil,
        prefetch: [Prefetch] = [],
        filter: Filter? = nil,
        params: SearchParams? = nil,
        scoreThreshold: Float? = nil,
        limit: UInt64 = 10,
        offset: UInt64 = 0,
        withPayload: WithPayload = true,
        withVectors: WithVectors = false
    ) {
        self.query = query
        self.using = using
        self.prefetch = prefetch
        self.filter = filter
        self.params = params
        self.scoreThreshold = scoreThreshold
        self.limit = limit
        self.offset = offset
        self.withPayload = withPayload
        self.withVectors = withVectors
    }

    func buildProto(collection: String) -> Qdrant_QueryPoints {
        var request = Qdrant_QueryPoints()
        request.collectionName = collection
        request.limit = limit
        request.offset = offset
        request.withPayload = QdrantClient.payloadSelector(withPayload)
        request.withVectors = QdrantClient.vectorsSelector(withVectors)
        request.prefetch = prefetch.map(\.proto)
        if let query { request.query = query.proto }
        if let using { request.using = using }
        if let filter { request.filter = filter.proto }
        if let params { request.params = params.proto }
        if let scoreThreshold { request.scoreThreshold = scoreThreshold }
        return request
    }
}
