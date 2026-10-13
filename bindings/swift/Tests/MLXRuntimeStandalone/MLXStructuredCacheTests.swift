import Foundation

private struct Message: Equatable {
    let role: String
    let content: String
    var hasMedia = false
}

private struct Request {
    let model: String
    let system: String?
    let tools: [String]
    let messages: [Message]
}

private struct Cache {
    let model: String
    let system: String?
    let tools: [String]
    var ledger: [Message]

    func reusablePrefix(for request: Request) -> Int? {
        guard model == request.model,
              system == request.system,
              tools == request.tools,
              !request.messages.contains(where: \.hasMedia),
              request.messages.count > ledger.count,
              request.messages.starts(with: ledger) else {
            return nil
        }
        return ledger.count
    }
}

@main
private enum MLXStructuredCacheTests {
    static func main() {
        let firstUser = Message(role: "user", content: "first")
        let firstAssistant = Message(role: "assistant", content: "answer")
        let secondUser = Message(role: "user", content: "second")
        let cache = Cache(
            model: "mlx/model",
            system: "be concise",
            tools: ["weather"],
            ledger: [firstUser, firstAssistant])

        let extensionRequest = Request(
            model: "mlx/model",
            system: "be concise",
            tools: ["weather"],
            messages: [firstUser, firstAssistant, secondUser])
        precondition(cache.reusablePrefix(for: extensionRequest) == 2)
        precondition(Array(extensionRequest.messages.dropFirst(2)) == [secondUser])

        let divergent = Request(
            model: "mlx/model",
            system: "be concise",
            tools: ["weather"],
            messages: [firstUser, Message(role: "assistant", content: "changed"), secondUser])
        precondition(cache.reusablePrefix(for: divergent) == nil)

        let changedSystem = Request(
            model: "mlx/model",
            system: "be verbose",
            tools: ["weather"],
            messages: extensionRequest.messages)
        precondition(cache.reusablePrefix(for: changedSystem) == nil)

        let changedTools = Request(
            model: "mlx/model",
            system: "be concise",
            tools: ["calendar"],
            messages: extensionRequest.messages)
        precondition(cache.reusablePrefix(for: changedTools) == nil)

        let changedModel = Request(
            model: "mlx/other",
            system: "be concise",
            tools: ["weather"],
            messages: extensionRequest.messages)
        precondition(cache.reusablePrefix(for: changedModel) == nil)

        let media = Request(
            model: "mlx/model",
            system: "be concise",
            tools: ["weather"],
            messages: extensionRequest.messages
                + [Message(role: "user", content: "image", hasMedia: true)])
        precondition(cache.reusablePrefix(for: media) == nil)

        let result =
            "MLX structured cache: extension reused; divergence/system/tools/model/media rebuilt\n"
        FileHandle.standardOutput.write(Data(result.utf8))
    }
}
