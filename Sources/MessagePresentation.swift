import Foundation

enum MessageRichContentKind: String, Equatable {
    case image
    case table
    case attachment
    case video
    case unknown

    var iconName: String {
        switch self {
        case .image:
            "photo"
        case .table:
            "tablecells"
        case .attachment:
            "paperclip"
        case .video:
            "video"
        case .unknown:
            "questionmark.square.dashed"
        }
    }

    var title: String {
        switch self {
        case .image:
            "图片内容"
        case .table:
            "表格内容"
        case .attachment:
            "附件内容"
        case .video:
            "视频内容"
        case .unknown:
            "富内容"
        }
    }

    var description: String {
        switch self {
        case .image:
            "暂不支持直接渲染图片消息。"
        case .table:
            "暂不支持直接渲染表格消息。"
        case .attachment:
            "暂不支持直接渲染附件消息。"
        case .video:
            "暂不支持直接渲染视频消息。"
        case .unknown:
            "暂不支持直接渲染这类富内容消息。"
        }
    }

    var summaryText: String {
        "\(title)，请在飞书查看"
    }
}

enum MessagePresentationBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case listItem(marker: String, depth: Int, text: String)
    case codeBlock(language: String?, code: String)
    case divider
    case placeholder(kind: MessageRichContentKind)

    var summaryFragment: String {
        switch self {
        case .heading(_, let text), .paragraph(let text), .quote(let text), .listItem(_, _, let text):
            return MessagePresentationParser.plainText(fromMarkdown: text)
        case .codeBlock(_, let code):
            let firstLine = code
                .split(separator: "\n", omittingEmptySubsequences: false)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return firstLine?.isEmpty == false ? "[代码] \(firstLine!)" : "代码块"
        case .divider:
            return ""
        case .placeholder(let kind):
            return kind.summaryText
        }
    }

    var shouldRender: Bool {
        if case .divider = self {
            return true
        }
        return !summaryFragment.isEmpty
    }

    var containsPlaceholder: Bool {
        if case .placeholder = self {
            return true
        }
        return false
    }
}

struct MessagePresentationModel: Equatable {
    let blocks: [MessagePresentationBlock]
    let summaryText: String
    let feishuURL: URL?

    static let empty = MessagePresentationModel(blocks: [], summaryText: "", feishuURL: nil)

    var hasVisibleContent: Bool {
        !blocks.isEmpty && !summaryText.isEmpty
    }
}

enum MessagePresentationParser {
    static func parse(rawText: String, targetChatID: String? = nil) -> MessagePresentationModel {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }

        if let structuredModel = parseStructuredPayload(from: trimmed, targetChatID: targetChatID) {
            return structuredModel
        }

        return buildModel(from: parseMarkdownBlocks(from: trimmed), targetChatID: nil)
    }

    static func plainText(fromMarkdown text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            (#"\[([^\]]+)\]\(([^)]+)\)"#, "$1"),
            (#"`([^`]+)`"#, "$1"),
            (#"\*\*\*([^*]+)\*\*\*"#, "$1"),
            (#"\*\*([^*]+)\*\*"#, "$1"),
            (#"\*([^*]+)\*"#, "$1"),
            (#"__([^_]+)__"#, "$1"),
            (#"_([^_]+)_"#, "$1")
        ]

        for (pattern, template) in replacements {
            result = replacingMatches(in: result, pattern: pattern, template: template)
        }

        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseStructuredPayload(
        from text: String,
        targetChatID: String?
    ) -> MessagePresentationModel? {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        return parseStructuredObject(object, targetChatID: targetChatID)
    }

    private static func parseStructuredObject(
        _ object: Any,
        targetChatID: String?
    ) -> MessagePresentationModel? {
        if let string = object as? String {
            return parse(rawText: string, targetChatID: targetChatID)
        }

        if let dictionary = object as? [String: Any] {
            return parseStructuredDictionary(dictionary, targetChatID: targetChatID)
        }

        if let paragraphs = object as? [Any] {
            let blocks = parseRichTextParagraphs(from: paragraphs)
            guard !blocks.isEmpty else {
                return nil
            }
            return buildModel(from: blocks, targetChatID: targetChatID)
        }

        return nil
    }

    private static func parseStructuredDictionary(
        _ dictionary: [String: Any],
        targetChatID: String?
    ) -> MessagePresentationModel? {
        if let plainText = dictionary["text"] as? String {
            return buildModel(from: parseMarkdownBlocks(from: plainText), targetChatID: nil)
        }

        if let content = dictionary["content"] as? String, content != dictionary["text"] as? String {
            let nested = parse(rawText: content, targetChatID: targetChatID)
            if nested.hasVisibleContent {
                return nested
            }
        }

        if let payload = richTextPayload(from: dictionary) {
            let blocks = parseRichTextPayload(payload)
            if !blocks.isEmpty {
                return buildModel(from: blocks, targetChatID: targetChatID)
            }
        }

        let extractedBlocks = parseGenericRichContent(from: dictionary)
        if !extractedBlocks.isEmpty {
            return buildModel(from: extractedBlocks, targetChatID: targetChatID)
        }

        if let kind = placeholderKind(from: dictionary) {
            return buildModel(from: [.placeholder(kind: kind)], targetChatID: targetChatID)
        }

        guard !dictionary.isEmpty else {
            return nil
        }

        return buildModel(from: [.placeholder(kind: .unknown)], targetChatID: targetChatID)
    }

    private static func richTextPayload(from dictionary: [String: Any]) -> [String: Any]? {
        let preferredKeys = ["zh_cn", "zh-CN", "en_us", "en-US"]
        for key in preferredKeys {
            if let payload = dictionary[key] as? [String: Any],
               payload["content"] != nil || payload["title"] != nil {
                return payload
            }
        }

        if dictionary["content"] != nil || dictionary["title"] != nil {
            return dictionary
        }

        return dictionary.values.first {
            guard let payload = $0 as? [String: Any] else {
                return false
            }
            return payload["content"] != nil || payload["title"] != nil
        } as? [String: Any]
    }

    private static func parseRichTextPayload(_ payload: [String: Any]) -> [MessagePresentationBlock] {
        var blocks: [MessagePresentationBlock] = []

        if let title = payload["title"] as? String {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                blocks.append(.heading(level: 1, text: trimmedTitle))
            }
        }

        if let paragraphs = payload["content"] as? [Any] {
            blocks.append(contentsOf: parseRichTextParagraphs(from: paragraphs))
        }

        return blocks
    }

    private static func parseRichTextParagraphs(from paragraphs: [Any]) -> [MessagePresentationBlock] {
        paragraphs.flatMap { paragraph -> [MessagePresentationBlock] in
            guard let elements = paragraph as? [Any] else {
                return []
            }
            return parseRichTextParagraph(elements)
        }
    }

    private static func parseRichTextParagraph(_ elements: [Any]) -> [MessagePresentationBlock] {
        var blocks: [MessagePresentationBlock] = []
        var inlineParts: [String] = []

        func flushParagraph() {
            let combined = inlineParts.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combined.isEmpty else {
                inlineParts.removeAll()
                return
            }
            blocks.append(.paragraph(combined))
            inlineParts.removeAll()
        }

        for element in elements {
            guard let dictionary = element as? [String: Any] else {
                continue
            }

            let tag = (dictionary["tag"] as? String ?? "").lowercased()
            switch tag {
            case "text":
                if let text = dictionary["text"] as? String {
                    inlineParts.append(text)
                }
            case "a":
                let label = (dictionary["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = hrefString(from: dictionary)
                if let label, !label.isEmpty, let url, !url.isEmpty {
                    inlineParts.append("[\(label)](\(url))")
                } else if let label, !label.isEmpty {
                    inlineParts.append(label)
                }
            case "at":
                inlineParts.append(attributedMention(from: dictionary))
            case "emotion":
                inlineParts.append((dictionary["text"] as? String) ?? "[表情]")
            case "code_block":
                flushParagraph()
                let code = (dictionary["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let code, !code.isEmpty {
                    blocks.append(.codeBlock(language: dictionary["language"] as? String, code: code))
                }
            case "markdown", "md", "lark_md":
                flushParagraph()
                blocks.append(contentsOf: parseMarkdownBlocks(from: richTextString(from: dictionary)))
            case "hr", "divider":
                flushParagraph()
                blocks.append(.divider)
            case "quote":
                flushParagraph()
                let quoteText = richTextString(from: dictionary)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !quoteText.isEmpty {
                    blocks.append(.quote(quoteText))
                }
            case "img":
                flushParagraph()
                blocks.append(.placeholder(kind: .image))
            case "media":
                flushParagraph()
                blocks.append(.placeholder(kind: .video))
            case "file":
                flushParagraph()
                blocks.append(.placeholder(kind: .attachment))
            case "sheet", "table":
                flushParagraph()
                blocks.append(.placeholder(kind: .table))
            default:
                if let text = dictionary["text"] as? String, !text.isEmpty {
                    inlineParts.append(text)
                } else if let nestedBlocks = nestedRichTextBlocks(from: dictionary), !nestedBlocks.isEmpty {
                    flushParagraph()
                    blocks.append(contentsOf: nestedBlocks)
                } else {
                    flushParagraph()
                    blocks.append(.placeholder(kind: placeholderKind(from: dictionary) ?? .unknown))
                }
            }
        }

        flushParagraph()
        return blocks
    }

    private static func parseGenericRichContent(from dictionary: [String: Any]) -> [MessagePresentationBlock] {
        if let tag = dictionary["tag"] as? String {
            let normalizedTag = tag.lowercased()
            if ["markdown", "md", "lark_md"].contains(normalizedTag) {
                return parseMarkdownBlocks(from: richTextString(from: dictionary))
            }
            if ["plain_text", "text"].contains(normalizedTag) {
                let text = richTextString(from: dictionary).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? [] : [.paragraph(text)]
            }
        }

        if let nestedBlocks = nestedRichTextBlocks(from: dictionary), !nestedBlocks.isEmpty {
            return nestedBlocks
        }

        let richText = richTextString(from: dictionary).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !richText.isEmpty else {
            return []
        }
        return parseMarkdownBlocks(from: richText)
    }

    private static func nestedRichTextBlocks(from dictionary: [String: Any]) -> [MessagePresentationBlock]? {
        let nestedKeys = ["elements", "children", "items", "fields"]
        for key in nestedKeys {
            if let elements = dictionary[key] as? [Any] {
                let blocks = parseRichTextParagraph(elements)
                if !blocks.isEmpty {
                    return blocks
                }
            }
        }

        if let content = dictionary["content"] as? [Any] {
            if content.allSatisfy({ $0 is [Any] }) {
                let blocks = parseRichTextParagraphs(from: content)
                if !blocks.isEmpty {
                    return blocks
                }
            }
            let blocks = parseRichTextParagraph(content)
            if !blocks.isEmpty {
                return blocks
            }
        }

        if let textObject = dictionary["text"] as? [String: Any] {
            let blocks = parseGenericRichContent(from: textObject)
            if !blocks.isEmpty {
                return blocks
            }
        }

        return nil
    }

    private static func richTextString(from dictionary: [String: Any]) -> String {
        let stringKeys = ["text", "content", "plain_text", "markdown", "value"]
        for key in stringKeys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }

        if let textObject = dictionary["text"] as? [String: Any] {
            return richTextString(from: textObject)
        }
        if let contentObject = dictionary["content"] as? [String: Any] {
            return richTextString(from: contentObject)
        }
        return ""
    }

    private static func attributedMention(from dictionary: [String: Any]) -> String {
        if let userName = dictionary["user_name"] as? String, !userName.isEmpty {
            return "@\(userName)"
        }
        if let userID = dictionary["user_id"] as? String, !userID.isEmpty {
            return "@\(userID)"
        }
        return "@"
    }

    private static func hrefString(from dictionary: [String: Any]) -> String? {
        if let href = dictionary["href"] as? String, !href.isEmpty {
            return href
        }
        if let href = dictionary["default_href"] as? String, !href.isEmpty {
            return href
        }
        if let hrefDictionary = dictionary["href"] as? [String: Any] {
            if let url = hrefDictionary["url"] as? String, !url.isEmpty {
                return url
            }
            if let urlVal = hrefDictionary["urlVal"] as? [String: Any],
               let url = urlVal["url"] as? String,
               !url.isEmpty {
                return url
            }
        }
        return nil
    }

    private static func placeholderKind(from dictionary: [String: Any]) -> MessageRichContentKind? {
        let keys = Set(dictionary.keys.map { $0.lowercased() })

        if keys.contains("image_key") || keys.contains("img_key") || keys.contains("image_keys") {
            return .image
        }
        if keys.contains("file_key") || keys.contains("file_name") {
            return .attachment
        }
        if keys.contains("media_key") || keys.contains("duration") || keys.contains("video_key") {
            return .video
        }
        if keys.contains("sheet_id") || keys.contains("table_id") || keys.contains("table") {
            return .table
        }
        if let tag = dictionary["tag"] as? String {
            switch tag.lowercased() {
            case "img":
                return .image
            case "file":
                return .attachment
            case "media":
                return .video
            case "sheet", "table":
                return .table
            default:
                break
            }
        }
        return nil
    }

    private static func buildModel(
        from blocks: [MessagePresentationBlock],
        targetChatID: String?
    ) -> MessagePresentationModel {
        let sanitizedBlocks = blocks.filter(\.shouldRender)
        let summaryText = sanitizedBlocks
            .map(\.summaryFragment)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPlaceholder = sanitizedBlocks.contains(where: \.containsPlaceholder)
        return MessagePresentationModel(
            blocks: sanitizedBlocks,
            summaryText: summaryText,
            feishuURL: hasPlaceholder ? feishuURL(for: targetChatID) : nil
        )
    }

    private static func feishuURL(for targetChatID: String?) -> URL? {
        guard let targetChatID else {
            return nil
        }
        let trimmedChatID = targetChatID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatID.isEmpty else {
            return nil
        }
        var components = URLComponents(string: "https://applink.feishu.cn/client/chat/open")
        components?.queryItems = [
            URLQueryItem(name: "openChatId", value: trimmedChatID),
            URLQueryItem(name: "lk_unique", value: "true")
        ]
        return components?.url
    }

    private static func parseMarkdownBlocks(from text: String) -> [MessagePresentationBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MessagePresentationBlock] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            let paragraph = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !paragraph.isEmpty else {
                paragraphLines.removeAll()
                return
            }
            blocks.append(.paragraph(paragraph))
            paragraphLines.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if isDividerLine(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            if let heading = parseHeading(from: line) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if isQuoteLine(line) {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count, isQuoteLine(lines[index]) {
                    quoteLines.append(strippingQuotePrefix(from: lines[index]))
                    index += 1
                }
                let quoteText = quoteLines
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !quoteText.isEmpty {
                    blocks.append(.quote(quoteText))
                }
                continue
            }

            if let listItem = parseListItem(from: line) {
                flushParagraph()
                blocks.append(listItem)
                index += 1
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func isDividerLine(_ trimmedLine: String) -> Bool {
        let compact = trimmedLine.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first else {
            return false
        }
        return ["-", "*", "_"].contains(first) && compact.allSatisfy { $0 == first }
    }

    private static func parseHeading(from line: String) -> MessagePresentationBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for character in trimmed {
            guard character == "#" else { break }
            level += 1
        }
        guard (1...6).contains(level) else {
            return nil
        }
        let contentStart = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard contentStart < trimmed.endIndex, trimmed[contentStart] == " " else {
            return nil
        }
        let text = trimmed[trimmed.index(after: contentStart)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return .heading(level: level, text: text)
    }

    private static func isQuoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func strippingQuotePrefix(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else {
            return trimmed
        }
        let content = trimmed.dropFirst()
        return content.trimmingCharacters(in: .whitespaces)
    }

    private static func parseListItem(from line: String) -> MessagePresentationBlock? {
        let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let first = trimmed.first, ["-", "*", "+"].contains(first) {
            let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else {
                return nil
            }
            return .listItem(marker: "•", depth: leadingSpaces / 2, text: content)
        }

        var digits = ""
        var currentIndex = trimmed.startIndex
        while currentIndex < trimmed.endIndex, trimmed[currentIndex].isNumber {
            digits.append(trimmed[currentIndex])
            currentIndex = trimmed.index(after: currentIndex)
        }

        guard !digits.isEmpty, currentIndex < trimmed.endIndex, trimmed[currentIndex] == "." else {
            return nil
        }

        let afterPeriod = trimmed.index(after: currentIndex)
        guard afterPeriod < trimmed.endIndex, trimmed[afterPeriod] == " " else {
            return nil
        }

        let content = trimmed[trimmed.index(after: afterPeriod)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return nil
        }

        return .listItem(marker: "\(digits).", depth: leadingSpaces / 2, text: content)
    }

    private static func replacingMatches(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
