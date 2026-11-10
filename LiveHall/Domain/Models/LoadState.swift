enum LoadState<Value: Sendable>: Sendable {
    case loading
    case loaded(Value)
    case failed
}
