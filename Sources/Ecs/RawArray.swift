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

public final class RawArrayStorage {
    let fn: RawArrayFunctions
    let stride: Int
    let alignment: Int

    public private(set) var pointer: UnsafeMutableRawPointer
    public private(set) var capacity: Int = 1
    public private(set) var count: Int = 0

    public init<T>(_ t: T.Type) {
        self.fn = RawArrayFunctionsImpl<T>()
        self.stride = MemoryLayout<T>.stride
        self.alignment = MemoryLayout<T>.alignment
        self.pointer = UnsafeMutableRawPointer.allocate(
            byteCount: stride * capacity,
            alignment: alignment
        )
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
    public func clone() -> RawArrayStorage {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: stride * capacity,
            alignment: alignment
        )
        return RawArrayStorage(
            fn: fn,
            stride: stride,
            alignment: alignment,
            pointer: pointer,
            capacity: capacity,
            count: count
        )
    }

    public func reserveCapacity(_ minimumCapacity: Int) {
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

    public func append(from source: UnsafeRawPointer) {
        reserveCapacity(count + 1)
        let destination = pointer.advanced(by: stride * count)
        fn.initialize(from: source, to: destination, count: 1)
        count += 1
    }

    public func append<T>(_ value: T) {
        reserveCapacity(count + 1)
        let destination = pointer.assumingMemoryBound(to: T.self).advanced(by: count)
        destination.update(repeating: value, count: 1)
        count += 1
    }

    public func removeLast(_ k: Int = 1) {
        let pointer = pointer.advanced(by: stride * (count - k))
        fn.deinitialize(pointer: pointer, count: k)
        count -= k
    }

    public func swapRemove(at position: Int) {
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

    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
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
    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript<T>(_ position: Int) -> T {
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

public struct RawArray: @unchecked Sendable {
    @usableFromInline var storage: RawArrayStorage

    public init<T>(_ t: T.Type) {
        storage = RawArrayStorage(T.self)
    }
}

// public
extension RawArray {
    @inlinable public mutating func reserveCapacity(_ minimumCapacity: Int) {
        storage.reserveCapacity(minimumCapacity)
    }

    @inlinable public mutating func append(from source: UnsafeRawPointer) {
        ensureUnique()
        storage.append(from: source)
    }

    @inlinable public mutating func append<T>(_ value: T) {
        ensureUnique()
        storage.append(value)
    }

    @inlinable public mutating func removeLast(_ k: Int = 1) {
        ensureUnique()
        storage.removeLast(k)
    }

    @inlinable public mutating func swapRemove(at position: Int) {
        ensureUnique()
        storage.swapRemove(at: position)
    }

    @inlinable public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        ensureUnique()
        storage.removeAll(keepingCapacity: keepCapacity)
    }

    public func pointer(at position: Int) -> UnsafeRawPointer {
        UnsafeRawPointer(storage.pointer.advanced(by: position * storage.stride))
    }

    public mutating func pointer(at position: Int) -> UnsafeMutableRawPointer {
        storage.pointer.advanced(by: position * storage.stride)
    }

    public func buffer() -> UnsafeRawBufferPointer {
        UnsafeRawBufferPointer(start: storage.pointer, count: storage.count * storage.stride)
    }

    public mutating func buffer() -> UnsafeMutableRawBufferPointer {
        UnsafeMutableRawBufferPointer(start: storage.pointer, count: storage.count * storage.stride)
    }
}

// private
extension RawArray {
    @usableFromInline mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.clone()
        }
    }
}

extension RawArray: RandomAccessCollection {
    @inlinable public var startIndex: Int { storage.startIndex }
    @inlinable public var endIndex: Int { storage.endIndex }
    @inlinable public var capacity: Int { storage.capacity }

    @inlinable public subscript<T>(_ position: Int) -> T {
        get {
            storage[position]
        }
        mutating set(source) {
            ensureUnique()
            storage[position] = source
        }
    }
}