public struct ViewBuilder<each T>: Sendable {
    public let included: Set<ComponentID>
    public let excluded: Set<ComponentID>

    public init(included: Set<ComponentID> = [], excluded: Set<ComponentID> = []) {
        self.included = included
        self.excluded = excluded
    }

    public func including<each U>(_ u: repeat (each U).Type) -> Self {
        var included = included
        for U in repeat (each U).self {
            included.insert(ComponentID(U.self))
        }
        return Self(included: included, excluded: excluded)
    }

    public func excluding<each U>(_ u: repeat (each U).Type) -> Self {
        var excluded = excluded
        for U in repeat (each U).self {
            excluded.insert(ComponentID(U.self))
        }
        return Self(included: included, excluded: excluded)
    }

    public func view(into world: World) -> View<repeat each T> {
        var included = included
        for T in repeat (each T).self {
            included.insert(ComponentID(T.self))
        }
        let indices = world.archetypeLookup.indices(containing: included, excluding: excluded)
        let packs: [BufferPack<repeat UnsafeBufferPointer<each T>>] = indices.map {
            BufferPack((repeat world.buffer(of: (each T).self, fromArchetypeAt: $0)))
        }
        return View(packs)
    }

    public func view(into world: inout World) -> MutableView<repeat each T> {
        var included = included
        for T in repeat (each T).self {
            included.insert(ComponentID(T.self))
        }
        let indices = world.archetypeLookup.indices(containing: included, excluding: excluded)
        let packs: [BufferPack<repeat UnsafeMutableBufferPointer<each T>>] = indices.map {
            BufferPack((repeat world.buffer(of: (each T).self, fromArchetypeAt: $0)))
        }
        return MutableView(packs)
    }
}
