import Foundation

@main
struct MLXTextStopFilterTests {
    static func main() {
        let tool = "<tool_call>{\"tool\":\"read\",\"arguments\":{\"filePath\":\"a.txt\"}}</tool_call>"
        var raw = MLXTextStopFilter(stopStrings: [])
        var actual = ""
        for character in tool { actual += raw.process(String(character)) }
        actual += raw.finish()
        precondition(actual == tool, "commons tool frames must pass through unchanged")

        var split = MLXTextStopFilter(stopStrings: ["<end>"])
        precondition(split.process("hello<en") == "hello")
        precondition(split.process("d>ignored") == "")
        precondition(split.stopped && split.finish().isEmpty)
        precondition(split.process("more") == "")

        var partial = MLXTextStopFilter(stopStrings: ["<end>"])
        precondition(partial.process("hello<en") == "hello")
        precondition(partial.finish() == "<en", "an incomplete terminator is actual model text")

        var earliest = MLXTextStopFilter(stopStrings: ["STOP", "END"])
        precondition(earliest.process("okENDlaterSTOP") == "ok")

        var unicode = MLXTextStopFilter(stopStrings: ["🛑終", ""])
        precondition(unicode.process("hi🛑") == "hi")
        precondition(unicode.process("終tail") == "")
        precondition(unicode.stopped)
        print("MLX text stop filter: 5 regression cases passed")
    }
}
