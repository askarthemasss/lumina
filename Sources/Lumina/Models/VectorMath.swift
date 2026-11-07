import Foundation
import Accelerate

enum VectorMath {
    /// Embeddings are normalized before storage. Semantic similarity is then
    /// a dot product, which keeps local brute-force search fast and simple.
    static func normalized(_ vector: [Float]) -> [Float] {
        var output = vector
        var magnitudeSquared: Float = 0
        vDSP_svesq(vector, 1, &magnitudeSquared, vDSP_Length(vector.count))
        let magnitude = sqrt(max(magnitudeSquared, 1e-12))
        var divisor = magnitude
        vDSP_vsdiv(vector, 1, &divisor, &output, 1, vDSP_Length(vector.count))
        return output
    }

    static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &result, vDSP_Length(lhs.count))
        return result
    }

    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { rawBuffer in
            var values = [Float](repeating: 0, count: count)
            for index in 0..<count {
                values[index] = rawBuffer.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<Float>.size,
                    as: Float.self
                )
            }
            return values
        }
    }
}

/// A bounded min-heap used for streaming the best semantic matches without
/// loading an entire vector index into memory.
struct BoundedTopK<Element> {
    private struct Entry {
        let score: Double
        let element: Element
    }

    let limit: Int
    private var heap: [Entry] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    var minimumScore: Double? { heap.first?.score }

    mutating func offer(score: Double, element: Element) {
        if heap.count < limit {
            heap.append(Entry(score: score, element: element))
            siftUp(from: heap.count - 1)
        } else if score > (heap.first?.score ?? -.infinity) {
            heap[0] = Entry(score: score, element: element)
            siftDown(from: 0)
        }
    }

    func sortedDescending() -> [Element] {
        heap.sorted { $0.score > $1.score }.map(\.element)
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            if heap[parent].score <= heap[child].score { break }
            heap.swapAt(parent, child)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < heap.count, heap[left].score < heap[smallest].score { smallest = left }
            if right < heap.count, heap[right].score < heap[smallest].score { smallest = right }
            if smallest == parent { break }
            heap.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
