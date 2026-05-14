import SwiftUI

struct MessagePresentationView: View {
    let presentation: MessagePresentationModel
    let baseFont: Font
    let foregroundColor: Color
    let secondaryColor: Color
    let linkColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(presentation.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MessagePresentationBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            renderedMarkdownText(text)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .foregroundStyle(foregroundColor)

        case .paragraph(let text):
            renderedMarkdownText(text)
                .font(baseFont)
                .foregroundStyle(foregroundColor)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(secondaryColor.opacity(0.45))
                    .frame(width: 4)

                renderedMarkdownText(text)
                    .font(baseFont)
                    .foregroundStyle(foregroundColor.opacity(0.92))
            }

        case .listItem(let marker, let depth, let text):
            HStack(alignment: .top, spacing: 8) {
                Text(marker)
                    .font(baseFont.weight(.semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 22, alignment: .leading)

                renderedMarkdownText(text)
                    .font(baseFont)
                    .foregroundStyle(foregroundColor)
            }
            .padding(.leading, CGFloat(depth) * 14)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(secondaryColor)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(foregroundColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(secondaryColor.opacity(0.12))
            )

        case .divider:
            Rectangle()
                .fill(secondaryColor.opacity(0.22))
                .frame(height: 1)
                .padding(.vertical, 2)

        case .placeholder(let kind):
            RichContentPlaceholderView(
                kind: kind,
                feishuURL: presentation.feishuURL,
                foregroundColor: foregroundColor,
                secondaryColor: secondaryColor,
                linkColor: linkColor
            )
        }
    }

    private func renderedMarkdownText(_ text: String) -> Text {
        let attributed = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(MessagePresentationParser.plainText(fromMarkdown: text))
        return Text(attributed)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            .system(size: 18, weight: .semibold)
        case 2:
            .system(size: 16, weight: .semibold)
        case 3:
            .system(size: 15, weight: .semibold)
        default:
            .system(size: 14, weight: .semibold)
        }
    }
}

private struct RichContentPlaceholderView: View {
    let kind: MessageRichContentKind
    let feishuURL: URL?
    let foregroundColor: Color
    let secondaryColor: Color
    let linkColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(linkColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(foregroundColor)

                    Text(kind.description)
                        .font(.caption)
                        .foregroundStyle(secondaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let feishuURL {
                Link("在飞书查看", destination: feishuURL)
                    .font(.caption)
                    .foregroundStyle(linkColor)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(secondaryColor.opacity(0.08))
        )
    }
}
