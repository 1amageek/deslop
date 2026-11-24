/// What builds a model: a frontend for a language, or a model file one wrote.
public protocol ModelSource {
    associatedtype Failure: Error
    func model() throws(Failure) -> Model
}
