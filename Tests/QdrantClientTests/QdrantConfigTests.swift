import XCTest
@testable import QdrantClient

/// Config-model completeness — proto/JSON encoding of the full config surface.
final class QdrantConfigModelTests: XCTestCase {
    func testVectorParamsFullProto() {
        let p = VectorParams(
            size: 128, distance: .dot, onDisk: true, datatype: .float16,
            hnswConfig: .init(m: 32, efConstruct: 200, fullScanThreshold: 1000,
                              maxIndexingThreads: 4, onDisk: true, payloadM: 16, inlineStorage: true),
            quantizationConfig: .scalar(.init(type: .int8, quantile: 0.99, alwaysRam: true)),
            multivectorComparator: .maxSim)
        let proto = p.proto
        XCTAssertEqual(proto.size, 128)
        XCTAssertEqual(proto.distance, .dot)
        XCTAssertTrue(proto.onDisk)
        XCTAssertEqual(proto.datatype, .float16)
        XCTAssertEqual(proto.hnswConfig.m, 32)
        XCTAssertEqual(proto.hnswConfig.payloadM, 16)
        XCTAssertTrue(proto.hnswConfig.inlineStorage)
        XCTAssertEqual(proto.quantizationConfig.scalar.type, .int8)
        XCTAssertEqual(proto.quantizationConfig.scalar.quantile, 0.99, accuracy: 1e-6)
        XCTAssertEqual(proto.multivectorConfig.comparator, .maxSim)
    }

    func testOptimizersConfigFullProto() {
        let o = OptimizersConfig(deletedThreshold: 0.2, vacuumMinVectorNumber: 1000,
                                 defaultSegmentNumber: 4, maxSegmentSize: 200_000,
                                 memmapThreshold: 50_000, indexingThreshold: 20_000,
                                 flushIntervalSec: 5, maxOptimizationThreads: 2)
        let proto = o.proto
        XCTAssertEqual(proto.deletedThreshold, 0.2, accuracy: 1e-9)
        XCTAssertEqual(proto.maxSegmentSize, 200_000)
        XCTAssertEqual(proto.maxOptimizationThreads.value, 2)
    }

    func testQuantizationVariantsProto() {
        if case .product(let pq) = QuantizationConfig.product(.init(compression: .x16, alwaysRam: true)).proto.quantization {
            XCTAssertEqual(pq.compression, .x16)
            XCTAssertTrue(pq.alwaysRam)
        } else { XCTFail("expected product") }

        if case .binary(let bq) = QuantizationConfig.binary(.init(alwaysRam: false, encoding: .twoBits)).proto.quantization {
            XCTAssertEqual(bq.encoding, .twoBits)
        } else { XCTFail("expected binary") }
    }

    func testSparseDatatypeAndSearchQuantizationProto() {
        let sp = SparseVectorParams(onDisk: true, fullScanThreshold: 100, datatype: .uint8, modifier: .idf)
        XCTAssertEqual(sp.proto.index.datatype, .uint8)
        XCTAssertEqual(sp.proto.modifier, .idf)

        let params = SearchParams(hnswEf: 256, quantization: .init(ignore: false, rescore: true, oversampling: 2.0))
        XCTAssertEqual(params.proto.hnswEf, 256)
        XCTAssertTrue(params.proto.quantization.rescore)
        XCTAssertEqual(params.proto.quantization.oversampling, 2.0, accuracy: 1e-9)
    }

    func testRESTJSONEncodesQuantization() {
        let p = VectorParams(size: 4, distance: .cosine,
                             quantizationConfig: .scalar(.init(quantile: 0.95)))
        let json = p.json
        XCTAssertEqual(json["quantization_config"]?["scalar"]?["type"]?.stringValue, "int8")
        XCTAssertEqual(json["quantization_config"]?["scalar"]?["quantile"]?.doubleValue ?? 0, 0.95, accuracy: 1e-6)
    }
}
