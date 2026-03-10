public typealias ComponentID = ObjectIdentifier

// MARK: ArchetypeID
public struct ArchetypeID: Sendable, Hashable {
    public let componentIDs: Set<ComponentID>
}

extension ArchetypeID {
    public init<each T>(_ types: repeat (each T).Type) {
        var count = 0
        for _ in repeat (each T).self { count += 1 }
        var componentIDs = Set<ComponentID>(minimumCapacity: count)
        for T in repeat (each T).self {
            let inserted = componentIDs.insert(ComponentID(T.self)).inserted
            precondition(inserted, "Duplicate type \(T.self)")
        }
        self.componentIDs = componentIDs
    }

    public func adding<T>(_ type: T.Type) -> Self {
        var componentIDs = componentIDs
        let inserted = componentIDs.insert(ComponentID(T.self)).inserted
        precondition(inserted, "Duplicate type \(T.self)")
        return Self(componentIDs: componentIDs)
    }

    public func removing<T>(_ type: T.Type) -> Self {
        var componentIDs = componentIDs
        componentIDs.remove(ComponentID(T.self))
        return Self(componentIDs: componentIDs)
    }
}

// MARK: ComponentArray
public struct ComponentArray: Sendable {
    public var array: RawArray
    public let id: ComponentID

    public init<T>(of t: T.Type, capacity: Int = 1) {
        array = RawArray(of: T.self, capacity: capacity)
        id = ComponentID(T.self)
    }
}

// MARK: Archetype
public struct Archetype: Sendable {
    public let id: ArchetypeID
    public private(set) var components: [ComponentArray] = []
    public private(set) var indices: [ComponentID: Int] = [:]

    public var count: Int { components.first?.array.count ?? 0 }
    public var capacity: Int { components.first?.array.capacity ?? 0 }
    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
}

extension Archetype {
    public init<each T>(for t: repeat (each T).Type, capacity: Int = 1) {
        id = ArchetypeID(repeat (each T).self)
        components.reserveCapacity(id.componentIDs.count)
        indices.reserveCapacity(id.componentIDs.count)
        for T in repeat (each T).self {
            indices[ComponentID(T.self)] = components.endIndex
            components.append(ComponentArray(of: T.self, capacity: capacity))
        }
    }

    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        for i in components.indices {
            components[i].array.reserveCapacity(minimumCapacity)
        }
    }

    public func contains<T>(_ t: T.Type) -> Bool {
        let componentID = ComponentID(T.self)
        return indices[componentID] != nil
    }

    public mutating func append<each T>(_ values: repeat each T) {
        repeat components[componentIndex(of: (each T).self)].array.append(each values)
    }

    public mutating func append(from other: Self, at position: Int) {
        for (componentID, i) in indices {
            if let j = other.indices[componentID] {
                components[i].array.append(from: other.components[j].array.pointer(at: position))
            }
        }
    }

    public subscript<T>(_ position: Int) -> T {
        get {
            let componentIndex = componentIndex(of: T.self)
            return components[componentIndex].array[position]
        }
        mutating set(value) {
            let componentIndex = componentIndex(of: T.self)
            components[componentIndex].array[position] = value
        }
    }

    public mutating func swapRemove(at position: Int) {
        for i in components.indices {
            components[i].array.swapRemove(at: position)
        }
    }

    public func buffer<T>(of type: T.Type) -> UnsafeBufferPointer<T> {
        let index = componentIndex(of: T.self)
        return components[index].array.buffer().assumingMemoryBound(to: T.self)
    }

    public mutating func buffer<T>(of type: T.Type) -> UnsafeMutableBufferPointer<T> {
        let index = componentIndex(of: T.self)
        return components[index].array.buffer().assumingMemoryBound(to: T.self)
    }

    public func adding<T>(_ t: T.Type) -> Self {
        let componentID = ComponentID(T.self)
        guard indices[componentID] == nil else {
            assertionFailure("Component \(T.self) is already in archetype.")
            return self
        }

        var indices = indices
        var components = components
        for i in components.indices {
            components[i].array.removeAll()
        }

        indices[componentID] = components.endIndex
        components.append(ComponentArray(of: T.self))

        return Self(id: id.adding(T.self), components: components, indices: indices)
    }

    public func removing<T>(_ t: T.Type) -> Self {
        let componentID = ComponentID(T.self)
        guard let index = indices[componentID] else {
            assertionFailure("Component \(T.self) not found in archetype.")
            return self
        }

        var indices = indices
        var components = components
        for i in components.indices {
            components[i].array.removeAll()
        }

        if index != components.count - 1 {
            components.swapAt(index, components.count - 1)
            indices[components[index].id] = index
        }
        components.removeLast()
        indices.removeValue(forKey: componentID)

        return Self(id: id.removing(T.self), components: components, indices: indices)
    }

    private func componentIndex<T>(of type: T.Type) -> Int {
        let id = ComponentID(T.self)
        guard let index = indices[id] else {
            preconditionFailure("Component \(T.self) not found in archetype.")
        }
        return index
    }
}
