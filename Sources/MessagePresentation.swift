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
    case table(headers: [String], rows: [[String]])
    case remoteImage(messageID: String, imageKey: String, fallbackText: String?)
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
        case .table(let headers, let rows):
            let headerText = headers.joined(separator: " / ")
            let firstRowText = rows.first?.joined(separator: " / ") ?? ""
            return [headerText, firstRowText]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        case .remoteImage(_, _, let fallbackText):
            return fallbackText?.isEmpty == false ? fallbackText! : MessageRichContentKind.image.summaryText
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

struct MessageRemoteImageReference: Hashable {
    let messageID: String
    let imageKey: String
}

struct MessagePresentationModel: Equatable {
    let blocks: [MessagePresentationBlock]
    let summaryText: String
    let feishuURL: URL?

    static let empty = MessagePresentationModel(blocks: [], summaryText: "", feishuURL: nil)

    var hasVisibleContent: Bool {
        !blocks.isEmpty && !summaryText.isEmpty
    }

    var remoteImages: [MessageRemoteImageReference] {
        var uniqueImages = Set<MessageRemoteImageReference>()
        var images: [MessageRemoteImageReference] = []
        for block in blocks {
            guard case .remoteImage(let messageID, let imageKey, _) = block else {
                continue
            }
            let image = MessageRemoteImageReference(messageID: messageID, imageKey: imageKey)
            if uniqueImages.insert(image).inserted {
                images.append(image)
            }
        }
        return images
    }
}

enum MessagePresentationParser {
    static func parse(
        rawText: String,
        targetChatID: String? = nil,
        leadingQuoteText: String? = nil,
        sourceMessageID: String? = nil
    ) -> MessagePresentationModel {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .empty
        }

        if let structuredModel = parseStructuredPayload(
            from: trimmed,
            targetChatID: targetChatID,
            leadingQuoteText: leadingQuoteText,
            sourceMessageID: sourceMessageID
        ) {
            return structuredModel
        }

        return buildModel(
            from: quoteBlocks(from: leadingQuoteText) + parseMarkdownBlocks(from: trimmed),
            targetChatID: nil
        )
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
            (#"_([^_]+)_"#, "$1"),
            (#"~~([^~]+)~~"#, "$1")
        ]

        for (pattern, template) in replacements {
            result = replacingMatches(in: result, pattern: pattern, template: template)
        }

        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseStructuredPayload(
        from text: String,
        targetChatID: String?,
        leadingQuoteText: String?,
        sourceMessageID: String?
    ) -> MessagePresentationModel? {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        return parseStructuredObject(
            object,
            targetChatID: targetChatID,
            leadingQuoteText: leadingQuoteText,
            sourceMessageID: sourceMessageID
        )
    }

    private static func parseStructuredObject(
        _ object: Any,
        targetChatID: String?,
        leadingQuoteText: String?,
        sourceMessageID: String?
    ) -> MessagePresentationModel? {
        if let string = object as? String {
            return parse(
                rawText: string,
                targetChatID: targetChatID,
                leadingQuoteText: leadingQuoteText,
                sourceMessageID: sourceMessageID
            )
        }

        if let dictionary = object as? [String: Any] {
            return parseStructuredDictionary(
                dictionary,
                targetChatID: targetChatID,
                leadingQuoteText: leadingQuoteText,
                sourceMessageID: sourceMessageID
            )
        }

        if let paragraphs = object as? [Any] {
            let blocks = parseRichTextParagraphs(from: paragraphs, sourceMessageID: sourceMessageID)
            guard !blocks.isEmpty else {
                return nil
            }
            return buildModel(from: quoteBlocks(from: leadingQuoteText) + blocks, targetChatID: targetChatID)
        }

        return nil
    }

    private static func parseStructuredDictionary(
        _ dictionary: [String: Any],
        targetChatID: String?,
        leadingQuoteText: String?,
        sourceMessageID: String?
    ) -> MessagePresentationModel? {
        let quoteText = firstNonEmptyString(
            from: [
                leadingQuoteText,
                dictionary["quote_text"] as? String,
                dictionary["reply_to_text"] as? String
            ]
        )

        if let plainText = dictionary["text"] as? String {
            return buildModel(
                from: quoteBlocks(from: quoteText) + parseMarkdownBlocks(from: plainText),
                targetChatID: nil
            )
        }

        if let content = dictionary["content"] as? String, content != dictionary["text"] as? String {
            let nested = parse(
                rawText: content,
                targetChatID: targetChatID,
                leadingQuoteText: quoteText,
                sourceMessageID: sourceMessageID
            )
            if nested.hasVisibleContent {
                return nested
            }
        }

        if let payload = richTextPayload(from: dictionary) {
            let blocks = parseRichTextPayload(payload, sourceMessageID: sourceMessageID)
            if !blocks.isEmpty {
                return buildModel(from: quoteBlocks(from: quoteText) + blocks, targetChatID: targetChatID)
            }
        }

        let extractedBlocks = parseGenericRichContent(from: dictionary, sourceMessageID: sourceMessageID)
        if !extractedBlocks.isEmpty {
            return buildModel(
                from: quoteBlocks(from: quoteText) + extractedBlocks,
                targetChatID: targetChatID
            )
        }

        let recoveredText = deepTextString(from: dictionary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !recoveredText.isEmpty {
            return buildModel(
                from: quoteBlocks(from: quoteText) + parseMarkdownBlocks(from: recoveredText),
                targetChatID: targetChatID
            )
        }

        if let kind = placeholderKind(from: dictionary) {
            return buildModel(
                from: quoteBlocks(from: quoteText) + [.placeholder(kind: kind)],
                targetChatID: targetChatID
            )
        }

        guard !dictionary.isEmpty else {
            return nil
        }

        return buildModel(
            from: quoteBlocks(from: quoteText) + [.placeholder(kind: .unknown)],
            targetChatID: targetChatID
        )
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

    private static func parseRichTextPayload(
        _ payload: [String: Any],
        sourceMessageID: String?
    ) -> [MessagePresentationBlock] {
        var blocks: [MessagePresentationBlock] = []

        if let title = payload["title"] as? String {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                blocks.append(.heading(level: 1, text: trimmedTitle))
            }
        }

        if let paragraphs = payload["content"] as? [Any] {
            blocks.append(contentsOf: parseRichTextParagraphs(from: paragraphs, sourceMessageID: sourceMessageID))
        }

        if let paragraphs = payload["elements"] as? [Any] {
            blocks.append(contentsOf: parseRichTextParagraphs(from: paragraphs, sourceMessageID: sourceMessageID))
        }

        return blocks
    }

    private static func parseRichTextParagraphs(
        from paragraphs: [Any],
        sourceMessageID: String?
    ) -> [MessagePresentationBlock] {
        paragraphs.flatMap { paragraph -> [MessagePresentationBlock] in
            guard let elements = paragraph as? [Any] else {
                return []
            }
            return parseRichTextParagraph(elements, sourceMessageID: sourceMessageID)
        }
    }

    private static func parseRichTextParagraph(
        _ elements: [Any],
        sourceMessageID: String?
    ) -> [MessagePresentationBlock] {
        var blocks: [MessagePresentationBlock] = []
        var inlineParts: [String] = []

        func appendInlineBlock(_ text: String) {
            let inlineText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inlineText.isEmpty else {
                return
            }
            let parsedBlocks = parseMarkdownBlocks(from: inlineText)
            if parsedBlocks.count == 1, case .paragraph = parsedBlocks[0] {
                blocks.append(.paragraph(inlineText))
            } else {
                blocks.append(contentsOf: parsedBlocks)
            }
        }

        func flushParagraph() {
            let combined = inlineParts.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combined.isEmpty else {
                inlineParts.removeAll()
                return
            }
            appendInlineBlock(combined)
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
                    inlineParts.append(markdownText(text, styles: dictionary["style"] as? [String]))
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
                blocks.append(imageBlock(from: dictionary, sourceMessageID: sourceMessageID))
            case "media":
                flushParagraph()
                blocks.append(.placeholder(kind: .video))
            case "file":
                flushParagraph()
                blocks.append(.placeholder(kind: .attachment))
            case "sheet", "table":
                flushParagraph()
                blocks.append(contentsOf: tableBlocks(from: dictionary))
            default:
                if let text = dictionary["text"] as? String, !text.isEmpty {
                    inlineParts.append(markdownText(text, styles: dictionary["style"] as? [String]))
                } else if let nestedBlocks = nestedRichTextBlocks(
                    from: dictionary,
                    sourceMessageID: sourceMessageID
                ), !nestedBlocks.isEmpty {
                    flushParagraph()
                    blocks.append(contentsOf: nestedBlocks)
                } else {
                    let recoveredText = deepTextString(from: dictionary)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !recoveredText.isEmpty {
                        inlineParts.append(recoveredText)
                    }
                }
            }
        }

        flushParagraph()
        return blocks
    }

    private static func parseGenericRichContent(
        from dictionary: [String: Any],
        sourceMessageID: String?
    ) -> [MessagePresentationBlock] {
        if let tag = dictionary["tag"] as? String {
            let normalizedTag = tag.lowercased()
            if ["markdown", "md", "lark_md"].contains(normalizedTag) {
                return parseMarkdownBlocks(from: richTextString(from: dictionary))
            }
            if ["plain_text", "text"].contains(normalizedTag) {
                let text = richTextString(from: dictionary).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? [] : [.paragraph(text)]
            }
            if ["table", "sheet"].contains(normalizedTag) {
                return tableBlocks(from: dictionary)
            }
            if normalizedTag == "img" {
                return [imageBlock(from: dictionary, sourceMessageID: sourceMessageID)]
            }
        }

        if let nestedBlocks = nestedRichTextBlocks(from: dictionary, sourceMessageID: sourceMessageID), !nestedBlocks.isEmpty {
            return nestedBlocks
        }

        let richText = richTextString(from: dictionary).trimmingCharacters(in: .whitespacesAndNewlines)
        if !richText.isEmpty {
            return parseMarkdownBlocks(from: richText)
        }

        let recoveredText = deepTextString(from: dictionary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recoveredText.isEmpty else {
            return []
        }
        return parseMarkdownBlocks(from: recoveredText)
    }

    private static func nestedRichTextBlocks(
        from dictionary: [String: Any],
        sourceMessageID: String?
    ) -> [MessagePresentationBlock]? {
        let nestedKeys = ["elements", "children", "items", "fields"]
        for key in nestedKeys {
            if let elements = dictionary[key] as? [Any] {
                let blocks: [MessagePresentationBlock]
                if elements.allSatisfy({ $0 is [Any] }) {
                    blocks = parseRichTextParagraphs(from: elements, sourceMessageID: sourceMessageID)
                } else {
                    blocks = parseRichTextParagraph(elements, sourceMessageID: sourceMessageID)
                }
                if !blocks.isEmpty {
                    return blocks
                }
            }
        }

        if let content = dictionary["content"] as? [Any] {
            if content.allSatisfy({ $0 is [Any] }) {
                let blocks = parseRichTextParagraphs(from: content, sourceMessageID: sourceMessageID)
                if !blocks.isEmpty {
                    return blocks
                }
            }
            let blocks = parseRichTextParagraph(content, sourceMessageID: sourceMessageID)
            if !blocks.isEmpty {
                return blocks
            }
        }

        if let textObject = dictionary["text"] as? [String: Any] {
            let blocks = parseGenericRichContent(from: textObject, sourceMessageID: sourceMessageID)
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

    private static func deepTextString(from value: Any, depth: Int = 0) -> String {
        guard depth < 8 else {
            return ""
        }
        if let string = value as? String {
            return string
        }
        if let dictionary = value as? [String: Any] {
            let preferredKeys = [
                "text",
                "content",
                "plain_text",
                "markdown",
                "value",
                "title",
                "subtitle",
                "description",
                "alt"
            ]
            var parts: [String] = []
            for key in preferredKeys {
                if let nestedValue = dictionary[key] {
                    let text = deepTextString(from: nestedValue, depth: depth + 1)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        parts.append(text)
                    }
                }
            }
            for key in ["elements", "children", "items", "fields", "body"] {
                if let nestedValue = dictionary[key] {
                    let text = deepTextString(from: nestedValue, depth: depth + 1)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        parts.append(text)
                    }
                }
            }
            return parts.joined(separator: "\n")
        }
        if let array = value as? [Any] {
            return array
                .map { deepTextString(from: $0, depth: depth + 1).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        return ""
    }

    private static func markdownText(_ text: String, styles: [String]?) -> String {
        var result = text
        let normalizedStyles = Set((styles ?? []).map { $0.lowercased() })
        if normalizedStyles.contains("bold") {
            result = "**\(result)**"
        }
        if normalizedStyles.contains("italic") {
            result = "*\(result)*"
        }
        if normalizedStyles.contains("underline") {
            result = "__\(result)__"
        }
        if normalizedStyles.contains("linethrough")
            || normalizedStyles.contains("line_through")
            || normalizedStyles.contains("strikethrough")
            || normalizedStyles.contains("strike") {
            result = "~~\(result)~~"
        }
        return result
    }

    private static func imageBlock(
        from dictionary: [String: Any],
        sourceMessageID: String?
    ) -> MessagePresentationBlock {
        let imageKey = firstNonEmptyString(from: [
            dictionary["image_key"] as? String,
            dictionary["img_key"] as? String,
            dictionary["file_key"] as? String
        ])
        let fallbackText = firstNonEmptyString(from: [
            dictionary["text"] as? String,
            dictionary["fallback"] as? String,
            dictionary["alt"] as? String
        ])
        if let imageKey, let sourceMessageID {
            return .remoteImage(messageID: sourceMessageID, imageKey: imageKey, fallbackText: fallbackText)
        }
        return .placeholder(kind: .image)
    }

    private static func tableBlocks(from dictionary: [String: Any]) -> [MessagePresentationBlock] {
        guard let table = extractTable(from: dictionary) else {
            return [.placeholder(kind: .table)]
        }
        return [.table(headers: table.headers, rows: table.rows)]
    }

    private static func extractTable(from dictionary: [String: Any]) -> (headers: [String], rows: [[String]])? {
        let rowKeys = ["rows", "data", "items", "content"]
        for key in rowKeys {
            if let rows = dictionary[key] as? [[Any]],
               let table = tableFromRawRows(rows) {
                return table
            }
            if let rowDictionaries = dictionary[key] as? [[String: Any]],
               let table = tableFromDictionaries(rowDictionaries) {
                return table
            }
        }

        if let cells = dictionary["cells"] as? [Any],
           let table = tableFromRawRows([cells]) {
            return table
        }

        return nil
    }

    private static func tableFromRawRows(_ rawRows: [[Any]]) -> (headers: [String], rows: [[String]])? {
        let rows = rawRows
            .map { row in
                row.map { cellText(from: $0) }
                    .map { plainText(fromMarkdown: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { !$0.allSatisfy(\.isEmpty) }

        guard rows.count >= 2 else {
            return nil
        }
        return (headers: rows[0], rows: Array(rows.dropFirst()))
    }

    private static func tableFromDictionaries(
        _ rowDictionaries: [[String: Any]]
    ) -> (headers: [String], rows: [[String]])? {
        let orderedKeys = rowDictionaries
            .flatMap { $0.keys }
            .reduce(into: [String]()) { result, key in
                if !result.contains(key) {
                    result.append(key)
                }
            }

        guard orderedKeys.count >= 2 else {
            return nil
        }

        let rows = rowDictionaries.map { row in
            orderedKeys.map { cellText(from: row[$0] as Any) }
        }
        return (headers: orderedKeys, rows: rows)
    }

    private static func cellText(from value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let dictionary = value as? [String: Any] {
            let direct = richTextString(from: dictionary).trimmingCharacters(in: .whitespacesAndNewlines)
            if !direct.isEmpty {
                return direct
            }
            if let nested = nestedRichTextBlocks(from: dictionary, sourceMessageID: nil) {
                return nested
                    .map(\.summaryFragment)
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            return ""
        }
        if let values = value as? [Any] {
            return values
                .map { cellText(from: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return ""
    }

    private static func quoteBlocks(from quoteText: String?) -> [MessagePresentationBlock] {
        guard
            let quoteText = quoteText?.trimmingCharacters(in: .whitespacesAndNewlines),
            !quoteText.isEmpty
        else {
            return []
        }
        return [.quote(quoteText)]
    }

    private static func firstNonEmptyString(from values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
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

            if let table = parseMarkdownTable(lines: lines, startIndex: index) {
                flushParagraph()
                blocks.append(table.block)
                index = table.nextIndex
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

    private static func parseMarkdownTable(
        lines: [String],
        startIndex: Int
    ) -> (block: MessagePresentationBlock, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }

        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard
            looksLikeTableRow(headerLine),
            looksLikeTableSeparator(separatorLine)
        else {
            return nil
        }

        let headers = splitMarkdownTableRow(headerLine)
        guard !headers.isEmpty else {
            return nil
        }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let rowLine = lines[index].trimmingCharacters(in: .whitespaces)
            guard looksLikeTableRow(rowLine), !looksLikeTableSeparator(rowLine) else {
                break
            }
            let row = splitMarkdownTableRow(rowLine)
            if !row.isEmpty {
                rows.append(row)
            }
            index += 1
        }

        guard !rows.isEmpty else {
            return nil
        }
        return (.table(headers: headers, rows: rows), index)
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        line.contains("|") && splitMarkdownTableRow(line).count >= 2
    }

    private static func looksLikeTableSeparator(_ line: String) -> Bool {
        let cells = splitMarkdownTableRow(line)
        guard cells.count >= 2 else {
            return false
        }
        return cells.allSatisfy { cell in
            let normalized = cell.trimmingCharacters(in: .whitespaces)
            guard normalized.count >= 3 else {
                return false
            }
            return normalized.allSatisfy { character in
                character == "-" || character == ":" || character.isWhitespace
            }
        }
    }

    private static func splitMarkdownTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { plainText(fromMarkdown: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
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
