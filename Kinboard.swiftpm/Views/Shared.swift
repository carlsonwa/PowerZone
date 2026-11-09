import SwiftUI

// MARK: - Colours

extension PaletteColor {
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }

    var label: String { rawValue.capitalized }
}

extension LifeArea {
    var tint: Color {
        switch self {
        case .school: return .blue
        case .childcare: return .teal
        case .medical: return .red
        case .activities: return .green
        case .household: return .brown
        case .social: return .pink
        case .other: return .gray
        }
    }
}

extension Expense.Category {
    var tint: Color {
        switch self {
        case .childcare: return .teal
        case .school: return .blue
        case .activities: return .green
        case .medical: return .red
        case .clothing: return .indigo
        case .babySupplies: return .pink
        case .food: return .orange
        case .gifts: return .purple
        case .toys: return .yellow
        case .travel: return .mint
        case .other: return .gray
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static var currencyCode: String {
        UserDefaults.standard.string(forKey: "currencyCode") ?? Locale.current.currency?.identifier ?? "USD"
    }

    static func money(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currencyCode))
    }

    /// Whole-unit money for tight spaces, e.g. chart axes.
    static func moneyShort(_ cents: Int) -> String {
        (Decimal(cents / 100)).formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func shortDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days > 0 && days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 {
            let h = Int(seconds / 3600)
            let m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return m == 0 ? "\(h)h ago" : "\(h)h \(m)m ago"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func eventTime(_ occurrence: EventOccurrence) -> String {
        if occurrence.event.isAllDay { return "All day" }
        if occurrence.end > occurrence.start {
            return "\(time(occurrence.start)) – \(time(occurrence.end))"
        }
        return time(occurrence.start)
    }

    static func age(birthday: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: birthday, to: now)
        let years = c.year ?? 0
        let months = c.month ?? 0
        if years >= 2 { return "\(years) years old" }
        let total = years * 12 + months
        return total == 1 ? "1 month old" : "\(total) months old"
    }
}

// MARK: - Avatars

struct MemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 32

    var body: some View {
        Text(member.initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(member.color.color.gradient, in: Circle())
            .accessibilityLabel(member.name)
    }
}

/// Small overlapping avatars for list rows.
struct MemberStack: View {
    let members: [FamilyMember]
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(members.prefix(4)) { m in
                MemberAvatar(member: m, size: size)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
        }
    }
}

// MARK: - Pickers

/// Tap names to choose who something is for.
struct MemberMultiPicker: View {
    let members: [FamilyMember]
    @Binding var selection: [UUID]

    var body: some View {
        if members.isEmpty {
            Text("Add family members in Family → People").foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(members) { m in
                        chip(m)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ m: FamilyMember) -> some View {
        let on = selection.contains(m.id)
        return Button {
            if on {
                selection.removeAll { $0 == m.id }
            } else {
                selection.append(m.id)
            }
        } label: {
            HStack(spacing: 6) {
                MemberAvatar(member: m, size: 22)
                Text(m.firstName).font(.subheadline)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(on ? m.color.color.opacity(0.22) : Color(.tertiarySystemFill), in: Capsule())
            .overlay(Capsule().stroke(on ? m.color.color : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// "Who's doing it" — one person or nobody.
struct MemberSinglePicker: View {
    let title: String
    let members: [FamilyMember]
    @Binding var selection: UUID?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("Nobody").tag(UUID?.none)
            ForEach(members) { m in
                Text(m.name).tag(UUID?.some(m.id))
            }
        }
    }
}

struct ColorChoice: View {
    @Binding var selection: PaletteColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(PaletteColor.allCases) { c in
                Circle()
                    .fill(c.color.gradient)
                    .frame(width: 30, height: 30)
                    .overlay {
                        if c == selection {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selection = c }
                    .accessibilityLabel(c.label)
                    .accessibilityAddTraits(c == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Repeat settings for an event or task. `anchor` is the first occurrence, used to
/// pre-select its weekday.
struct RepeatEditor: View {
    @Binding var rule: RepeatRule?
    let anchor: Date
    @Environment(\.calendar) var calendar

    private var frequency: Binding<RepeatRule.Frequency?> {
        Binding(
            get: { rule?.frequency },
            set: { newValue in
                if let newValue {
                    var r = rule ?? RepeatRule(frequency: newValue)
                    r.frequency = newValue
                    if newValue != .weekly { r.weekdays = [] }
                    rule = r
                } else {
                    rule = nil
                }
            }
        )
    }

    var body: some View {
        Picker("Repeat", selection: frequency) {
            Text("Never").tag(RepeatRule.Frequency?.none)
            ForEach(RepeatRule.Frequency.allCases) { f in
                Text(f.label(interval: 1)).tag(RepeatRule.Frequency?.some(f))
            }
        }
        if let current = rule {
            Stepper(value: Binding(get: { current.interval },
                                   set: { rule?.interval = max(1, $0) }),
                    in: 1...52) {
                Text(current.interval == 1 ? "Every \(current.frequency.unit)"
                                           : "Every \(current.interval) \(current.frequency.unit)s")
            }
            if current.frequency == .weekly {
                weekdayRow(current)
            }
            Toggle("End repeat", isOn: Binding(
                get: { current.until != nil },
                set: { on in
                    rule?.until = on ? calendar.date(byAdding: .month, value: 3, to: anchor) : nil
                }))
            if let until = current.until {
                DatePicker("Ends on", selection: Binding(get: { until }, set: { rule?.until = $0 }),
                           in: anchor..., displayedComponents: .date)
            }
        }
    }

    private func weekdayRow(_ current: RepeatRule) -> some View {
        let symbols = calendar.veryShortWeekdaySymbols
        let days = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let anchorDay = calendar.component(.weekday, from: anchor)
        let chosen = current.weekdays.isEmpty ? [anchorDay] : current.weekdays
        return HStack {
            ForEach(days, id: \.self) { day in
                let on = chosen.contains(day)
                Button {
                    var set = Set(chosen)
                    if on { set.remove(day) } else { set.insert(day) }
                    if set.isEmpty { set.insert(anchorDay) }
                    rule?.weekdays = set == [anchorDay] ? [] : Array(set).sorted()
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Cards

/// The rounded panels on the Today screen.
struct Card<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "See all"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(Color.accentColor)
                }
                Text(title).font(.headline)
                Spacer()
                if let action {
                    Button(actionLabel, action: action).font(.subheadline)
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A check circle for tasks.
struct DoneButton: View {
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isDone ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Mark not done" : "Mark done")
    }
}

/// Text field bound to an amount in cents.
struct AmountField: View {
    let title: String
    @Binding var cents: Int?
    @State private var text = ""
    @FocusState var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .focused($focused)
            .onAppear { text = cents.map(Money.plain) ?? "" }
            .onChange(of: text) {
                cents = Money.parseInput(text, decimalSeparator: Locale.current.decimalSeparator ?? ".")
            }
    }
}
