// MARK: BufferPointerProtocol
public protocol BufferPointerProtocol {
    var count: Int { get }
    static var null: Self { get }
}

extension UnsafeBufferPointer: BufferPointerProtocol {
    @inlinable public static var null: Self { Self(start: nil, count: 0) }
}
extension UnsafeMutableBufferPointer: BufferPointerProtocol {
    @inlinable public static var null: Self { Self(start: nil, count: 0) }
}

// MARK: BufferPack
public struct BufferPack<each T: BufferPointerProtocol>: @unchecked Sendable {
    public let buffers: (repeat each T)
    public let count: Int

    public init(_ buffers: (repeat each T)) {
        var count: Int?
        for buffer in repeat each buffers {
            assert(count == nil || count == buffer.count)
            count = buffer.count
        }
        self.buffers = buffers
        self.count = count ?? 0
    }

    public static var null: Self {
        Self((repeat (each T).null))
    }
}

// MARK: View
public struct View<each T>: Sequence, IteratorProtocol, Sendable {
    public let packs: [BufferPack<repeat UnsafeBufferPointer<each T>>]
    @usableFromInline var pack: BufferPack<repeat UnsafeBufferPointer<each T>>
    @usableFromInline var packIndex: Int = 0
    @usableFromInline var elementIndex: Int = 0

    public init(_ packs: [BufferPack<repeat UnsafeBufferPointer<each T>>]) {
        self.packs = packs
        self.pack = packs.first ?? .null
    }

    @inlinable public func count() -> Int { packs.reduce(0) { $0 + $1.count } }

    @inlinable public mutating func next() -> (Int, (repeat UnsafeBufferPointer<each T>))? {
        while packIndex < packs.endIndex {
            while elementIndex < pack.count {
                defer { elementIndex += 1 }
                return (elementIndex, pack.buffers)
            }
            elementIndex = 0
            packIndex += 1
            if packIndex < packs.endIndex {
                pack = packs[packIndex]
            }
        }
        return nil
    }
}

// MARK: MutableView
public struct MutableView<each T>: Sequence, IteratorProtocol, Sendable {
    public let packs: [BufferPack<repeat UnsafeMutableBufferPointer<each T>>]
    @usableFromInline var pack: BufferPack<repeat UnsafeMutableBufferPointer<each T>>
    @usableFromInline var packIndex: Int = 0
    @usableFromInline var elementIndex: Int = 0

    public init(_ packs: [BufferPack<repeat UnsafeMutableBufferPointer<each T>>]) {
        self.packs = packs
        self.pack = packs.first ?? .null
    }

    @inlinable public func count() -> Int { packs.reduce(0) { $0 + $1.count } }

    @inlinable public mutating func next() -> (Int, (repeat UnsafeMutableBufferPointer<each T>))? {
        while packIndex < packs.endIndex {
            while elementIndex < pack.count {
                defer { elementIndex += 1 }
                return (elementIndex, pack.buffers)
            }
            elementIndex = 0
            packIndex += 1
            if packIndex < packs.endIndex {
                pack = packs[packIndex]
            }
        }
        return nil
    }
}
