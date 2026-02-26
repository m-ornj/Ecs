public typealias ComponentID = ObjectIdentifier

public struct ArchetypeID: Sendable, Hashable {
    public let componentIDs: [ComponentID]

    public init<each T>(_ types: repeat (each T).Type) {
        var count = 0
        for _ in repeat (each T).self { count += 1 }
        var componentIDs: [ComponentID] = []
        componentIDs.reserveCapacity(count)
        for T in repeat (each T).self { componentIDs.append(ComponentID(T.self)) }
        componentIDs.sort()
        for i in 0..<componentIDs.count - 1 {
            precondition(componentIDs[i] != componentIDs[i + 1], "Duplicate component")
        }
        self.componentIDs = componentIDs
    }

    /// Does NOT sort or de-duplicate the array
    private init(componentIDs: [ComponentID]) {
        self.componentIDs = componentIDs
    }

    public func adding<T>(_ type: T.Type) -> Self {
        let newComponentID = ComponentID(T.self)

        var index = componentIDs.endIndex
        for i in 0..<componentIDs.count {
            precondition(newComponentID != componentIDs[i], "Duplicate component \(T.self)")
            if newComponentID < componentIDs[i] {
                index = i
                break
            }
        }

        var componentIDs = componentIDs
        componentIDs.insert(newComponentID, at: index)
        return Self(componentIDs: componentIDs)
    }

    public func removing<T>(_ type: T.Type) -> Self {
        let componentID = ComponentID(T.self)

        var componentIDs = componentIDs
        componentIDs.removeAll { $0 == componentID }
        return Self(componentIDs: componentIDs)
    }
}

public struct Archetype: Sendable {
    public let id: ArchetypeID
    public private(set) var components: [RawArray] = []
    public private(set) var indices: [ComponentID: Int] = [:]

    public var count: Int { components.first?.count ?? 0 }

    public init<each T>(_ t: repeat (each T).Type) {
        id = ArchetypeID(repeat (each T).self)
        components.reserveCapacity(id.componentIDs.count)
        indices.reserveCapacity(id.componentIDs.count)
        for T in repeat (each T).self {
            indices[ComponentID(T.self)] = components.endIndex
            components.append(RawArray(T.self))
        }
    }
}

// public
extension Archetype {
    public func contains<T>(_ t: T.Type) -> Bool {
        let componentID = ComponentID(T.self)
        return indices[componentID] != nil
    }

    public mutating func append<each T>(_ values: repeat each T) {
        for (value, T) in repeat (each values, (each T).self) {
            let componentIndex = componentIndex(of: T.self)
            components[componentIndex].append(value)
        }
    }

    public mutating func append(from other: Self, at position: Int) {
        for (componentID, index) in indices {
            if let otherIndex = other.indices[componentID] {
                components[index].append(from: other.components[otherIndex].pointer(at: position))
            }
        }
    }

    public subscript<T>(_ position: Int) -> T {
        get {
            let componentIndex = componentIndex(of: T.self)
            return components[componentIndex][position]
        }
        mutating set(value) {
            let componentIndex = componentIndex(of: T.self)
            components[componentIndex][position] = value
        }
    }

    public func buffer<T>(of type: T.Type) -> UnsafeBufferPointer<T> {
        let index = componentIndex(of: T.self)
        return components[index].buffer().assumingMemoryBound(to: T.self)
    }

    public mutating func buffer<T>(of type: T.Type) -> UnsafeMutableBufferPointer<T> {
        let index = componentIndex(of: T.self)
        return components[index].buffer().assumingMemoryBound(to: T.self)
    }

    public mutating func swapRemove(at position: Int) {
        for i in components.indices {
            components[i].swapRemove(at: position)
        }
    }
}

// private
extension Archetype {
    private init(id: ArchetypeID, components: [RawArray], indices: [ComponentID: Int]) {
        self.id = id
        self.components = components
        self.indices = indices
    }

    private func componentIndex<T>(of type: T.Type) -> Int {
        let id = ComponentID(T.self)
        guard let index = indices[id] else {
            preconditionFailure("Component \(T.self) not found in archetype.")
        }
        return index
    }
}

extension Archetype {
    public func adding<T>(_ t: T.Type, newID: ArchetypeID) -> Self {
        let componentID = ComponentID(T.self)
        precondition(indices[componentID] == nil, "Adding a duplicate type \(T.self)")

        var indices = indices
        var components = components
        for i in components.indices {
            components[i].removeAll()
        }

        indices[componentID] = components.endIndex
        components.reserveCapacity(components.count + 1)
        components.append(RawArray(T.self))

        return Self(id: newID, components: components, indices: indices)
    }

    public func removing<T>(_ t: T.Type, newID: ArchetypeID) -> Self {
        let componentID = ComponentID(T.self)
        let index = componentIndex(of: T.self)

        var indices = indices
        var components = components

        let lastIndex = components.count - 1
        let lastComponentID = indices.first { $0.value == lastIndex }!.key

        components.swapAt(index, components.count - 1)
        indices[lastComponentID] = index
        indices.removeValue(forKey: componentID)
        components.removeLast()

        for i in components.indices {
            components[i].removeAll()
        }

        return Self(id: newID, components: components, indices: indices)
    }
}
