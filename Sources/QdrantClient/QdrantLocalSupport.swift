import Foundation

// MARK: - PointID ordering

extension PointID: Comparable {
    /// Integer ids sort before UUID ids; within a kind, natural order.
    public static func < (lhs: PointID, rhs: PointID) -> Bool {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return a < b
        case (.uuid(let a), .uuid(let b)): return a < b
        case (.int, .uuid): return true
        case (.uuid, .int): return false
        }
    }
}

// MARK: - QdrantValue scalar access

extension QdrantValue {
    var asDouble: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }
    var asInt: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        default: return nil
        }
    }
    var asString: String? { if case .string(let s) = self { return s } else { return nil } }
    var asBool: Bool? { if case .bool(let b) = self { return b } else { return nil } }

    /// `true` if this value is "empty" for `is_empty` semantics.
    var isEmptyValue: Bool {
        switch self {
        case .null: return true
        case .list(let xs): return xs.isEmpty
        default: return false
        }
    }
}

// MARK: - Payload path resolution

enum PayloadPath {
    /// Resolve a (possibly dotted) key path to the flattened list of matching
    /// values. Arrays encountered along the path are expanded.
    static func resolve(_ payload: Payload, _ path: String) -> [QdrantValue] {
        var current: [QdrantValue] = [.object(payload)]
        for component in path.split(separator: ".").map(String.init) {
            var next: [QdrantValue] = []
            for value in current {
                switch value {
                case .object(let dict):
                    if let v = dict[component] { next.append(contentsOf: flatten(v)) }
                case .list(let items):
                    for item in items {
                        if case .object(let dict) = item, let v = dict[component] {
                            next.append(contentsOf: flatten(v))
                        }
                    }
                default:
                    break
                }
            }
            current = next
        }
        return current
    }

    /// Expand a top-level array into its elements (one level).
    private static func flatten(_ value: QdrantValue) -> [QdrantValue] {
        if case .list(let items) = value { return items }
        return [value]
    }
}

// MARK: - Distances

enum DistanceMath {
    static func score(_ a: [Float], _ b: [Float], _ metric: Distance) -> Float {
        switch metric {
        case .cosine: return cosine(a, b)
        case .dot: return dot(a, b)
        case .euclid: return euclid(a, b)
        case .manhattan: return manhattan(a, b)
        }
    }

    /// Whether higher scores rank better for this metric.
    static func higherIsBetter(_ metric: Distance) -> Bool {
        switch metric {
        case .cosine, .dot: return true
        case .euclid, .manhattan: return false
        }
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var s: Float = 0
        for i in 0..<n { s += a[i] * b[i] }
        return s
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let d = dot(a, b)
        let na = (dot(a, a)).squareRoot()
        let nb = (dot(b, b)).squareRoot()
        guard na > 0, nb > 0 else { return 0 }
        return d / (na * nb)
    }

    static func euclid(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var s: Float = 0
        for i in 0..<n { let d = a[i] - b[i]; s += d * d }
        return s.squareRoot()
    }

    static func manhattan(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var s: Float = 0
        for i in 0..<n { s += abs(a[i] - b[i]) }
        return s
    }

    /// Sparse dot product over matching indices.
    static func sparseDot(_ aIdx: [UInt32], _ aVal: [Float], _ bIdx: [UInt32], _ bVal: [Float]) -> Float {
        var map: [UInt32: Float] = [:]
        for (i, idx) in aIdx.enumerated() where i < aVal.count { map[idx] = aVal[i] }
        var s: Float = 0
        for (i, idx) in bIdx.enumerated() where i < bVal.count {
            if let v = map[idx] { s += v * bVal[i] }
        }
        return s
    }

    /// Great-circle distance in metres (haversine).
    static func haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

// MARK: - Filter evaluation

enum FilterEval {
    static func matches(_ filter: Filter?, id: PointID, payload: Payload, vectorNames: Set<String>) -> Bool {
        guard let filter else { return true }
        func eval(_ c: Condition) -> Bool {
            condition(c, id: id, payload: payload, vectorNames: vectorNames)
        }
        if !filter.must.isEmpty, !filter.must.allSatisfy(eval) { return false }
        if !filter.mustNot.isEmpty, filter.mustNot.contains(where: eval) { return false }
        if !filter.should.isEmpty, !filter.should.contains(where: eval) { return false }
        if let minShould = filter.minShould {
            let matched = minShould.conditions.filter(eval).count
            if matched < Int(minShould.count) { return false }
        }
        return true
    }

    private static func condition(
        _ c: Condition, id: PointID, payload: Payload, vectorNames: Set<String>
    ) -> Bool {
        switch c {
        case .match(let key, let value):
            return PayloadPath.resolve(payload, key).contains { matchValue(value, $0) }
        case .range(let key, let range):
            return PayloadPath.resolve(payload, key).contains { v in
                guard let d = v.asDouble else { return false }
                if let lt = range.lt, !(d < lt) { return false }
                if let gt = range.gt, !(d > gt) { return false }
                if let gte = range.gte, !(d >= gte) { return false }
                if let lte = range.lte, !(d <= lte) { return false }
                return true
            }
        case .geoRadius(let key, let center, let radius):
            return PayloadPath.resolve(payload, key).contains { v in
                guard let (lat, lon) = geo(v) else { return false }
                return DistanceMath.haversine(lat1: center.lat, lon1: center.lon, lat2: lat, lon2: lon) <= Double(radius)
            }
        case .geoBoundingBox(let key, let topLeft, let bottomRight):
            return PayloadPath.resolve(payload, key).contains { v in
                guard let (lat, lon) = geo(v) else { return false }
                return lat <= topLeft.lat && lat >= bottomRight.lat
                    && lon >= topLeft.lon && lon <= bottomRight.lon
            }
        case .hasID(let ids):
            return ids.contains(id)
        case .hasVector(let name):
            return vectorNames.contains(name)
        case .isEmpty(let key):
            let values = PayloadPath.resolve(payload, key)
            return values.isEmpty || values.allSatisfy(\.isEmptyValue)
        case .isNull(let key):
            let values = PayloadPath.resolve(payload, key)
            return values.isEmpty || values.contains { if case .null = $0 { return true } else { return false } }
        case .nested(let key, let filter):
            let objects = PayloadPath.resolve(payload, key)
            return objects.contains { v in
                guard case .object(let obj) = v else { return false }
                return matches(filter, id: id, payload: obj, vectorNames: vectorNames)
            }
        case .filter(let filter):
            return matches(filter, id: id, payload: payload, vectorNames: vectorNames)
        }
    }

    private static func matchValue(_ match: MatchValue, _ value: QdrantValue) -> Bool {
        switch match {
        case .keyword(let s): return value.asString == s
        case .integer(let i): return value.asInt == i
        case .boolean(let b): return value.asBool == b
        case .text(let t), .textAny(let t):
            guard let s = value.asString?.lowercased() else { return false }
            let needle = t.lowercased()
            return needle.split(separator: " ").contains { s.contains($0) }
        case .phrase(let p):
            return value.asString?.lowercased().contains(p.lowercased()) ?? false
        case .anyKeywords(let set): return value.asString.map(set.contains) ?? false
        case .anyIntegers(let set): return value.asInt.map(set.contains) ?? false
        case .exceptKeywords(let set):
            guard let s = value.asString else { return false }
            return !set.contains(s)
        case .exceptIntegers(let set):
            guard let i = value.asInt else { return false }
            return !set.contains(i)
        }
    }

    private static func geo(_ value: QdrantValue) -> (lat: Double, lon: Double)? {
        guard case .object(let obj) = value,
              let lat = obj["lat"]?.asDouble, let lon = obj["lon"]?.asDouble else { return nil }
        return (lat, lon)
    }
}
