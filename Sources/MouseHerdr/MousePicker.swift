import SwiftUI

/// On the Buttons page, beside the picture: which mouse this is, and the way to change it.
struct MousePlate: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("YOUR MOUSE").font(.system(size: 9.5, weight: .semibold)).kerning(0.6).foregroundStyle(.tertiary)
            Text(state.mouseTitle).font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(state.mouseSubtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Button(state.choosingMouse ? "Done" : "Change…") {
                state.recording = false
                state.choosingMouse.toggle()
            }
            .controlSize(.small).padding(.top, 3)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(width: MouseArt.chipSize.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(state.choosingMouse ? Palette.accent : Color.primary.opacity(0.10), lineWidth: state.choosingMouse ? 1.5 : 1))
    }
}

/// Beside the Buttons page in place of a button's actions: the mice connected now, and every
/// model in the list to pick from by hand.
struct MousePickerPanel: View {
    @ObservedObject var state: AppState

    /// The models to list, by brand, narrowed by what is typed in the search field.
    static func models(matching query: String) -> [(brand: String, models: [MouseProfile])] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let all = (MouseProfile.all + MouseProfile.fallbacks).filter { p in
            guard p.kind != .receiver else { return false }      // a receiver is not a model to pick
            let text = "\(p.brand) \(p.name) \(p.id)".lowercased()
            return words.allSatisfy(text.contains)
        }
        return MouseCatalog.brands.compactMap { brand in
            let models = all.filter { $0.brand == brand }
            return models.isEmpty ? nil : (brand, models)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your mouse").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("MouseHerdr works out which mouse is connected. Pick it from the list if it got it wrong, or if the mouse hides behind a USB receiver.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("Search \(MouseProfile.all.filter { $0.kind == .mouse }.count) mice", text: $state.mouseSearch)
                        .textFieldStyle(.plain).font(.system(size: 13))
                    if !state.mouseSearch.isEmpty {
                        Button { state.mouseSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                .padding(.top, 4)
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if state.mouseSearch.isEmpty { connected }
                    let groups = Self.models(matching: state.mouseSearch)
                    if groups.isEmpty {
                        Text("No mouse like that in the list. Under “Other”, the three-button and five-button layouts fit any mouse: a wheel click and side buttons work the same on all of them.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                    }
                    ForEach(groups, id: \.brand) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            sectionTitle(group.brand)
                            ForEach(group.models) { model in
                                row(profile: model, title: model.name, detail: nil, selected: state.profile.id == model.id) {
                                    state.choose(model)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 12)
            }
        }
    }

    // The mice that are plugged in or paired right now.
    private var connected: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("Connected now")
            if state.mice.isEmpty {
                Text("No mouse found. Trackpads don't count. Switch your mouse on or plug it in and it shows up here by itself.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.bottom, 4)
            }
            ForEach(state.mice) { device in
                let profile = device.recognised ?? .fallback(buttons: device.buttons)
                let followed = device.key == state.mouse?.key
                row(profile: followed ? state.profile : profile,
                    title: followed ? state.mouseTitle : MouseSetup.title(device: device, profile: profile),
                    detail: followed ? "\(device.connection) · in use" : device.connection,
                    selected: followed) {
                    // Clicking the one in use changes nothing; only picking another is a choice to remember.
                    if !followed { state.follow(device) }
                }
            }
            HStack(spacing: 8) {
                Button("Detect again") { state.detectMouse() }.controlSize(.small)
                if state.followingByChoice && state.mice.count > 1 {
                    Button("Follow automatically") { state.followAutomatically() }.controlSize(.small)
                }
            }
            .padding(.horizontal, 10).padding(.top, 6)
            if state.mice.count > 1 {
                // macOS doesn't say which mouse a click came from, so one profile serves them all.
                Text(state.followingByChoice
                     ? "This mouse is followed because you picked it. MouseHerdr follows one mouse at a time."
                     : "MouseHerdr follows one mouse at a time. Click another to switch to it.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.top, 3)
            }
            if let result = state.detectResult {
                Text(result).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.top, 2)
            }
            if let note = state.profile.note {
                Label(note, systemImage: "info.circle")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.accent).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.top, 4)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 10, weight: .semibold)).kerning(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10).padding(.bottom, 3)
    }

    private func row(profile: MouseProfile, title: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MouseThumbnail(profile: profile, size: CGSize(width: 30, height: 36))
                VStack(alignment: .leading, spacing: 1) {
                    // A long name shrinks a little before it is cut short.
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.82)
                    if let detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Palette.accentSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Across the top of the window: a mouse was found, and what opens the agent wheel on it.
struct MouseNoticeBanner: View {
    let notice: MouseNotice
    let answer: (_ primary: Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "computermouse.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Circle().fill(Palette.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.system(size: 13, weight: .semibold))
                Text(notice.text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Button(notice.primary) { answer(true) }.buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.small)
                if let other = notice.secondary {
                    Button(other) { answer(false) }.buttonStyle(.link).font(.system(size: 11.5))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.accentSoft))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.accent.opacity(0.35), lineWidth: 1))
    }
}

/// The same notice under the menu bar icon, for when the window is closed.
struct MouseNoticePopover: View {
    let notice: MouseNotice
    let answer: (_ primary: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "computermouse.fill").font(.system(size: 18)).foregroundStyle(Palette.accent)
                Text(notice.title).font(.system(size: 14, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(notice.text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let other = notice.secondary {
                    Button(other) { answer(false) }.buttonStyle(.link).font(.system(size: 12))
                }
                Spacer()
                Button(notice.primary) { answer(true) }.buttonStyle(.borderedProminent).tint(Palette.accent).controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 310)
    }
}

/// Developer aid: every mouse in the list on one sheet, to check the drawings.
struct MouseSheet: View {
    static let columns = 8
    static let cell = CGSize(width: 150, height: 176)

    private let profiles = MouseProfile.all.filter { $0.kind == .mouse } + MouseProfile.fallbacks

    static var size: CGSize {
        let count = MouseProfile.all.filter { $0.kind == .mouse }.count + MouseProfile.fallbacks.count
        let rows = (count + columns - 1) / columns
        return CGSize(width: CGFloat(columns) * cell.width + 32, height: CGFloat(rows) * cell.height + 32)
    }

    var body: some View {
        let rows = stride(from: 0, to: profiles.count, by: Self.columns).map { Array(profiles[$0..<min($0 + Self.columns, profiles.count)]) }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r]) { p in
                        VStack(spacing: 4) {
                            MouseThumbnail(profile: p, size: CGSize(width: 110, height: 120))
                            Text(p.brand).font(.system(size: 9.5, weight: .semibold)).kerning(0.5).foregroundStyle(.tertiary)
                            Text(p.name).font(.system(size: 11.5, weight: .semibold)).multilineTextAlignment(.center)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: Self.cell.width, height: Self.cell.height, alignment: .top)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }
}
