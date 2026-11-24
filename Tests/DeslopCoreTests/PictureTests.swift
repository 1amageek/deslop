import Testing
@testable import DeslopCore

@Suite("pictures")
struct PictureTests {
    private func plain(_ picture: Picture) -> [String] {
        PictureDrawer(paint: Paint(colored: false)).draw(picture)
    }

    private func step(_ member: String, _ file: String, _ line: Int, _ uses: String) -> Step {
        Step(member: member, site: Location(file: file, line: line), uses: uses)
    }

    @Test("a circle runs down its ties and back up from the last")
    func circle() {
        let picture = Picture.circle(
            steps: [
                step("kinds", "src/kinds.rs", 10, "Stream::new uses BACKLOG_MOST"),
                step("socket", "src/net/socket.rs", 5, "listen uses Stream"),
            ],
            rest: "not drawn: 1 more module"
        )
        #expect(plain(picture) == [
            "    ┌─▶ kinds",
            "    │     ┃ kinds.rs:10      Stream::new uses BACKLOG_MOST",
            "    │     ▼",
            "    │   socket",
            "    │     │ net/socket.rs:5  listen uses Stream",
            "    └─────┘",
            "    not drawn: 1 more module",
        ])
    }

    @Test("a spread draws an arm from each module into the field")
    func spread() {
        func spread(_ modules: [Picture.Spread]) -> Picture {
            .spread(owner: "q::RunQueue", field: "items", modules: modules, others: ["kept: limit"])
        }
        #expect(plain(spread([Picture.Spread(places: 1, module: "q::app")])) == [
            "    q::RunQueue",
            "      items ◀━━━ 1  q::app",
            "      kept: limit",
        ])
        let modules = [
            Picture.Spread(places: 12, module: "q::sched"),
            Picture.Spread(places: 3, module: "q::app"),
            Picture.Spread(places: 2, module: "in 2 more modules"),
        ]
        #expect(plain(spread(modules)) == [
            "    q::RunQueue",
            "      items ◀━┳━ 12  q::sched",
            "              ┣━  3  q::app",
            "              ┗━  2  in 2 more modules",
            "      kept: limit",
        ])
    }

    @Test("a bar crosses the line at seven and ends short of eighty columns")
    func listsBars() {
        let picture = Picture.lists(shown: 50, hidden: 3, lists: [Picture.Bar(name: "Store", length: 9)])
        #expect(plain(picture) == [
            "                  7",
            "    shows  ███████│█████████████████████████████████⋯ 50",
            "    hides  ███    │ 3",
            "    Store  ███████│██ 9",
        ])
    }

    @Test("a bar against a larger most puts its line halfway along")
    func largerMost() {
        #expect(plain(.bar(label: "holds", length: 17, most: 15)) == [
            "                         15",
            "    holds  ███████████████│██ 17",
        ])
        #expect(plain(.bar(label: "lines", length: 2_001, most: 2_000)) == [
            "                            2000",
            "    lines  ████████████████████│█ 2001",
        ])
        #expect(plain(.bar(label: "lines", length: 9_000, most: 2_000)) == [
            "                            2000",
            "    lines  ████████████████████│████████████████████⋯ 9000",
        ])
    }
}
