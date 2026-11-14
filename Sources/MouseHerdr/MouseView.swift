import SwiftUI

enum Palette {
    static let accent = Color(red: 1.0, green: 0.47, blue: 0.33)
    static let accentSoft = Color(red: 1.0, green: 0.47, blue: 0.33).opacity(0.16)
}

/// A mouse's body as its profile draws it: shadow, thumb rest, body, seams and ball. No controls.
struct MouseBodyView: View {
    let art: MouseArt
    /// Small pictures do without the shadows.
    var shadows = true
    /// Small pictures get a line around the mouse, this thick on the canvas, so a black mouse
    /// shows on a dark panel and a white one on a light panel.
    var outline: CGFloat? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let finish = art.finish
        ZStack(alignment: .topLeading) {
            if shadows {
                // soft floor shadow
                Ellipse()
                    .fill(Color.black.opacity(scheme == .dark ? 0.45 : 0.16))
                    .frame(width: art.shadow.width, height: art.shadow.height)
                    .blur(radius: 22)
                    .position(x: art.shadow.midX, y: art.shadow.midY)
            }

            if let wing = art.wing {
                wing.fill(LinearGradient(colors: finish.wing, startPoint: .top, endPoint: .bottom))
                wing.stroke(finish.isLight ? Color.black.opacity(0.16) : Color.white.opacity(0.07), lineWidth: 1)
            }

            art.body
                .fill(LinearGradient(colors: finish.body, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(shadows ? 0.28 : 0), radius: 14, y: 8)
            art.body
                .fill(RadialGradient(colors: [Color.white.opacity(finish.isLight ? 0.55 : 0.13), .clear],
                                     center: UnitPoint(x: 0.42, y: 0.2), startRadius: 4, endRadius: 190))
            art.body.stroke(finish.edge, lineWidth: 1)
            if let outline { art.body.stroke(Color.primary.opacity(0.34), lineWidth: outline) }
            art.seams.stroke(finish.seam, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            if let ball = art.ball {
                if art.ring {
                    // The scroll ring around a finger trackball's ball.
                    Circle().stroke(Color.black.opacity(0.42), lineWidth: 11)
                        .frame(width: ball.width + 22, height: ball.height + 22)
                        .position(x: ball.midX, y: ball.midY)
                    Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .frame(width: ball.width + 34, height: ball.height + 34)
                        .position(x: ball.midX, y: ball.midY)
                }
                ZStack {
                    Circle().fill(art.ballColor)
                    Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.38)],
                                                 center: .center, startRadius: ball.width * 0.28, endRadius: ball.width * 0.52))
                    Circle().fill(RadialGradient(colors: [Color.white.opacity(0.62), .clear],
                                                 center: UnitPoint(x: 0.34, y: 0.28), startRadius: 1, endRadius: ball.width * 0.42))
                    Circle().stroke(Color.black.opacity(0.4), lineWidth: 1)
                }
                .frame(width: ball.width, height: ball.height)
                .position(x: ball.midX, y: ball.midY)
            }
        }
    }
}

/// One control drawn on the body.
struct MousePart: View {
    let control: MouseControl
    let finish: Finish
    var selected = false

    var body: some View {
        let r = control.rect
        let on = selected
        Group {
            if control.virtual {
                // Not a real button: an outline where a middle click would be.
                Capsule().fill(on ? Palette.accent.opacity(0.30) : Color.clear)
                    .overlay(Capsule().stroke(on ? Palette.accent : finish.part,
                                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
            } else {
                switch control.shape {
                case .wheel:
                    ridged(r, fill: on ? Palette.accent : finish.part)
                case .pad(let tilt):
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(on ? Palette.accent : finish.pad)
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(finish.isLight && !on ? Color.black.opacity(0.18) : Color.white.opacity(on ? 0.5 : 0.14), lineWidth: 1))
                        .frame(width: r.width, height: r.height)
                        .rotationEffect(.degrees(tilt))
                        .position(x: r.midX, y: r.midY)
                case .button:
                    Capsule().fill(on ? Palette.accent : finish.part)
                        .overlay(Capsule().stroke(Color.black.opacity(0.35), lineWidth: 0.8))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
        }
        .shadow(color: on ? Palette.accent.opacity(0.75) : .clear, radius: 9)
    }

    private func ridged(_ r: CGRect, fill: Color) -> some View {
        ZStack {
            Capsule().fill(fill)
            VStack(spacing: 3) {
                ForEach(0..<Int(r.height / 6), id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.28)).frame(height: 1.2)
                }
            }
            .padding(.horizontal, 2)
            .clipShape(Capsule())
        }
        .frame(width: r.width, height: r.height)
        .position(x: r.midX, y: r.midY)
    }
}

/// The picture of the mouse being followed, drawn from its profile, with a label for each control.
struct MouseView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            MouseBodyView(art: art)
            ForEach(state.profile.controls) { control in leader(control) }
            ForEach(state.profile.controls) { control in part(control) }
            ForEach(state.profile.controls) { control in chip(control) }
        }
        .frame(width: art.size.width, height: art.size.height)
    }

    private var art: MouseArt { state.profile.art }

    // MARK: Pieces

    private func isSelected(_ slot: Slot) -> Bool { state.selected == slot }

    private func part(_ control: MouseControl) -> some View {
        let slot = control.slot
        let r = control.rect
        let on = isSelected(slot)
        return MousePart(control: control, finish: art.finish, selected: on)
            .contentShape(Rectangle().size(width: 0, height: 0))
            .overlay(
                Rectangle().fill(Color.white.opacity(0.001))
                    .frame(width: r.width + 14, height: r.height + 6)
                    .position(x: r.midX, y: r.midY)
                    .onTapGesture { state.selected = slot }
            )
            .animation(.easeOut(duration: 0.18), value: on)
    }

    private func leader(_ control: MouseControl) -> some View {
        let r = control.rect
        let left = control.chipOnLeft
        let from = CGPoint(x: control.chip.x + (left ? 1 : -1) * MouseArt.chipSize.width / 2, y: control.chip.y)
        let to = CGPoint(x: left ? r.minX - 3 : r.maxX + 3, y: r.midY)
        let on = isSelected(control.slot)
        var p = Path()
        p.move(to: from)
        let elbow = CGPoint(x: from.x + (left ? 18 : -18), y: from.y)
        p.addLine(to: elbow)
        p.addLine(to: to)
        return ZStack {
            p.stroke(on ? Palette.accent : Color.primary.opacity(0.22),
                     style: StrokeStyle(lineWidth: on ? 1.6 : 1, lineCap: .round, lineJoin: .round))
            Circle().fill(on ? Palette.accent : Color.primary.opacity(0.35))
                .frame(width: 5, height: 5).position(to)
        }
    }

    private func chip(_ control: MouseControl) -> some View {
        let slot = control.slot
        let on = isSelected(slot)
        let action = state.action(slot)
        return Button { state.selected = slot } label: {
            HStack(spacing: 9) {
                Image(systemName: Catalog.symbol(action, slot: slot))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(on ? Palette.accent : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(control.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(Catalog.title(action, slot: slot))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(width: MouseArt.chipSize.width, height: MouseArt.chipSize.height)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(on ? AnyShapeStyle(Palette.accentSoft) : AnyShapeStyle(.regularMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(on ? Palette.accent : Color.primary.opacity(0.10), lineWidth: on ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .position(control.chip)
        .animation(.easeOut(duration: 0.18), value: on)
    }
}

/// A small picture of a mouse with its controls, for lists.
struct MouseThumbnail: View {
    let profile: MouseProfile
    var size = CGSize(width: 44, height: 44)

    var body: some View {
        let art = profile.art
        let box = art.bounds.insetBy(dx: -8, dy: -8)
        let scale = min(size.width / box.width, size.height / box.height)
        ZStack(alignment: .topLeading) {
            MouseBodyView(art: art, shadows: false, outline: 1.2 / scale)
            ForEach(profile.controls) { MousePart(control: $0, finish: art.finish) }
        }
        .frame(width: art.size.width, height: art.size.height, alignment: .topLeading)
        .offset(x: -box.minX, y: -box.minY)
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: box.width * scale, height: box.height * scale, alignment: .topLeading)
        .frame(width: size.width, height: size.height)
    }
}
