import SwiftUI

enum OpenClawStyle {
    enum CornerRadius {
        static let panel: CGFloat = 18
        static let card: CGFloat = 18
        static let insetCard: CGFloat = 16
    }

    enum Stroke {
        static let light = Color.black.opacity(0.05)
        static let dark = Color.white.opacity(0.14)
    }

    enum Shadow {
        static let primary = Color.black.opacity(0.07)
        static let contact = Color.black.opacity(0.03)
        static let primaryRadius: CGFloat = 10
        static let primaryY: CGFloat = 6
        static let contactRadius: CGFloat = 4
        static let contactY: CGFloat = 3

        static let inputPrimary = Color.black.opacity(0.10)
        static let inputContact = Color.black.opacity(0.04)
        static let inputPrimaryRadius: CGFloat = 14
        static let inputPrimaryY: CGFloat = 8
        static let inputContactRadius: CGFloat = 6
        static let inputContactY: CGFloat = 4
    }

    enum Typography {
        static let title = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 12, weight: .medium, design: .rounded)
        static let caption = Font.system(size: 11, weight: .medium, design: .rounded)
        static let captionStrong = Font.system(size: 11, weight: .semibold, design: .rounded)
    }
}

extension View {
    func openClawSurface(
        cornerRadius: CGFloat = OpenClawStyle.CornerRadius.card,
        usesDarkStroke: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(usesDarkStroke ? OpenClawStyle.Stroke.dark : OpenClawStyle.Stroke.light, lineWidth: 1)
                }
        )
        .openClawDirectionalShadow(cornerRadius: cornerRadius)
    }

    func openClawFloatingSurface(
        cornerRadius: CGFloat = OpenClawStyle.CornerRadius.panel,
        includeStroke: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    if includeStroke {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(OpenClawStyle.Stroke.light.opacity(0.55), lineWidth: 1)
                    }
                }
        )
        .openClawDirectionalShadow(cornerRadius: cornerRadius)
    }

    func openClawChatSurface(
        cornerRadius: CGFloat = 14,
        includeShadow: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).gradient)
        )
        .openClawChatShadow(includeShadow)
    }

    func openClawDirectionalShadow(
        cornerRadius: CGFloat = OpenClawStyle.CornerRadius.card,
        primary: Color = OpenClawStyle.Shadow.primary,
        primaryRadius: CGFloat = OpenClawStyle.Shadow.primaryRadius,
        primaryY: CGFloat = OpenClawStyle.Shadow.primaryY,
        contact: Color = OpenClawStyle.Shadow.contact,
        contactRadius: CGFloat = OpenClawStyle.Shadow.contactRadius,
        contactY: CGFloat = OpenClawStyle.Shadow.contactY
    ) -> some View {
        background(
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .openClawRawShadow(
                        primary: primary,
                        primaryRadius: primaryRadius,
                        primaryY: primaryY,
                        contact: contact,
                        contactRadius: contactRadius,
                        contactY: contactY
                    )
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: geo.size.height * 0.45)
                            Rectangle()
                                .fill(Color.white)
                        }
                    )
            }
        )
    }

    private func openClawRawShadow(
        primary: Color,
        primaryRadius: CGFloat,
        primaryY: CGFloat,
        contact: Color,
        contactRadius: CGFloat,
        contactY: CGFloat
    ) -> some View {
        shadow(color: primary, radius: primaryRadius, x: 0, y: primaryY)
            .shadow(color: contact, radius: contactRadius, x: 0, y: contactY)
    }

    @ViewBuilder
    private func openClawChatShadow(_ includeShadow: Bool) -> some View {
        if includeShadow {
            openClawDirectionalShadow(
                cornerRadius: 14,
                primary: OpenClawStyle.Shadow.inputPrimary,
                primaryRadius: OpenClawStyle.Shadow.inputPrimaryRadius,
                primaryY: OpenClawStyle.Shadow.inputPrimaryY,
                contact: OpenClawStyle.Shadow.inputContact,
                contactRadius: OpenClawStyle.Shadow.inputContactRadius,
                contactY: OpenClawStyle.Shadow.inputContactY
            )
        } else {
            self
        }
    }
}
