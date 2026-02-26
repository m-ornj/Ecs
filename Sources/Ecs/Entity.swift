public struct Entity: Hashable, Sendable {
    @usableFromInline internal static let indexMask: UInt32 = 0x00FF_FFFF
    @usableFromInline internal static let generationShift: UInt32 = 24

    @usableFromInline internal let storage: UInt32

    @inlinable public var index: Int { Int(storage & Self.indexMask) }
    @inlinable public var generation: UInt8 { UInt8(storage >> Self.generationShift) }

    init(index: UInt32, generation: UInt8) {
        precondition(index <= Entity.endIndex, "Index greater than Entity.endIndex")
        storage = (index & Self.indexMask) | (UInt32(generation) << Self.generationShift)
    }

    public static let endIndex: UInt32 = 0x00FF_FFFF
}
