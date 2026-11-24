import Testing
@testable import DeslopCore

@Suite("Text and circles")
struct TextTests {
    @Test("a name without its generic arguments")
    func withoutGenerics() {
        #expect(Text.withoutGenerics("<Vec<T> as From<(A, B)>>::from") == "<Vec as From>::from")
        #expect(Text.withoutGenerics("Ready::new") == "Ready::new")
    }

    @Test("the circle drawn is the shortest through the first tie of the cheapest")
    func shortestCircle() {
        let ring = [("a", "b"), ("b", "c"), ("c", "a")].map { (user: $0.0, used: $0.1) }
        #expect(CircleReport.shortestCircle(ring) == [0, 1, 2])
        let chord = [("a", "b"), ("b", "c"), ("c", "a"), ("b", "a")].map { (user: $0.0, used: $0.1) }
        #expect(CircleReport.shortestCircle(chord) == [0, 3])
        let twoWays = [("a", "b"), ("b", "d"), ("b", "c"), ("c", "a"), ("d", "a")].map { (user: $0.0, used: $0.1) }
        #expect(CircleReport.shortestCircle(twoWays) == [0, 1, 4])
    }

    @Test("names under one name are written once")
    func grouped() {
        #expect(Text.grouped(["LIMIT"], separator: "::") == "LIMIT")
        #expect(Text.grouped(["Stream::new"], separator: "::") == "Stream::new")
        #expect(
            Text.grouped(["Stream", "LIMIT", "Stream::new", "Stream::Kind::Ready"], separator: "::")
                == "Stream::{self, new, Kind::Ready}, LIMIT"
        )
        #expect(Text.grouped(["Stream", "Stream.init(backlog:)"], separator: ".") == "Stream.{self, init(backlog:)}")
    }
}
