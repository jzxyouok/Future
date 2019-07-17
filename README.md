# Future
## 一个常见的场景
实例化 AB 需要的参数 a、b 来自两个不同的接口：

```swift
func getA(success: (A) -> Void, failure: (Error) -> Void) {
    // 从服务器获取 A
}

func getB(success: (B) -> Void, failure: (Error) -> Void) {
    // 从服务器获取 B
}

struct AB {
    let a: A
    let b: B
}

func `do`(with ab: AB) {
    // ...
}
```
要调用 `do` 方法：

```swift
var aOrB: Any?
let semaphore = DispatchSemaphore(value: 1)
getA(success: { a in
    semaphore.wait()
    defer { semaphore.signal() }
    if let b = aOrB as? B {
        let ab = AB(a: a, b: b)
        self.do(with: ab)
    } else {
        aOrB = a
    }
}, failure: { error in
    // 处理错误
})

getB(success: { b in
    semaphore.wait()
    defer { semaphore.signal() }
    if let a = aOrB as? A {
        let ab = AB(a: a, b: b)
        self.do(with: ab)
    } else {
        aOrB = b
    }
}, failure: { error in
    // 处理错误
})
```
## 使用 `Future`

先把异步方法 `getA`、`getB` 转换成同步方法 `getFutureA`、`getFutureB`：

```swift
func getFutureA() -> Future<A> {
    let promise = Promise<A>()
    getA(success: promise.succeed, failure: promise.fail)
    return promise.future
}

func getFutureB() -> Future<B> {
    let promise = Promise<B>()
    getB(success: promise.succeed, failure: promise.fail)
    return promise.future
}
```
再函数式地调用：

```swift
getFutureA().append(getFutureB()).map(AB.init).do(self.do).catch { error in
    // 处理错误
}
```