import Foundation
import Testing

@testable import Ecs

@Suite
struct RawArrayTests {
    @Test
    func appendRemove() {
        var rawArray = RawArray(String.self)
        #expect(rawArray.count == 0)
        #expect(rawArray.capacity == 1)

        var array: [String] = []

        for i in 0..<10 {
            let str = "String_\(i)"
            rawArray.append(str)
            array.append(str)
        }
        #expect(rawArray.count == array.count)
        for i in rawArray.indices {
            #expect(rawArray[i] == array[i])
        }
        for i in 0..<10 {
            let str = "String_\(i + 10)"
            rawArray[i] = str
            array[i] = str
        }

        #expect(rawArray.count == array.count)
        for i in rawArray.indices {
            #expect(rawArray[i] == array[i])
        }

        rawArray.removeLast(2)
        rawArray.swapRemove(at: rawArray.count - 1)
        array.removeLast(3)

        #expect(rawArray.count == array.count)
        for i in rawArray.indices {
            #expect(rawArray[i] == array[i])
        }

        rawArray.swapRemove(at: 1)
        array.swapAt(1, array.count - 1)
        array.removeLast()

        #expect(rawArray.count == array.count)
        for i in rawArray.indices {
            #expect(rawArray[i] == array[i])
        }
    }

    @Test func capacity() {
        var rawArray = RawArray(Int.self)
        #expect(rawArray.count == 0)
        #expect(rawArray.capacity == 1)

        rawArray.append(0)
        #expect(rawArray.count == 1)
        #expect(rawArray.capacity == 1)

        let initialCapacity = 10
        rawArray.reserveCapacity(initialCapacity)
        #expect(rawArray.count == 1)
        #expect(rawArray.capacity == initialCapacity)

        for i in 1..<initialCapacity {
            rawArray.append(i)
        }
        #expect(rawArray.count == initialCapacity)
        #expect(rawArray.capacity == initialCapacity)

        rawArray.append(42)
        #expect(rawArray.capacity > initialCapacity)
        #expect(rawArray.capacity >= rawArray.count)

        rawArray.removeLast(5)
        #expect(rawArray.capacity > initialCapacity)
        #expect(rawArray.capacity > rawArray.count)

        rawArray.removeAll(keepingCapacity: true)
        #expect(rawArray.count == 0)
        #expect(rawArray.capacity > 1)

        rawArray.removeAll()
        #expect(rawArray.count == 0)
        #expect(rawArray.capacity == 1)
    }

    @Test func buffers() {
        var rawArray = RawArray(String.self)
        var array: [String] = []
        for i in 0..<10 {
            let str = "String_\(i)"
            rawArray.append(str)
            array.append(str)
        }

        for i in rawArray.indices {
            let ptr: UnsafeRawPointer = rawArray.pointer(at: i)
            #expect(rawArray[i] == ptr.assumingMemoryBound(to: String.self).pointee)
        }

        for i in rawArray.indices {
            let str = "New String \(i)"
            let ptr: UnsafeMutableRawPointer = rawArray.pointer(at: i)
            ptr.assumingMemoryBound(to: String.self).pointee = str
            array[i] = str
        }

        for i in rawArray.indices {
            let ptr: UnsafeRawPointer = rawArray.pointer(at: i)
            #expect(rawArray[i] == ptr.assumingMemoryBound(to: String.self).pointee)
            #expect(rawArray[i] == array[i])
        }

        let buffer: UnsafeBufferPointer = rawArray.buffer().assumingMemoryBound(to: String.self)
        for (i, str) in buffer.enumerated() {
            #expect(rawArray[i] == str)
        }

        let mutableBuffer: UnsafeMutableBufferPointer = rawArray.buffer().assumingMemoryBound(
            to: String.self)
        array.removeAll()
        for i in mutableBuffer.indices {
            let str = "some value #\(i)"
            mutableBuffer[i] = str
            array.append(str)
        }

        #expect(rawArray.count == array.count)
        for i in rawArray.indices {
            #expect(rawArray[i] == array[i])
        }

        rawArray.removeAll()
        array = ["One", "Two", "Three"]
        array.withUnsafeBufferPointer {
            for i in $0.indices {
                rawArray.append(from: $0.baseAddress! + i)
            }
        }

        #expect(rawArray.count == array.count)
        for i in rawArray.indices {
            #expect(rawArray[i] == array[i])
        }
    }

    @Test
    func cow() {
        var rawArray = RawArray(String.self)
        for i in 0..<10 { rawArray.append("String_\(i)") }

        var copy = rawArray

        #expect(rawArray.storage === copy.storage)
        #expect(!isKnownUniquelyReferenced(&rawArray.storage))
        #expect(!isKnownUniquelyReferenced(&copy.storage))

        copy.append("New String")

        #expect(rawArray.storage !== copy.storage)
        #expect(copy.count == rawArray.count + 1)
        #expect(isKnownUniquelyReferenced(&rawArray.storage))
        #expect(isKnownUniquelyReferenced(&copy.storage))

    }
}
