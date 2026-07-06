import Testing
import Foundation
@testable import EchoMind

@Suite struct VectorPackingTests {
    @Test func roundTripIsExact() throws {
        let vector: [Float] = [1.0, -2.5, 0.0, 3.14159, 42.0]
        let data = VectorPacking.pack(vector)
        let restored = try VectorPacking.unpack(data, expectedDimension: vector.count)
        #expect(restored == vector)
    }

    @Test func littleEndianByteLayout() {
        // Float 1.0 = 0x3F800000 -> little-endian bytes 00 00 80 3F.
        let data = VectorPacking.pack([1.0])
        #expect([UInt8](data) == [0x00, 0x00, 0x80, 0x3F])
    }

    @Test func unpackRejectsWrongByteCount() {
        let data = VectorPacking.pack([1.0, 2.0])   // 8 bytes
        #expect(throws: VectorPackingError.dimensionMismatch) {
            _ = try VectorPacking.unpack(data, expectedDimension: 3)   // expects 12
        }
    }

    @Test func packedSizeIsFourBytesPerElement() {
        #expect(VectorPacking.pack([1, 2, 3, 4]).count == 16)
    }
}
