import WebKit

/// Blocks every load that isn't a local file (or about:/data:), so the preview
/// never touches the network.
enum ContentRules {
    private static var cached: WKContentRuleList?
    private static var waiting: [(WKContentRuleList?) -> Void] = []
    private static var compiling = false

    static let json = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """

    static func load(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let cached { completion(cached); return }
        waiting.append(completion)
        guard !compiling else { return }
        compiling = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MarkedLocalOnly", encodedContentRuleList: json
        ) { list, error in
            if let error { NSLog("Marked: content rules failed to compile: \(error)") }
            cached = list
            compiling = false
            let callbacks = waiting
            waiting.removeAll()
            callbacks.forEach { $0(list) }
        }
    }
}
