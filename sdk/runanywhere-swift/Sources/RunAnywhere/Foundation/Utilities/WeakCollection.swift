import Foundation

/// A wrapper for weak references
public class WeakBox<T: AnyObject> {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}

/// A collection that holds weak references to objects
public class WeakCollection<T: AnyObject> {
    private var items: [WeakBox<T>] = []
    private let queue = DispatchQueue(label: "com.runanywhere.weak-collection", attributes: .concurrent)

    /// Add an object to the collection
    public func add(_ object: T) {
        queue.async(flags: .barrier) { [weak self] in
            self?.cleanup()
            self?.items.append(WeakBox(object))
        }
    }

    /// Remove an object from the collection
    public func remove(_ object: T) {
        queue.async(flags: .barrier) { [weak self] in
            self?.items.removeAll { $0.value === object }
        }
    }

    /// Get all non-nil objects
    public var allObjects: [T] {
        queue.sync {
            cleanup()
            return items.compactMap { $0.value }
        }
    }

    /// Get the count of non-nil objects
    public var count: Int {
        allObjects.count
    }

    /// Check if collection contains an object
    public func contains(_ object: T) -> Bool {
        queue.sync {
            items.contains { $0.value === object }
        }
    }

    /// Remove all nil references
    private func cleanup() {
        items.removeAll { $0.value == nil }
    }

    /// Remove all objects
    public func removeAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.items.removeAll()
        }
    }

    /// Execute a closure for each non-nil object
    public func forEach(_ body: (T) -> Void) {
        allObjects.forEach(body)
    }
}
