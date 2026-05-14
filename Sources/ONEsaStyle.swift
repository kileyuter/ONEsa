import SwiftUI

enum ONEsaStyle {
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
    func onesaSurface(
        cornerRadius: CGFloat = ONEsaStyle.CornerRadius.card,
        usesDarkStroke: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(usesDarkStroke ? ONEsaStyle.Stroke.dark : ONEsaStyle.Stroke.light, lineWidth: 1)
                }
        )
        .onesaDirectionalShadow(cornerRadius: cornerRadius)
    }

    func onesaFloatingSurface(
        cornerRadius: CGFloat = ONEsaStyle.CornerRadius.panel,
        includeStroke: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    if includeStroke {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ONEsaStyle.Stroke.light.opacity(0.55), lineWidth: 1)
                    }
                }
        )
        .onesaDirectionalShadow(cornerRadius: cornerRadius)
    }

    func onesaChatSurface(
        cornerRadius: CGFloat = 14,
        includeShadow: Bool = false
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).gradient)
        )
        .onesaChatShadow(includeShadow)
    }

    func onesaDirectionalShadow(
        cornerRadius: CGFloat = ONEsaStyle.CornerRadius.card,
        primary: Color = ONEsaStyle.Shadow.primary,
        primaryRadius: CGFloat = ONEsaStyle.Shadow.primaryRadius,
        primaryY: CGFloat = ONEsaStyle.Shadow.primaryY,
        contact: Color = ONEsaStyle.Shadow.contact,
        contactRadius: CGFloat = ONEsaStyle.Shadow.contactRadius,
        contactY: CGFloat = ONEsaStyle.Shadow.contactY
    ) -> some View {
        background(
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .onesaRawShadow(
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

    private func onesaRawShadow(
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
    private func onesaChatShadow(_ includeShadow: Bool) -> some View {
        if includeShadow {
            onesaDirectionalShadow(
                cornerRadius: 14,
                primary: ONEsaStyle.Shadow.inputPrimary,
                primaryRadius: ONEsaStyle.Shadow.inputPrimaryRadius,
                primaryY: ONEsaStyle.Shadow.inputPrimaryY,
                contact: ONEsaStyle.Shadow.inputContact,
                contactRadius: ONEsaStyle.Shadow.inputContactRadius,
                contactY: ONEsaStyle.Shadow.inputContactY
            )
        } else {
            self
        }
    }
}
