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
        precondition(split.process("d>ignored").isEmpty)
        precondition(split.stopped && split.finish().isEmpty)
        precondition(split.process("more").isEmpty)

        var partial = MLXTextStopFilter(stopStrings: ["<end>"])
        precondition(partial.process("hello<en") == "hello")
        precondition(partial.finish() == "<en", "an incomplete terminator is actual model text")

        var earliest = MLXTextStopFilter(stopStrings: ["STOP", "END"])
        precondition(earliest.process("okENDlaterSTOP") == "ok")

        var unicode = MLXTextStopFilter(stopStrings: ["🛑終", ""])
        precondition(unicode.process("hi🛑") == "hi")
        precondition(unicode.process("終tail").isEmpty)
        precondition(unicode.stopped)
        // Token boundaries may occur anywhere in a textual terminator. Every
        // split must preserve the complete commons tool frame and stop before
        // trailing model text reaches the ABI callback.
        let generated = tool + "<end>discarded"
        for boundary in 0...generated.count {
            let index = generated.index(generated.startIndex, offsetBy: boundary)
            var filter = MLXTextStopFilter(stopStrings: ["<end>"])
            let first = filter.process(String(generated[..<index]))
            let second = filter.process(String(generated[index...]))
            precondition(first + second + filter.finish() == tool)
            precondition(filter.stopped)
        }

        var overlap = MLXTextStopFilter(stopStrings: ["ABAB", "BABA"])
        precondition(overlap.process("textABA") == "text")
        precondition(overlap.process("BABAtail").isEmpty)
        precondition(overlap.stopped && overlap.finish().isEmpty)

        var falsePrefix = MLXTextStopFilter(stopStrings: ["<end>"])
        precondition(falsePrefix.process("safe<en") == "safe")
        precondition(falsePrefix.process("ough>") == "<enough>")
        precondition(!falsePrefix.stopped && falsePrefix.finish().isEmpty)

        let decomposedStop = "e\u{301}X"
        let decomposed = "safe" + decomposedStop + "tail"
        for boundary in 0...decomposed.unicodeScalars.count {
            let index = decomposed.unicodeScalars.index(
                decomposed.unicodeScalars.startIndex,
                offsetBy: boundary
            )
            var filter = MLXTextStopFilter(stopStrings: [decomposedStop])
            let first = filter.process(String(decomposed.unicodeScalars[..<index]))
            let second = filter.process(String(decomposed.unicodeScalars[index...]))
            precondition(first + second + filter.finish() == "safe")
            precondition(filter.stopped)
        }

        let result =
            "MLX text stop filter: 9 regression cases passed (including every scalar boundary)\n"
        FileHandle.standardOutput.write(Data(result.utf8))
    }
}
