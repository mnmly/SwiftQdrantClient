import Foundation

/// An in-process, in-memory Qdrant implementation — the Swift counterpart of the
/// Python client's "local mode". It performs brute-force vector search with full
/// filter evaluation and payload storage, requiring no server.
///
/// Supported queries: nearest (dense / sparse / multi / by-id), recommend
/// (average-vector & best-score), and order-by. Discovery / context / fusion /
/// prefetch are server-only and throw ``QdrantError/unsupported(_:)``.
public actor QdrantLocalClient: QdrantClientProtocol {
    /// The default (unnamed) vector slot, matching Qdrant's `""` convention.
    static let defaultVector = ""

    struct StoredPoint {
        var id: PointID
        var vectors: [String: VectorData]
        var payload: Payload
    }

    struct LocalCollection {
        var vectorParams: [String: (size: UInt64, distance: Distance)]
        var sparseVectors: Set<String>
        var points: [PointID: StoredPoint] = [:]
        var nextVersion: UInt64 = 0
    }

    private var collections: [String: LocalCollection] = [:]
    /// Alias name → collection name.
    private var aliases: [String: String] = [:]
    /// Indexed payload fields per collection (tracked for parity; search is brute-force regardless).
    private var payloadIndexes: [String: Set<String>] = [:]

    public init() {}

    /// Resolve a collection name through any alias.
    private func resolveName(_ name: String) -> String { aliases[name] ?? name }

    // MARK: - Collections

    @discardableResult
    public func createCollection(
        name: String,
        vectors: VectorsConfiguration,
        sparseVectors: [String: SparseVectorParams]? = nil,
        quantizationConfig: QuantizationConfig? = nil,
        hnswConfig: HnswConfig? = nil,
        optimizersConfig: OptimizersConfig? = nil,
        walConfig: WalConfig? = nil,
        onDiskPayload: Bool? = nil,
        shardNumber: UInt32? = nil,
        shardingMethod: ShardingMethod? = nil,
        replicationFactor: UInt32? = nil,
        writeConsistencyFactor: UInt32? = nil
    ) async throws -> Bool {
        var params: [String: (size: UInt64, distance: Distance)] = [:]
        switch vectors {
        case .single(let p):
            params[Self.defaultVector] = (p.size, p.distance)
        case .named(let map):
            for (k, v) in map { params[k] = (v.size, v.distance) }
        }
        collections[name] = LocalCollection(
            vectorParams: params,
            sparseVectors: Set(sparseVectors?.keys ?? [:].keys))
        return true
    }

    public func collectionExists(_ name: String) async throws -> Bool {
        collections[name] != nil
    }

    public func listCollections() async throws -> [String] {
        Array(collections.keys)
    }

    @discardableResult
    public func deleteCollection(_ name: String) async throws -> Bool {
        collections.removeValue(forKey: name) != nil
    }

    public func getCollection(_ name: String) async throws -> CollectionInfo {
        guard let c = collections[name] else { throw QdrantError.collectionNotFound(name) }
        return CollectionInfo(pointsCount: UInt64(c.points.count),
                              indexedVectorsCount: UInt64(c.points.count))
    }

    // MARK: - Write

    @discardableResult
    public func upsert(collection: String, points: [PointStruct], wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            for p in points {
                let vectors: [String: VectorData]
                switch p.vectors {
                case .single(let data): vectors = [Self.defaultVector: data]
                case .named(let map): vectors = map
                }
                c.points[p.id] = StoredPoint(id: p.id, vectors: vectors, payload: p.payload)
            }
            c.nextVersion += 1
        }
    }

    @discardableResult
    public func delete(collection: String, selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            switch selector {
            case .ids(let ids):
                for id in ids { c.points.removeValue(forKey: id) }
            case .filter(let filter):
                for (id, p) in c.points where FilterEval.matches(filter, id: id, payload: p.payload, vectorNames: Set(p.vectors.keys)) {
                    c.points.removeValue(forKey: id)
                }
            }
            c.nextVersion += 1
        }
    }

    @discardableResult
    public func setPayload(
        collection: String, payload: Payload, selector: PointsSelector,
        key: String? = nil, wait: Bool = true
    ) async throws -> UpdateResult {
        try mutate(collection) { c in
            for id in resolveIDs(selector, in: c) {
                guard var p = c.points[id] else { continue }
                for (k, v) in payload { p.payload[k] = v }
                c.points[id] = p
            }
            c.nextVersion += 1
        }
    }

    @discardableResult
    public func overwritePayload(collection: String, payload: Payload, selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            for id in resolveIDs(selector, in: c) {
                guard var p = c.points[id] else { continue }
                p.payload = payload
                c.points[id] = p
            }
            c.nextVersion += 1
        }
    }

    @discardableResult
    public func deletePayload(collection: String, keys: [String], selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            for id in resolveIDs(selector, in: c) {
                guard var p = c.points[id] else { continue }
                for k in keys { p.payload.removeValue(forKey: k) }
                c.points[id] = p
            }
            c.nextVersion += 1
        }
    }

    @discardableResult
    public func clearPayload(collection: String, selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            for id in resolveIDs(selector, in: c) {
                guard var p = c.points[id] else { continue }
                p.payload = [:]
                c.points[id] = p
            }
            c.nextVersion += 1
        }
    }

    // MARK: - Read

    public func retrieve(
        collection: String, ids: [PointID], withPayload: WithPayload = true, withVectors: WithVectors = false
    ) async throws -> [RetrievedPoint] {
        let c = try get(collection)
        return ids.compactMap { c.points[$0] }.map { stored in
            makeRetrieved(stored, withPayload: withPayload, withVectors: withVectors)
        }
    }

    public func scroll(
        collection: String, filter: Filter? = nil, limit: UInt32 = 10, offset: PointID? = nil,
        withPayload: WithPayload = true, withVectors: WithVectors = false, orderBy: OrderBy? = nil
    ) async throws -> (points: [RetrievedPoint], nextOffset: PointID?) {
        let c = try get(collection)
        var matched = c.points.values.filter {
            FilterEval.matches(filter, id: $0.id, payload: $0.payload, vectorNames: Set($0.vectors.keys))
        }
        if let orderBy {
            matched.sort { a, b in
                let av = PayloadPath.resolve(a.payload, orderBy.key).first?.asDouble ?? 0
                let bv = PayloadPath.resolve(b.payload, orderBy.key).first?.asDouble ?? 0
                return orderBy.direction == .desc ? av > bv : av < bv
            }
        } else {
            matched.sort { $0.id < $1.id }
        }
        if let offset {
            if let idx = matched.firstIndex(where: { $0.id == offset }) {
                matched = Array(matched[idx...])
            } else {
                matched = matched.filter { $0.id >= offset }
            }
        }
        let page = Array(matched.prefix(Int(limit)))
        let next = matched.count > page.count ? matched[Int(limit)].id : nil
        return (page.map { makeRetrieved($0, withPayload: withPayload, withVectors: withVectors) }, next)
    }

    public func count(collection: String, filter: Filter? = nil, exact: Bool = true) async throws -> UInt64 {
        let c = try get(collection)
        return UInt64(c.points.values.filter {
            FilterEval.matches(filter, id: $0.id, payload: $0.payload, vectorNames: Set($0.vectors.keys))
        }.count)
    }

    // MARK: - Query

    public func query(
        collection: String, query: Query? = nil, using: String? = nil, prefetch: [Prefetch] = [],
        filter: Filter? = nil, params: SearchParams? = nil, scoreThreshold: Float? = nil,
        limit: UInt64 = 10, offset: UInt64 = 0, withPayload: WithPayload = true, withVectors: WithVectors = false
    ) async throws -> [ScoredPoint] {
        guard prefetch.isEmpty else {
            throw QdrantError.unsupported("prefetch (hybrid) queries are not supported in local mode")
        }
        let c = try get(collection)
        let vectorName = using ?? Self.defaultVector
        let metric = c.vectorParams[vectorName]?.distance ?? .cosine

        // Candidate points after filtering.
        let candidates = c.points.values.filter {
            FilterEval.matches(filter, id: $0.id, payload: $0.payload, vectorNames: Set($0.vectors.keys))
        }

        guard let query else {
            // No query → return filtered points (scroll-like) as zero-score hits.
            let page = candidates.sorted { $0.id < $1.id }.dropFirst(Int(offset)).prefix(Int(limit))
            return page.map { makeScored($0, score: 0, withPayload: withPayload, withVectors: withVectors) }
        }

        var scored: [(StoredPoint, Float)]
        var higher = DistanceMath.higherIsBetter(metric)
        var preSorted = false
        switch query {
        case .nearest(let input):
            let target = try resolveVectorInput(input, name: vectorName, in: c)
            scored = score(candidates, against: target, name: vectorName, metric: metric)
        case .recommend(let input):
            scored = try recommend(input, candidates: candidates, name: vectorName, metric: metric, in: c)
            higher = true
        case .orderBy(let orderBy):
            let sorted = candidates.sorted { a, b in
                let av = PayloadPath.resolve(a.payload, orderBy.key).first?.asDouble ?? 0
                let bv = PayloadPath.resolve(b.payload, orderBy.key).first?.asDouble ?? 0
                return orderBy.direction == .desc ? av > bv : av < bv
            }
            scored = sorted.map { ($0, 0) }
            preSorted = true
        case .nearestWithMmr(let input, _):
            // MMR re-ranking is not modelled locally; fall back to plain nearest.
            let target = try resolveVectorInput(input, name: vectorName, in: c)
            scored = score(candidates, against: target, name: vectorName, metric: metric)
        case .discover(let target, let context):
            scored = try discover(target: target, context: context, candidates: candidates, name: vectorName, metric: metric, in: c)
            higher = true
        case .context(let pairs):
            scored = try contextScore(pairs: pairs, candidates: candidates, name: vectorName, metric: metric, in: c)
            higher = true
        case .sampleRandom:
            scored = candidates.shuffled().map { ($0, 0) }
            preSorted = true
        case .fusion:
            throw QdrantError.unsupported("fusion queries require prefetch, not supported in local mode")
        }

        // Rank, threshold, page.
        if !preSorted { scored.sort { higher ? $0.1 > $1.1 : $0.1 < $1.1 } }
        if let t = scoreThreshold {
            scored = scored.filter { higher ? $0.1 >= t : $0.1 <= t }
        }
        let paged = scored.dropFirst(Int(offset)).prefix(Int(limit))
        return paged.map { makeScored($0.0, score: $0.1, withPayload: withPayload, withVectors: withVectors) }
    }

    // MARK: - Discovery scoring (local approximation of Qdrant semantics)

    private func contextScore(
        pairs: [ContextPair], candidates: [StoredPoint], name: String, metric: Distance, in c: LocalCollection
    ) throws -> [(StoredPoint, Float)] {
        let resolved = try pairs.map {
            (pos: try resolveDense($0.positive, name: name, in: c), neg: try resolveDense($0.negative, name: name, in: c))
        }
        return candidates.compactMap { point in
            guard case .dense(let pv)? = point.vectors[name] else { return nil }
            // Each pair contributes 0 when correctly on the positive side, else a negative penalty.
            var total: Float = 0
            for pair in resolved {
                let sp = DistanceMath.score(pv, pair.pos, metric)
                let sn = DistanceMath.score(pv, pair.neg, metric)
                total += min(sp - sn, 0)
            }
            return (point, total)
        }
    }

    private func discover(
        target: VectorInput, context: [ContextPair], candidates: [StoredPoint],
        name: String, metric: Distance, in c: LocalCollection
    ) throws -> [(StoredPoint, Float)] {
        let ctx = try contextScore(pairs: context, candidates: candidates, name: name, metric: metric, in: c)
        let targetVec = try resolveDense(target, name: name, in: c)
        // Primary: context score (0 best); secondary: similarity to target.
        return ctx.map { point, ctxScore in
            guard case .dense(let pv)? = point.vectors[name] else { return (point, ctxScore) }
            let targetSim = DistanceMath.score(pv, targetVec, metric)
            // When fully in-context (ctxScore == 0), rank by target similarity; else penalise.
            let combined = ctxScore < 0 ? ctxScore : targetSim
            return (point, combined)
        }
    }

    public func close() async throws { collections.removeAll() }

    // MARK: - Scoring helpers

    private func score(
        _ candidates: some Collection<StoredPoint>, against target: VectorData,
        name: String, metric: Distance
    ) -> [(StoredPoint, Float)] {
        candidates.compactMap { point in
            guard let v = point.vectors[name] else { return nil }
            guard let s = scorePair(target, v, metric) else { return nil }
            return (point, s)
        }
    }

    private func scorePair(_ a: VectorData, _ b: VectorData, _ metric: Distance) -> Float? {
        switch (a, b) {
        case (.dense(let x), .dense(let y)):
            return DistanceMath.score(x, y, metric)
        case (.sparse(let xi, let xv), .sparse(let yi, let yv)):
            return DistanceMath.sparseDot(xi, xv, yi, yv) // sparse uses dot similarity
        case (.multiDense(let xs), .multiDense(let ys)):
            // Max-sim (sum of best matches), the common multi-vector scoring.
            var total: Float = 0
            for x in xs {
                var best = -Float.greatestFiniteMagnitude
                for y in ys { best = max(best, DistanceMath.score(x, y, metric)) }
                total += best
            }
            return total
        default:
            return nil
        }
    }

    private func recommend(
        _ input: RecommendInput, candidates: [StoredPoint],
        name: String, metric: Distance, in c: LocalCollection
    ) throws -> [(StoredPoint, Float)] {
        let positives = try input.positive.map { try resolveDense($0, name: name, in: c) }
        let negatives = try input.negative.map { try resolveDense($0, name: name, in: c) }
        let excluded = Set(input.positive.compactMap(idOf) + input.negative.compactMap(idOf))
        let usable = candidates.filter { !excluded.contains($0.id) }

        switch input.strategy ?? .averageVector {
        case .averageVector:
            guard let dim = positives.first?.count ?? negatives.first?.count else {
                throw QdrantError.unsupported("recommend requires at least one example")
            }
            var avg = [Float](repeating: 0, count: dim)
            for v in positives { for i in 0..<min(dim, v.count) { avg[i] += v[i] } }
            for v in negatives { for i in 0..<min(dim, v.count) { avg[i] -= v[i] } }
            let denom = Float(max(positives.count, 1))
            avg = avg.map { $0 / denom }
            return score(usable, against: .dense(avg), name: name, metric: metric)
        case .bestScore, .sumScores:
            // best_score: score = max(sim to any positive) - max(sim to any negative)
            return usable.compactMap { point in
                guard case .dense(let pv)? = point.vectors[name] else { return nil }
                let bestPos = positives.map { DistanceMath.score($0, pv, metric) }.max() ?? -Float.greatestFiniteMagnitude
                let bestNeg = negatives.map { DistanceMath.score($0, pv, metric) }.max() ?? -Float.greatestFiniteMagnitude
                let s = input.strategy == .sumScores
                    ? positives.map { DistanceMath.score($0, pv, metric) }.reduce(0, +)
                        - negatives.map { DistanceMath.score($0, pv, metric) }.reduce(0, +)
                    : bestPos - (negatives.isEmpty ? 0 : bestNeg)
                return (point, s)
            }
        }
    }

    private func idOf(_ input: VectorInput) -> PointID? {
        if case .id(let id) = input { return id } else { return nil }
    }

    private func resolveVectorInput(_ input: VectorInput, name: String, in c: LocalCollection) throws -> VectorData {
        switch input {
        case .dense(let d): return .dense(d)
        case .sparse(let i, let v): return .sparse(indices: i, values: v)
        case .multiDense(let m): return .multiDense(m)
        case .id(let id):
            guard let v = c.points[id]?.vectors[name] else {
                throw QdrantError.unsupported("point \(id) has no vector named \"\(name)\"")
            }
            return v
        }
    }

    private func resolveDense(_ input: VectorInput, name: String, in c: LocalCollection) throws -> [Float] {
        switch try resolveVectorInput(input, name: name, in: c) {
        case .dense(let d): return d
        default: throw QdrantError.unsupported("recommend supports dense vectors in local mode")
        }
    }

    // MARK: - Plumbing

    private func get(_ name: String) throws -> LocalCollection {
        let key = resolveName(name)
        guard let c = collections[key] else { throw QdrantError.collectionNotFound(name) }
        return c
    }

    private func mutate(_ name: String, _ body: (inout LocalCollection) -> Void) throws -> UpdateResult {
        let key = resolveName(name)
        guard var c = collections[key] else { throw QdrantError.collectionNotFound(name) }
        body(&c)
        collections[key] = c
        return UpdateResult(operationId: c.nextVersion, status: .completed)
    }

    private func resolveIDs(_ selector: PointsSelector, in c: LocalCollection) -> [PointID] {
        switch selector {
        case .ids(let ids): return ids
        case .filter(let filter):
            return c.points.values
                .filter { FilterEval.matches(filter, id: $0.id, payload: $0.payload, vectorNames: Set($0.vectors.keys)) }
                .map(\.id)
        }
    }

    private func makeRetrieved(_ p: StoredPoint, withPayload: WithPayload, withVectors: WithVectors) -> RetrievedPoint {
        let (vector, vectors) = vectorOutput(p, withVectors: withVectors)
        return RetrievedPoint(id: p.id, payload: withPayload.apply(p.payload), vector: vector, vectors: vectors)
    }

    private func makeScored(_ p: StoredPoint, score: Float, withPayload: WithPayload, withVectors: WithVectors) -> ScoredPoint {
        let (vector, vectors) = vectorOutput(p, withVectors: withVectors)
        return ScoredPoint(id: p.id, score: score, version: 0,
                           payload: withPayload.apply(p.payload), vector: vector, vectors: vectors)
    }

    private func vectorOutput(_ p: StoredPoint, withVectors: WithVectors) -> ([Float]?, [String: VectorData]) {
        guard withVectors.isEnabled else { return (nil, [:]) }
        let selected = withVectors.apply(p.vectors)
        if selected.count == 1, let only = selected[Self.defaultVector], case .dense(let d) = only {
            return (d, [:])
        }
        return (nil, selected)
    }

    // MARK: - Parity: payload indexes / vectors / collection config

    @discardableResult
    public func createPayloadIndex(collection: String, fieldName: String, fieldType: FieldType, wait: Bool = true) async throws -> UpdateResult {
        _ = try get(collection) // validate existence
        payloadIndexes[resolveName(collection), default: []].insert(fieldName)
        return UpdateResult(status: .completed)
    }

    @discardableResult
    public func deletePayloadIndex(collection: String, fieldName: String, wait: Bool = true) async throws -> UpdateResult {
        _ = try get(collection)
        payloadIndexes[resolveName(collection)]?.remove(fieldName)
        return UpdateResult(status: .completed)
    }

    @discardableResult
    public func updateVectors(collection: String, points: [(id: PointID, vectors: PointVectors)], wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            for pair in points {
                guard var p = c.points[pair.id] else { continue }
                switch pair.vectors {
                case .single(let data): p.vectors[Self.defaultVector] = data
                case .named(let map): for (k, v) in map { p.vectors[k] = v }
                }
                c.points[pair.id] = p
            }
            c.nextVersion += 1
        }
    }

    @discardableResult
    public func deleteVectors(collection: String, vectorNames: [String], selector: PointsSelector, wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            let ids = resolveIDs(selector, in: c)
            for id in ids {
                guard var p = c.points[id] else { continue }
                for name in vectorNames { p.vectors.removeValue(forKey: name) }
                c.points[id] = p
            }
            c.nextVersion += 1
        }
    }

    @discardableResult
    public func createVectorName(collection: String, vectorName: String, config: VectorNameConfig, wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in c.vectorParams[vectorName] = (config.size, config.distance) }
    }

    @discardableResult
    public func deleteVectorName(collection: String, vectorName: String, wait: Bool = true) async throws -> UpdateResult {
        try mutate(collection) { c in
            c.vectorParams.removeValue(forKey: vectorName)
            for (id, var p) in c.points { p.vectors.removeValue(forKey: vectorName); c.points[id] = p }
        }
    }

    @discardableResult
    public func updateCollection(name: String, optimizersConfig: OptimizersConfig? = nil, hnswConfig: HnswConfig? = nil, quantizationConfig: QuantizationConfig? = nil) async throws -> Bool {
        _ = try get(name)
        return true
    }

    // MARK: - Parity: aliases

    @discardableResult
    public func updateAliases(_ actions: [AliasOperation]) async throws -> Bool {
        for action in actions {
            switch action {
            case .create(let collection, let alias): aliases[alias] = collection
            case .delete(let alias): aliases.removeValue(forKey: alias)
            case .rename(let oldAlias, let newAlias):
                if let target = aliases.removeValue(forKey: oldAlias) { aliases[newAlias] = target }
            }
        }
        return true
    }

    public func listAliases() async throws -> [AliasDescription] {
        aliases.map { AliasDescription(aliasName: $0.key, collectionName: $0.value) }
    }

    public func listCollectionAliases(_ collection: String) async throws -> [AliasDescription] {
        aliases.filter { $0.value == collection }.map { AliasDescription(aliasName: $0.key, collectionName: $0.value) }
    }

    // MARK: - Parity: facet / batched & grouped queries

    public func facet(collection: String, key: String, filter: Filter? = nil, limit: UInt64? = nil, exact: Bool = false) async throws -> [FacetHit] {
        let c = try get(collection)
        var counts: [FacetValue: UInt64] = [:]
        for p in c.points.values where FilterEval.matches(filter, id: p.id, payload: p.payload, vectorNames: Set(p.vectors.keys)) {
            for value in PayloadPath.resolve(p.payload, key) {
                guard let fv = facetValue(value) else { continue }
                counts[fv, default: 0] += 1
            }
        }
        let sorted = counts.sorted { $0.value > $1.value }.map { FacetHit(value: $0.key, count: $0.value) }
        if let limit { return Array(sorted.prefix(Int(limit))) }
        return sorted
    }

    public func queryBatch(collection: String, queries: [QueryRequest]) async throws -> [[ScoredPoint]] {
        var out: [[ScoredPoint]] = []
        for req in queries {
            out.append(try await query(
                collection: collection, query: req.query, using: req.using, prefetch: req.prefetch,
                filter: req.filter, params: req.params, scoreThreshold: req.scoreThreshold,
                limit: req.limit, offset: req.offset, withPayload: req.withPayload, withVectors: req.withVectors))
        }
        return out
    }

    public func queryGroups(
        collection: String, groupBy: String, query: Query? = nil, using: String? = nil, prefetch: [Prefetch] = [],
        filter: Filter? = nil, params: SearchParams? = nil, scoreThreshold: Float? = nil, limit: UInt64 = 10,
        groupSize: UInt64 = 3, withPayload: WithPayload = true, withVectors: WithVectors = false
    ) async throws -> [PointGroup] {
        // Over-fetch then group by the payload key.
        let hits = try await self.query(
            collection: collection, query: query, using: using, prefetch: prefetch, filter: filter,
            params: params, scoreThreshold: scoreThreshold, limit: limit * groupSize * 4, offset: 0,
            withPayload: true, withVectors: withVectors)
        var groups: [GroupId: [ScoredPoint]] = [:]
        var order: [GroupId] = []
        for hit in hits {
            guard let raw = PayloadPath.resolve(hit.payload, groupBy).first, let gid = groupId(raw) else { continue }
            if groups[gid] == nil { order.append(gid) }
            if (groups[gid]?.count ?? 0) < Int(groupSize) { groups[gid, default: []].append(hit) }
        }
        return order.prefix(Int(limit)).map { PointGroup(id: $0, hits: groups[$0] ?? [], lookup: nil) }
    }

    public func info() async throws -> VersionInfo {
        VersionInfo(title: "qdrant - local mode", version: "local", commit: nil)
    }

    // MARK: - Parity: distance matrix (brute force over a sample)

    public func searchMatrixPairs(collection: String, filter: Filter? = nil, sample: UInt64 = 10, limit: UInt64 = 3, using: String? = nil) async throws -> [SearchMatrixPair] {
        let (ids, _, rows) = try matrix(collection: collection, filter: filter, sample: sample, limit: limit, using: using)
        var pairs: [SearchMatrixPair] = []
        for (i, row) in rows.enumerated() {
            for (j, score) in row { pairs.append(SearchMatrixPair(a: ids[i], b: ids[j], score: score)) }
        }
        return pairs
    }

    public func searchMatrixOffsets(collection: String, filter: Filter? = nil, sample: UInt64 = 10, limit: UInt64 = 3, using: String? = nil) async throws -> SearchMatrixOffsets {
        let (ids, _, rows) = try matrix(collection: collection, filter: filter, sample: sample, limit: limit, using: using)
        var offsetsRow: [UInt64] = [], offsetsCol: [UInt64] = [], scores: [Float] = []
        for (i, row) in rows.enumerated() {
            for (j, score) in row {
                offsetsRow.append(UInt64(i)); offsetsCol.append(UInt64(j)); scores.append(score)
            }
        }
        return SearchMatrixOffsets(offsetsRow: offsetsRow, offsetsCol: offsetsCol, scores: scores, ids: ids)
    }

    /// Sample points and compute each row's top-`limit` neighbours.
    private func matrix(collection: String, filter: Filter?, sample: UInt64, limit: UInt64, using: String?)
        throws -> (ids: [PointID], metric: Distance, rows: [[(Int, Float)]]) {
        let c = try get(collection)
        let name = using ?? Self.defaultVector
        let metric = c.vectorParams[name]?.distance ?? .cosine
        let candidates = c.points.values
            .filter { FilterEval.matches(filter, id: $0.id, payload: $0.payload, vectorNames: Set($0.vectors.keys)) }
            .compactMap { p -> (PointID, [Float])? in
                if case .dense(let d)? = p.vectors[name] { return (p.id, d) }
                return nil
            }
            .sorted { $0.0 < $1.0 }
            .prefix(Int(sample))
        let sampled = Array(candidates)
        let ids = sampled.map(\.0)
        let higher = DistanceMath.higherIsBetter(metric)
        let rows: [[(Int, Float)]] = sampled.enumerated().map { i, a in
            let scored = sampled.enumerated().compactMap { j, b -> (Int, Float)? in
                i == j ? nil : (j, DistanceMath.score(a.1, b.1, metric))
            }
            return Array(scored.sorted { higher ? $0.1 > $1.1 : $0.1 < $1.1 }.prefix(Int(limit)))
        }
        return (ids, metric, rows)
    }

    // MARK: helpers

    private func facetValue(_ v: QdrantValue) -> FacetValue? {
        switch v {
        case .string(let s): return .string(s)
        case .int(let i): return .integer(i)
        case .bool(let b): return .bool(b)
        default: return nil
        }
    }

    private func groupId(_ v: QdrantValue) -> GroupId? {
        switch v {
        case .string(let s): return .string(s)
        case .int(let i): return .integer(i)
        default: return nil
        }
    }
}
