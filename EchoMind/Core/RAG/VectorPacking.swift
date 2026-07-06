import Foundation

nonisolated enum VectorPackingError: Error, Equatable {
    case dimensionMismatch
}

/// `[Float]` <-> `Data` as explicit little-endian bytes (§6.2). Stored inline in
/// KnowledgeChunk.embedding; unpacked into a contiguous buffer for vDSP scoring.
nonisolated enum VectorPacking {
    static func pack(_ vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * 4)
        for value in vector {
            let bits = value.bitPattern.littleEndian
            data.append(UInt8(bits & 0xFF))
            data.append(UInt8((bits >> 8) & 0xFF))
            data.append(UInt8((bits >> 16) & 0xFF))
            data.append(UInt8((bits >> 24) & 0xFF))
        }
        return data
    }

    static func unpack(_ data: Data, expectedDimension: Int) throws -> [Float] {
        guard data.count == expectedDimension * 4 else { throw VectorPackingError.dimensionMismatch }
        let bytes = [UInt8](data)
        var result = [Float]()
        result.reserveCapacity(expectedDimension)
        for i in 0..<expectedDimension {
            let o = i * 4
            let bits = UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8)
                | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24)
            result.append(Float(bitPattern: UInt32(littleEndian: bits)))
        }
        return result
    }
}
