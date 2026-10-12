import Foundation

/// FNV-1a 64비트. tools/export_model.py의 fnv1a와 같아야 한다.
enum FNV {
    static let offset: UInt64 = 0xCBF2_9CE4_8422_2325
    static let prime: UInt64 = 0x100000001B3

    @inline(__always) static func feed(_ h: inout UInt64, _ ch: Character) {
        for s in ch.unicodeScalars {
            for b in s.utf8 {
                h = (h ^ UInt64(b)) &* prime
            }
        }
    }

    static func hash(_ chars: ArraySlice<Character>) -> UInt64 {
        var h = offset
        for ch in chars { feed(&h, ch) }
        return h
    }

    /// fnv(ctx + "\0" + ch)
    static func hash(_ chars: ArraySlice<Character>, then ch: Character) -> UInt64 {
        var h = offset
        for c in chars { feed(&h, c) }
        h = (h ^ 0) &* prime
        feed(&h, ch)
        return h
    }

    static func hash(_ s: String) -> UInt64 {
        var h = offset
        for b in s.utf8 { h = (h ^ UInt64(b)) &* prime }
        return h
    }
}

/// 정렬된 해시 키 배열 + 값 배열. 이진 탐색으로 찾는다. 딕셔너리보다 메모리가 훨씬 작다.
struct SortedTable<Value> {
    let keys: [UInt64]
    let values: [Value]

    init(keys: [UInt64], values: [Value]) {
        precondition(keys.count == values.count)
        self.keys = keys
        self.values = values
    }

    @inline(__always) func index(of key: UInt64) -> Int? {
        var lo = 0, hi = keys.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            let k = keys[mid]
            if k < key { lo = mid + 1 } else if k > key { hi = mid } else { return mid }
        }
        return nil
    }

    @inline(__always) subscript(key: UInt64) -> Value? {
        guard let i = index(of: key) else { return nil }
        return values[i]
    }
}

/// 바이너리 모델 파일을 순서대로 읽는다.
struct BinaryReader {
    let data: Data
    var offset: Int = 0

    init(_ data: Data) { self.data = data }

    mutating func align8() {
        let rem = offset % 8
        if rem != 0 { offset += 8 - rem }
    }

    mutating func bytes(_ n: Int) throws -> Data {
        guard offset + n <= data.count else { throw ModelError.malformed("truncated at \(offset)") }
        let d = data.subdata(in: offset..<(offset + n))
        offset += n
        return d
    }

    mutating func u32() throws -> UInt32 {
        let d = try bytes(4)
        return d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    mutating func f64() throws -> Double {
        let d = try bytes(8)
        return Double(bitPattern: d.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian)
    }

    /// 고정 크기 원소 배열을 복사해 온다. 정렬(alignment)과 무관하게 동작한다.
    mutating func array<T>(_ type: T.Type, count: Int) throws -> [T] {
        let size = MemoryLayout<T>.stride * count
        guard offset + size <= data.count else { throw ModelError.malformed("truncated array at \(offset)") }
        let start = offset
        let out = [T](unsafeUninitializedCapacity: count) { buf, initialized in
            if count > 0 {
                data.copyBytes(to: UnsafeMutableRawBufferPointer(buf), from: start..<(start + size))
            }
            initialized = count
        }
        offset += size
        return out
    }
}
