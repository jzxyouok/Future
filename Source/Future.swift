//
// MIT License
//
// Copyright (c) 2019 zhiycn
//

import class Dispatch.DispatchSemaphore

public final class Future<T> {

    @usableFromInline
    var result: Result<T, Error>?

    @usableFromInline
    var callbacks: [Callback]

    @usableFromInline
    var semaphore: DispatchSemaphore?

    @inlinable
    public init(_ value: T) {
        result = .success(value)
        callbacks = []
        semaphore = nil
    }

    @inlinable
    public init(error: Error) {
        result = .failure(error)
        callbacks = []
        semaphore = nil
    }

    @inlinable
    public init(catching body: () throws -> T) {
        result = Result(catching: body)
        callbacks = []
        semaphore = nil
    }

    @inlinable
    init() {
        result = nil
        callbacks = []
        semaphore = DispatchSemaphore(value: 1)
    }

    @inlinable
    func setResult(_ result: Result<T, Error>) {
        semaphore?.wait()
        defer {
            semaphore?.signal()
            semaphore = nil
        }
        guard self.result == nil else { return }
        callbacks.forEach { $0(result) }
        callbacks = []
        self.result = result
    }

    @inlinable
    func addCallback(_ callback: @escaping Callback) {
        semaphore?.wait()
        defer { semaphore?.signal() }
        if let result = result {
            callback(result)
        } else {
            callbacks.append(callback)
        }
    }

    @usableFromInline
    typealias Callback = (Result<T, Error>) -> Void
}

extension Future {

    @inlinable
    public func map<U>(_ transform: @escaping (T) throws -> U) -> Future<U> {
        if let result = result {
            switch result {
            case .success(let t):
                do {
                    let u = try transform(t)
                    return Future<U>(u)
                } catch {
                    return Future<U>(error: error)
                }
            case .failure(let e):
                return Future<U>(error: e)
            }
        }
        let future = Future<U>()
        addCallback { result in
            switch result {
            case .success(let t):
                do {
                    let u = try transform(t)
                    future.setResult(.success(u))
                } catch {
                    future.setResult(.failure(error))
                }
            case .failure(let e):
                future.setResult(.failure(e))
            }
        }
        return future
    }

    @inlinable
    public func flatMap<U>(_ transform: @escaping (T) throws -> Future<U>) -> Future<U> {
        if let result = result {
            switch result {
            case .success(let t):
                do {
                    return try transform(t)
                } catch {
                    return Future<U>(error: error)
                }
            case .failure(let e):
                return Future<U>(error: e)
            }
        }
        let future = Future<U>()
        addCallback { result in
            switch result {
            case .success(let t):
                do {
                    let newFuture = try transform(t)
                    newFuture.addCallback { future.setResult($0) }
                } catch {
                    future.setResult(.failure(error))
                }
            case .failure(let e):
                future.setResult(.failure(e))
            }
        }
        return future
    }

    @inlinable
    public func mapError(_ transform: @escaping (Error) throws -> Error) -> Future {
        if let result = result {
            switch result {
            case .success:
                return self
            case .failure(let e):
                do {
                    let error = try transform(e)
                    return Future(error: error)
                } catch {
                    return Future(error: error)
                }
            }
        }
        let future = Future()
        addCallback { result in
            switch result {
            case .success:
                future.setResult(result)
            case .failure(let e):
                do {
                    let error = try transform(e)
                    future.setResult(.failure(error))
                } catch {
                    future.setResult(.failure(error))
                }
            }
        }
        return future
    }

    @inlinable
    public func flatMapError(_ transform: @escaping (Error) throws -> Future) -> Future {
        if let result = result {
            switch result {
            case .success:
                return self
            case .failure(let e):
                do {
                    return try transform(e)
                } catch {
                    return Future(error: error)
                }
            }
        }
        let future = Future()
        addCallback { result in
            switch result {
            case .success:
                future.setResult(result)
            case .failure(let e):
                do {
                    let newFuture = try transform(e)
                    newFuture.addCallback { future.setResult($0) }
                } catch {
                    future.setResult(.failure(error))
                }
            }
        }
        return future
    }

    @inlinable
    public func recover(_ recovery: @escaping (Error) throws -> T) -> Future {
        if let result = result {
            switch result {
            case .success:
                return self
            case .failure(let e):
                do {
                    let t = try recovery(e)
                    return Future(t)
                } catch {
                    return Future(error: error)
                }
            }
        }
        let future = Future()
        addCallback { result in
            switch result {
            case .success:
                future.setResult(result)
            case .failure(let e):
                do {
                    let t = try recovery(e)
                    future.setResult(.success(t))
                } catch {
                    future.setResult(.failure(error))
                }
            }
        }
        return future
    }
}

extension Future {

    @inlinable
    public func map<U>(_ keyPath: KeyPath<T, U>) -> Future<U> {
        if let result = result {
            switch result {
            case .success(let t):
                let u = t[keyPath: keyPath]
                return Future<U>(u)
            case .failure(let e):
                return Future<U>(error: e)
            }
        }
        let future = Future<U>()
        addCallback { result in
            switch result {
            case .success(let t):
                let u = t[keyPath: keyPath]
                future.setResult(.success(u))
            case .failure(let e):
                future.setResult(.failure(e))
            }
        }
        return future
    }

    @inlinable
    public func flatMap<U>(_ keyPath: KeyPath<T, Future<U>>) -> Future<U> {
        if let result = result {
            switch result {
            case .success(let t):
                return t[keyPath: keyPath]
            case .failure(let e):
                return Future<U>(error: e)
            }
        }
        let future = Future<U>()
        addCallback { result in
            switch result {
            case .success(let t):
                let newFuture = t[keyPath: keyPath]
                newFuture.addCallback { future.setResult($0) }
            case .failure(let e):
                future.setResult(.failure(e))
            }
        }
        return future
    }
}

extension Future {

    @inlinable
    @discardableResult
    public func `do`(_ body: @escaping (T) -> Void) -> Future {
        addCallback { result in
            if case .success(let t) = result { body(t) }
        }
        return self
    }

    @inlinable
    @discardableResult
    public func `catch`(_ body: @escaping (Error) -> Void) -> Future {
        addCallback { result in
            if case .failure(let e) = result { body(e) }
        }
        return self
    }

    @inlinable
    @discardableResult
    public func result(_ body: @escaping (Result<T, Error>) -> Void) -> Future {
        addCallback { body($0) }
        return self
    }

    @inlinable
    @discardableResult
    public func then(_ body: @escaping () -> Void) -> Future {
        addCallback { _ in body() }
        return self
    }
}

extension Future {

    @inlinable
    func _append<U>(_ future: Future<U>) -> Future<(T, U)> {
        var tOrU: Any?
        if let result = result {
            switch result {
            case .success(let t):
                tOrU = t
            case .failure(let e):
                return Future<(T, U)>(error: e)
            }
        }
        if let result = future.result {
            switch result {
            case .success(let u):
                if let t = tOrU as? T {
                    return Future<(T, U)>((t, u))
                } else {
                    tOrU = u
                }
            case .failure(let e):
                return Future<(T, U)>(error: e)
            }
        }
        let semaphore = DispatchSemaphore(value: 1)
        let newFuture = Future<(T, U)>()
        addCallback { result in
            switch result {
            case .success(let t):
                semaphore.wait()
                defer { semaphore.signal() }
                if let u = tOrU as? U {
                    newFuture.setResult(.success((t, u)))
                } else {
                    tOrU = t
                }
            case .failure(let e):
                newFuture.setResult(.failure(e))
            }
        }
        future.addCallback { result in
            switch result {
            case .success(let u):
                semaphore.wait()
                defer { semaphore.signal() }
                if let t = tOrU as? T {
                    newFuture.setResult(.success((t, u)))
                } else {
                    tOrU = u
                }
            case .failure(let e):
                newFuture.setResult(.failure(e))
            }
        }
        return newFuture
    }

    @inlinable
    public func append<U>(_ future: Future<U>) -> Future<(T, U)> {
        return _append(future)
    }

    @inlinable
    public func append<A, B, U>(_ future: Future<U>) -> Future<(A, B, U)> where T == (A, B) {
        return _append(future).map { t, u in (t.0, t.1, u) }
    }

    @inlinable
    public func append<A, B, C, U>(_ future: Future<U>) -> Future<(A, B, C, U)> where T == (A, B, C) {
        return _append(future).map { t, u in (t.0, t.1, t.2, u) }
    }

    @inlinable
    public func append<A, B, C, D, U>(_ future: Future<U>) -> Future<(A, B, C, D, U)> where T == (A, B, C, D) {
        return _append(future).map { t, u in (t.0, t.1, t.2, t.3, u) }
    }

    @inlinable
    public func append<A, B, C, D, E, U>(_ future: Future<U>) -> Future<(A, B, C, D, E, U)> where T == (A, B, C, D, E) {
        return _append(future).map { t, u in (t.0, t.1, t.2, t.3, t.4, u) }
    }
}

extension Future {

    @inlinable
    public func append<U>(_ value: U) -> Future<(T, U)> {
        return map { t in (t, value) }
    }

    @inlinable
    public func append<A, B, U>(_ value: U) -> Future<(A, B, U)> where T == (A, B) {
        return map { t in (t.0, t.1, value) }
    }

    @inlinable
    public func append<A, B, C, U>(_ value: U) -> Future<(A, B, C, U)> where T == (A, B, C) {
        return map { t in (t.0, t.1, t.2, value) }
    }

    @inlinable
    public func append<A, B, C, D, U>(_ value: U) -> Future<(A, B, C, D, U)> where T == (A, B, C, D) {
        return map { t in (t.0, t.1, t.2, t.3, value) }
    }

    @inlinable
    public func append<A, B, C, D, E, U>(_ value: U) -> Future<(A, B, C, D, E, U)> where T == (A, B, C, D, E) {
        return map { t in (t.0, t.1, t.2, t.3, t.4, value) }
    }
}

extension Future {

    @inlinable
    public func prepend<S>(_ future: Future<S>) -> Future<(S, T)> {
        return future._append(self)
    }

    @inlinable
    public func prepend<S, A, B>(_ future: Future<S>) -> Future<(S, A, B)> where T == (A, B) {
        return future._append(self).map { s, t in (s, t.0, t.1) }
    }

    @inlinable
    public func prepend<S, A, B, C>(_ future: Future<S>) -> Future<(S, A, B, C)> where T == (A, B, C) {
        return future._append(self).map { s, t in (s, t.0, t.1, t.2) }
    }

    @inlinable
    public func prepend<S, A, B, C, D>(_ future: Future<S>) -> Future<(S, A, B, C, D)> where T == (A, B, C, D) {
        return future._append(self).map { s, t in (s, t.0, t.1, t.2, t.3) }
    }

    @inlinable
    public func prepend<S, A, B, C, D, E>(_ future: Future<S>) -> Future<(S, A, B, C, D, E)> where T == (A, B, C, D, E) {
        return future._append(self).map { s, t in (s, t.0, t.1, t.2, t.3, t.4) }
    }
}

extension Future {

    @inlinable
    public func prepend<S>(_ value: S) -> Future<(S, T)> {
        return map { t in (value, t) }
    }

    @inlinable
    public func prepend<S, A, B>(_ value: S) -> Future<(S, A, B)> where T == (A, B) {
        return map { t in (value, t.0, t.1) }
    }

    @inlinable
    public func prepend<S, A, B, C>(_ value: S) -> Future<(S, A, B, C)> where T == (A, B, C) {
        return map { t in (value, t.0, t.1, t.2) }
    }

    @inlinable
    public func prepend<S, A, B, C, D>(_ value: S) -> Future<(S, A, B, C, D)> where T == (A, B, C, D) {
        return map { t in (value, t.0, t.1, t.2, t.3) }
    }

    @inlinable
    public func prepend<S, A, B, C, D, E>(_ value: S) -> Future<(S, A, B, C, D, E)> where T == (A, B, C, D, E) {
        return map { t in (value, t.0, t.1, t.2, t.3, t.4) }
    }
}

public struct Promise<T> {

    public let future = Future<T>()

    @inlinable
    public init() {}

    @inlinable
    public func succeed(with value: T) {
        future.setResult(.success(value))
    }

    @inlinable
    public func fail(with error: Error) {
        future.setResult(.failure(error))
    }
}
