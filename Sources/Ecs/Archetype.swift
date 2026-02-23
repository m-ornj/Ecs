public typealias ArchetypeID = [ComponentID]

public struct ArchetypeSchema: Sendable {
    public let layout: [ComponentLayout]
    public let id: [ComponentID]

    public init<T: Component>(componentType: T.Type) {
        self.layout = [ComponentLayout(T.self)]
        self.id = [ComponentID(T.self)]
    }

    /// Does NOT sort or de-duplicate the arrays
    private init(layout: [ComponentLayout], id: [ComponentID]) {
        self.layout = layout
        self.id = id
    }

    public func adding<T: Component>(_ type: T.Type) -> ArchetypeSchema {
        let newLayout = ComponentLayout(T.self)
        let newID = ComponentID(T.self)

        var index = id.endIndex
        for i in 0...id.count {
            if newID > id[i] {
                index = i
                break
            }
        }

        var layout = layout
        var id = id
        layout.insert(newLayout, at: index)
        id.insert(newID, at: index)
        return ArchetypeSchema(layout: layout, id: id)
    }

    public func removing<T: Component>(_ type: T.Type) -> ArchetypeSchema {
        let newID = ComponentID(T.self)

        var layout = layout
        var id = id
        for i in 0..<id.count {
            if newID == id[i] {
                layout.remove(at: i)
                id.remove(at: i)
                break
            }
        }
        return ArchetypeSchema(layout: layout, id: id)
    }
}

public struct Archetype: Sendable {
    public let schema: ArchetypeSchema
    private var components: [ComponentArray] = []
    private var indices: [ComponentID: Int] = [:]

    public var count: Int { components.first?.count ?? 0 }

    public init(schema: ArchetypeSchema) {
        self.schema = schema
        self.components.reserveCapacity(schema.layout.count)
        for i in 0..<schema.layout.count {
            let id = schema.id[i]
            components.append(ComponentArray(layout: schema.layout[i]))
            indices[id] = components.count - 1
        }
    }

    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        for i in 0..<components.count {
            components[i].reserveCapacity(minimumCapacity)
        }
    }

    public mutating func append(_ data: [ComponentID: UnsafeRawPointer]) {
        for i in 0..<components.count {
            let id = schema.id[i]
            guard let pointer = data[id] else {
                preconditionFailure("Component \(id) not found")
            }
            components[i].append(pointer)
        }
    }

    public mutating func append(values: [ComponentID: Any]) {
        for i in 0..<components.count {
            let id = schema.id[i]
            guard let value = values[id] else {
                preconditionFailure("Component \(id) not found")
            }
            components[i].append(value: value)
        }
    }

    public mutating func removeLast() {
        for i in 0..<components.count {
            components[i].removeLast()
        }
    }

    public mutating func moveLast(to index: Int) {
        for i in 0..<components.count {
            components[i].moveLast(to: index)
        }
    }

    public func read(at index: Int) -> [ComponentID: UnsafeRawPointer] {
        precondition((0..<count).contains(index), "Index out of bounds")

        var data: [ComponentID: UnsafeRawPointer] = [:]
        for i in 0..<components.count {
            let id = schema.id[i]
            data[id] = components[i].pointer(at: index)
        }
        return data
    }

    public func contains<T: Component>(_ type: T.Type) -> Bool {
        let id = ComponentID(T.self)
        return indices[id] != nil
    }

    public func get<T: Component>(_ type: T.Type, at index: Int) -> T? {
        guard let componentIndex = indices[ComponentID(T.self)] else { return nil }
        let value: T = components[componentIndex][index]
        return value
    }

    public subscript<T: Component>(_ index: Int) -> T {
        get {
            let componentIndex = self.index(of: T.self)
            return components[componentIndex][index]
        }
        mutating set(newValue) {
            let componentIndex = self.index(of: T.self)
            components[componentIndex][index] = newValue
        }
    }

    public func buffer<T: Component>(of type: T.Type) -> UnsafeBufferPointer<T> {
        let componentIndex = index(of: T.self)
        return components[componentIndex].buffer(of: T.self)
    }

    public mutating func buffer<T: Component>(of type: T.Type) -> UnsafeMutableBufferPointer<T> {
        let componentIndex = index(of: T.self)
        return components[componentIndex].buffer(of: T.self)
    }
}

extension Archetype {
    private func index<T: Component>(of type: T.Type) -> Int {
        let id = ComponentID(T.self)
        guard let index = indices[id] else {
            preconditionFailure("Component \(T.self) not found in archetype.")
        }
        return index
    }
}

public struct ArchetypeRegistry: Sendable {
    public private(set) var archetypes: [Archetype] = []
    public private(set) var indexByID: [ArchetypeID: UInt32] = [:]

    public mutating func register(schema: ArchetypeSchema) -> UInt32 {
        if let index = indexByID[schema.id] {
            return index
        }
        let archetype = Archetype(schema: schema)
        archetypes.append(archetype)
        let index = UInt32(archetypes.count - 1)
        indexByID[archetype.schema.id] = index
        return index
    }
}

extension ArchetypeRegistry: RandomAccessCollection {
    public typealias Index = UInt32
    public typealias Element = Archetype

    public var startIndex: UInt32 { UInt32(archetypes.startIndex) }
    public var endIndex: UInt32 { UInt32(archetypes.endIndex) }

    public subscript(_ position: UInt32) -> Archetype {
        get {
            return archetypes[Int(position)]
        }
        mutating set(newValue) {
            let oldID = self.archetypes[Int(position)].schema.id
            let newID = newValue.schema.id

            archetypes[Int(position)] = newValue

            if oldID != newID {
                indexByID.removeValue(forKey: oldID)
            }
            indexByID[newID] = UInt32(position)
        }
    }
}
