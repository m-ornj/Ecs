// MARK: RawArrayFunctions
protocol RawArrayFunctions {
    func initialize(from: UnsafeRawPointer, to: UnsafeMutableRawPointer, count: Int)
    func moveInitialize(from: UnsafeMutableRawPointer, to: UnsafeMutableRawPointer, count: Int)
    func moveUpdate(from: UnsafeMutableRawPointer, to: UnsafeMutableRawPointer, count: Int)
    func deinitialize(pointer: UnsafeMutableRawPointer, count: Int)
}

struct RawArrayFunctionsImpl<T>: RawArrayFunctions {
    func initialize(
        from source: UnsafeRawPointer,
        to destination: UnsafeMutableRawPointer,
        count: Int
    ) {
        let src = source.assumingMemoryBound(to: T.self)
        let dst = destination.assumingMemoryBound(to: T.self)
        dst.initialize(from: src, count: count)
    }

    func moveInitialize(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        count: Int
    ) {
        let src = source.assumingMemoryBound(to: T.self)
        let dst = destination.assumingMemoryBound(to: T.self)
        dst.moveInitialize(from: src, count: count)
    }

    func moveUpdate(
        from source: UnsafeMutableRawPointer,
        to destination: UnsafeMutableRawPointer,
        count: Int
    ) {
        let src = source.assumingMemoryBound(to: T.self)
        let dst = destination.assumingMemoryBound(to: T.self)
        dst.moveUpdate(from: src, count: count)
    }

    func deinitialize(pointer: UnsafeMutableRawPointer, count: Int) {
        let pointer = pointer.assumingMemoryBound(to: T.self)
        pointer.deinitialize(count: count)
    }
}

// MARK: RawArrayStorage
final class RawArrayStorage {
    let fn: RawArrayFunctions
    let stride: Int
    let alignment: Int

    private(set) var pointer: UnsafeMutableRawPointer
    private(set) var capacity: Int = 1
    private(set) var count: Int = 0

    init<T>(of t: T.Type, capacity: Int = 1) {
        self.fn = RawArrayFunctionsImpl<T>()
        self.stride = MemoryLayout<T>.stride
        self.alignment = MemoryLayout<T>.alignment
        self.pointer = UnsafeMutableRawPointer.allocate(
            byteCount: stride * capacity,
            alignment: alignment
        )
        self.capacity = capacity
    }

    init(
        fn: RawArrayFunctions,
        stride: Int,
        alignment: Int,
        pointer: UnsafeMutableRawPointer,
        capacity: Int,
        count: Int
    ) {
        self.fn = fn
        self.stride = stride
        self.alignment = alignment
        self.pointer = pointer
        self.capacity = capacity
        self.count = count
    }

    deinit {
        fn.deinitialize(pointer: pointer, count: count)
        pointer.deallocate()
    }
}

extension RawArrayStorage {
    func clone() -> RawArrayStorage {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: stride * capacity,
            alignment: alignment
        )
        fn.initialize(from: self.pointer, to: pointer, count: count)
        return RawArrayStorage(
            fn: fn,
            stride: stride,
            alignment: alignment,
            pointer: pointer,
            capacity: capacity,
            count: count
        )
    }

    func reserveCapacity(_ minimumCapacity: Int) {
        guard capacity < minimumCapacity else { return }

        let newCapacity = Swift.max(minimumCapacity, capacity * 2)
        let newPointer = UnsafeMutableRawPointer.allocate(
            byteCount: stride * newCapacity,
            alignment: alignment
        )

        if count > 0 {
            fn.moveInitialize(from: pointer, to: newPointer, count: count)
            pointer.deallocate()
        }

        self.pointer = newPointer
        self.capacity = newCapacity
    }

    func append(from source: UnsafeRawPointer) {
        reserveCapacity(count + 1)
        let destination = pointer.advanced(by: stride * count)
        fn.initialize(from: source, to: destination, count: 1)
        count += 1
    }

    func append<T>(_ value: T) {
        reserveCapacity(count + 1)
        let destination = pointer.assumingMemoryBound(to: T.self).advanced(by: count)
        destination.update(repeating: value, count: 1)
        count += 1
    }

    func removeLast(_ k: Int = 1) {
        let pointer = pointer.advanced(by: stride * (count - k))
        fn.deinitialize(pointer: pointer, count: k)
        count -= k
    }

    func swapRemove(at position: Int) {
        let lastPosition = count - 1
        let source = pointer.advanced(by: stride * lastPosition)
        let destination = pointer.advanced(by: stride * position)
        if position < lastPosition {
            fn.moveUpdate(from: source, to: destination, count: 1)
        } else {
            fn.deinitialize(pointer: destination, count: 1)
        }
        count -= 1
    }

    func removeAll(keepingCapacity keepCapacity: Bool = false) {
        fn.deinitialize(pointer: pointer, count: count)
        count = 0
        if !keepCapacity {
            pointer.deallocate()
            capacity = 1
            pointer = UnsafeMutableRawPointer.allocate(
                byteCount: stride * capacity,
                alignment: alignment
            )
        }
    }
}

extension RawArrayStorage: RandomAccessCollection {
    var startIndex: Int { 0 }
    var endIndex: Int { count }

    subscript<T>(_ position: Int) -> T {
        get {
            pointer.assumingMemoryBound(to: T.self).advanced(by: position).pointee
        }
        set(value) {
            let pointer =
                pointer
                .assumingMemoryBound(to: T.self)
                .advanced(by: position)
            pointer.update(repeating: value, count: 1)
        }
    }
}

// MARK: RawArray
public struct RawArray: @unchecked Sendable {
    var storage: RawArrayStorage
}

extension RawArray {
    public init<T>(of t: T.Type, capacity: Int = 1) {
        storage = RawArrayStorage(of: T.self, capacity: capacity)
    }

    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        storage.reserveCapacity(minimumCapacity)
    }

    public mutating func append(from source: UnsafeRawPointer) {
        ensureUnique()
        storage.append(from: source)
    }

    public mutating func append<T>(_ value: T) {
        ensureUnique()
        storage.append(value)
    }

    public mutating func removeLast(_ k: Int = 1) {
        ensureUnique()
        storage.removeLast(k)
    }

    public mutating func swapRemove(at position: Int) {
        ensureUnique()
        storage.swapRemove(at: position)
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        ensureUnique()
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func pointer(at position: Int = 0) -> UnsafeRawPointer {
        UnsafeRawPointer(storage.pointer.advanced(by: position * storage.stride))
    }

    public mutating func pointer(at position: Int = 0) -> UnsafeMutableRawPointer {
        ensureUnique()
        return storage.pointer.advanced(by: position * storage.stride)
    }

    public func buffer() -> UnsafeRawBufferPointer {
        return UnsafeRawBufferPointer(
            start: storage.pointer,
            count: storage.count * storage.stride
        )
    }

    public mutating func buffer() -> UnsafeMutableRawBufferPointer {
        ensureUnique()
        return UnsafeMutableRawBufferPointer(
            start: storage.pointer,
            count: storage.count * storage.stride
        )
    }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.clone()
        }
    }
}

extension RawArray: RandomAccessCollection {
    public var startIndex: Int { storage.startIndex }
    public var endIndex: Int { storage.endIndex }
    public var capacity: Int { storage.capacity }

    public subscript<T>(_ position: Int) -> T {
        get {
            storage[position]
        }
        mutating set(value) {
            ensureUnique()
            storage[position] = value
        }
    }
}
