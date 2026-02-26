public struct View<each T>: Sendable {
    private let included: Set<ComponentID>
    private let excluded: Set<ComponentID>
    private var archetypes: [Int] = []
    private var worldID: UInt = 0
    private var version: UInt = 0

    public private(set) var count: Int = 0

    public init(world: World, included: Set<ComponentID>, excluded: Set<ComponentID>) {
        var included = included
        for type in repeat (each T).self {
            included.insert(ComponentID(type.self))
        }
        self.included = included
        self.excluded = excluded

        rebuild(for: world)
    }

    public func isValid(for world: World) -> Bool {
        worldID == world.id && version == world.groupsVersion
    }

    public mutating func rebuild(for world: World) {
        let indices = world.archetypeIndices(containing: included, excluding: excluded)
        archetypes = []
        archetypes.reserveCapacity(indices.capacity)
        count = 0
        for index in indices {
            archetypes.append(index)
            count += world.archetypes[index].count
        }
        worldID = world.id
        version = world.groupsVersion
    }

    public func forEach(
        in world: World,
        _ body: (repeat each T) throws -> Void
    ) rethrows {
        guard isValid(for: world) else { return }
        for i in archetypes {
            let count = world.archetypes[i].count
            let buffers = (repeat world.archetypes[i].buffer(of: (each T).self))
            for j in 0..<count {
                try body(repeat (each buffers)[j])
            }
        }
    }

    public func forEach(
        in world: inout World,
        _ body: (repeat UnsafeMutablePointer<each T>) throws -> Void
    ) rethrows {
        guard isValid(for: world) else { return }
        for i in archetypes {
            let count = world.archetypes[i].count
            try world.withArchetype(at: i) { archetype in
                let pointers: (repeat UnsafeMutablePointer<each T>)
                pointers = (repeat archetype.buffer(of: (each T).self).baseAddress!)
                for j in 0..<count {
                    try body(repeat (each pointers).advanced(by: j))
                }
            }
        }
    }
}

public struct UnsafeView<each T>: @unchecked Sendable {
    public let buffers: [(repeat UnsafeMutableBufferPointer<each T>)]
    public let count: Int

    public init(world: inout World, included: Set<ComponentID>, excluded: Set<ComponentID>) {
        var included = included
        for type in repeat (each T).self {
            included.insert(ComponentID(type.self))
        }
        let indices = world.archetypeIndices(containing: included, excluding: excluded)
        var buffers: [(repeat UnsafeMutableBufferPointer<each T>)] = []
        buffers.reserveCapacity(indices.count)
        var count = 0
        for index in indices {
            world.withArchetype(at: index) { archetype in
                buffers.append((repeat archetype.buffer(of: (each T).self)))
                count += archetype.count
            }
        }
        self.buffers = buffers
        self.count = count
    }
}

extension UnsafeView: Sequence {
    public func makeIterator() -> UnsafeViewIterator<repeat each T> {
        UnsafeViewIterator(buffers: buffers)
    }
}

public struct UnsafeViewIterator<each T>: IteratorProtocol {
    var buffers: [(repeat UnsafeMutableBufferPointer<each T>)]
    var entityIndex = 0
    var entitiesCount = 0
    var bufferIndex = 0

    init(buffers: [(repeat UnsafeMutableBufferPointer<each T>)]) {
        self.buffers = buffers
        entityIndex = 0
        bufferIndex = 0

        if let tuple = buffers.first {
            for buffer in repeat each tuple {
                entitiesCount = buffer.count
                break
            }
        }
    }

    public mutating func next() -> (repeat UnsafeMutablePointer<each T>)? {
        while bufferIndex < buffers.count {
            while entityIndex < entitiesCount {
                let tuple = buffers[bufferIndex]
                let pointers = (repeat (each tuple).baseAddress!.advanced(by: entityIndex))
                entityIndex += 1
                return pointers
            }
            entityIndex = 0
            bufferIndex += 1
            if bufferIndex < buffers.count {
                let tuple = buffers[bufferIndex]
                for buffer in repeat each tuple {
                    entitiesCount = buffer.count
                    break
                }
            }
        }
        return nil
    }
}

public struct ViewBuilder<each T>: Sendable {
    private let included: Set<ComponentID>
    private let excluded: Set<ComponentID>

    public init(included: Set<ComponentID> = [], excluded: Set<ComponentID> = []) {
        self.included = included
        self.excluded = excluded
    }

    public func including<each U>(_ type: repeat (each U).Type) -> Self {
        var included = included
        for type in repeat (each U).self {
            included.insert(ComponentID(type.self))
        }
        return Self(included: included, excluded: excluded)
    }

    public func excluding<each U>(_ type: repeat (each U).Type) -> Self {
        var excluded = excluded
        for type in repeat (each U).self {
            excluded.insert(ComponentID(type.self))
        }
        return Self(included: included, excluded: excluded)
    }

    public func view(into world: World) -> View<repeat each T> {
        View(world: world, included: included, excluded: excluded)
    }

    public func unsafeView(into world: inout World) -> UnsafeView<repeat each T> {
        UnsafeView(world: &world, included: included, excluded: excluded)
    }
}
