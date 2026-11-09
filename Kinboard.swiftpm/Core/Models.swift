import Foundation

// Everything the family keeps in Kinboard. These types are plain Codable values with no
// UI or Apple-only imports, so the same files compile on Linux and run in
// `tools/check_kinboard_core.sh`.

// MARK: - People

struct FamilyMember: Identifiable, Codable, Hashable {
    enum Role: String, Codable, CaseIterable, Identifiable {
        case parent, child, caregiver, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .parent: return "Parent"
            case .child: return "Child"
            case .caregiver: return "Caregiver"
            case .other: return "Other"
            }
        }
    }

    var id = UUID()
    var name: String
    var role: Role
    var color: PaletteColor
    var birthday: Date?

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

/// Colours are stored by name so the data file stays readable and the UI layer maps them.
enum PaletteColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray
    var id: String { rawValue }
}

/// Doctors, teachers, coaches, sitters — the people the family deals with.
struct Contact: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var role: String = ""
    var phone: String = ""
    var email: String = ""
    var memberIDs: [UUID] = []
    var notes: String = ""
}

/// One fact worth keeping at hand: shoe size, allergies, insurance member number.
struct InfoItem: Identifiable, Codable, Hashable {
    enum Category: String, Codable, CaseIterable, Identifiable {
        case medical, school, sizes, insurance, activities, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .medical: return "Medical"
            case .school: return "School"
            case .sizes: return "Sizes"
            case .insurance: return "Insurance & IDs"
            case .activities: return "Activities"
            case .other: return "Other"
            }
        }
        var symbol: String {
            switch self {
            case .medical: return "cross.case"
            case .school: return "graduationcap"
            case .sizes: return "tshirt"
            case .insurance: return "creditcard"
            case .activities: return "figure.run"
            case .other: return "note.text"
            }
        }
    }

    var id = UUID()
    var memberID: UUID?
    var category: Category
    var title: String
    var value: String
}

// MARK: - Shared categories

/// One list of life areas used by events, tasks and messages so a school message files
/// its follow-ups under School everywhere.
enum LifeArea: String, Codable, CaseIterable, Identifiable {
    case school, childcare, medical, activities, household, social, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .school: return "School"
        case .childcare: return "Childcare"
        case .medical: return "Medical"
        case .activities: return "Activities"
        case .household: return "Household"
        case .social: return "Social"
        case .other: return "Other"
        }
    }
    var symbol: String {
        switch self {
        case .school: return "backpack"
        case .childcare: return "figure.and.child.holdinghands"
        case .medical: return "stethoscope"
        case .activities: return "soccerball"
        case .household: return "house"
        case .social: return "party.popper"
        case .other: return "tag"
        }
    }
}

// MARK: - Calendar

struct FamilyEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// For all-day events this is the start of the first day.
    var start: Date
    /// For timed events, the end time. For all-day events, the start of the *last* day
    /// (inclusive), so a one-day event has `end == start`.
    var end: Date
    var isAllDay: Bool = false
    var location: String = ""
    var notes: String = ""
    var area: LifeArea = .other
    var memberIDs: [UUID] = []
    var repeatRule: RepeatRule?
    /// Occurrences removed from a repeating series, as day keys ("2026-11-14").
    var skippedDays: [String] = []
    var reminder: ReminderOffset = .none
    var sourceMessageID: UUID?
}

enum ReminderOffset: Int, Codable, CaseIterable, Identifiable {
    case none = -1
    case atTime = 0
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours2 = 120
    case day1 = 1440
    case days2 = 2880
    case week1 = 10080

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .atTime: return "At time of event"
        case .minutes15: return "15 minutes before"
        case .minutes30: return "30 minutes before"
        case .hour1: return "1 hour before"
        case .hours2: return "2 hours before"
        case .day1: return "1 day before"
        case .days2: return "2 days before"
        case .week1: return "1 week before"
        }
    }
}

// MARK: - Tasks

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var dueDate: Date?
    var hasDueTime: Bool = false
    var area: LifeArea = .household
    var assigneeID: UUID?
    /// Who the task is about — "sign Maya's permission slip" is for Maya.
    var memberIDs: [UUID] = []
    var isFlagged: Bool = false
    var repeatRule: RepeatRule?
    var remind: Bool = false
    var createdAt = Date()
    var completedAt: Date?
    var sourceMessageID: UUID?

    var isDone: Bool { completedAt != nil }
}

// MARK: - Spending

struct Expense: Identifiable, Codable, Hashable {
    enum Category: String, Codable, CaseIterable, Identifiable {
        case childcare, school, activities, medical, clothing, babySupplies, food, gifts, toys, travel, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .childcare: return "Childcare"
            case .school: return "School"
            case .activities: return "Activities & Lessons"
            case .medical: return "Medical"
            case .clothing: return "Clothing & Shoes"
            case .babySupplies: return "Baby & Supplies"
            case .food: return "Food & Snacks"
            case .gifts: return "Gifts & Parties"
            case .toys: return "Toys & Books"
            case .travel: return "Travel & Outings"
            case .other: return "Other"
            }
        }
        var symbol: String {
            switch self {
            case .childcare: return "figure.and.child.holdinghands"
            case .school: return "backpack"
            case .activities: return "soccerball"
            case .medical: return "cross.case"
            case .clothing: return "tshirt"
            case .babySupplies: return "stroller"
            case .food: return "fork.knife"
            case .gifts: return "gift"
            case .toys: return "teddybear"
            case .travel: return "car"
            case .other: return "tag"
            }
        }
    }

    /// For FSA / HSA / insurance claims: has the money come back yet?
    enum Reimbursement: String, Codable, CaseIterable, Identifiable {
        case notEligible, toSubmit, submitted, reimbursed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notEligible: return "Not reimbursable"
            case .toSubmit: return "To submit"
            case .submitted: return "Submitted"
            case .reimbursed: return "Reimbursed"
            }
        }
    }

    var id = UUID()
    var title: String
    /// Whole cents, so totals never pick up floating-point noise.
    var amountCents: Int
    var date: Date
    var category: Category
    var memberIDs: [UUID] = []
    var paidByID: UUID?
    var reimbursement: Reimbursement = .notEligible
    var notes: String = ""
    /// File name of a receipt photo in the app's Receipts folder.
    var receiptFile: String?
    var sourceMessageID: UUID?
}

// MARK: - Trackers

struct Tracker: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// Just "it happened" — a diaper change, a dose of medicine.
        case event
        /// A number with a unit — ounces, °F, pounds, minutes.
        case quantity
        /// Started and stopped — sleep, a nap, tummy time.
        case duration
        var id: String { rawValue }
        var label: String {
            switch self {
            case .event: return "Log when it happens"
            case .quantity: return "Record an amount"
            case .duration: return "Time it (start / stop)"
            }
        }
    }

    var id = UUID()
    var name: String
    var symbol: String
    var kind: Kind
    var unit: String = ""
    var memberID: UUID?
    var color: PaletteColor = .blue
    var isPinned: Bool = true
}

struct TrackerEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var trackerID: UUID
    var date: Date
    /// Set when a duration entry is stopped. `nil` on a duration entry means it's running.
    var endDate: Date?
    var value: Double?
    var note: String = ""

    var duration: TimeInterval? {
        endDate.map { $0.timeIntervalSince(date) }
    }
}

// MARK: - Messages

/// A piece of parenting communication — a school email, a daycare note, a coach's text,
/// a photo of a flyer — captured so its dates, to-dos and costs can be pulled out.
struct InboxMessage: Identifiable, Codable, Hashable {
    enum Source: String, Codable, CaseIterable, Identifiable {
        case school, daycare, medical, activities, family, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .school: return "School"
            case .daycare: return "Daycare"
            case .medical: return "Medical"
            case .activities: return "Activities"
            case .family: return "Family & Friends"
            case .other: return "Other"
            }
        }
        var symbol: String {
            switch self {
            case .school: return "backpack"
            case .daycare: return "figure.and.child.holdinghands"
            case .medical: return "stethoscope"
            case .activities: return "soccerball"
            case .family: return "person.2"
            case .other: return "envelope"
            }
        }
    }

    enum Status: String, Codable {
        case needsReview, done
    }

    var id = UUID()
    var receivedAt = Date()
    var sender: String = ""
    var subject: String = ""
    var body: String
    var source: Source = .other
    var memberIDs: [UUID] = []
    var status: Status = .needsReview
    var isPinned: Bool = false
    /// Pulled out when the message is captured and stored with it. Relative dates such as
    /// "this Friday" mean the Friday after the message arrived, so re-reading the text a
    /// week later would land on the wrong day.
    var suggestions: [Suggestion] = []

    var pendingSuggestions: [Suggestion] { suggestions.filter { $0.state == .pending } }

    var displayTitle: String {
        if !subject.trimmingCharacters(in: .whitespaces).isEmpty { return subject }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Message" }
        return trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
    }
}

/// Something Kinboard found in a message that could become an event, task or expense.
struct Suggestion: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case event, task, expense
        var label: String {
            switch self {
            case .event: return "Event"
            case .task: return "To-do"
            case .expense: return "Expense"
            }
        }
        var symbol: String {
            switch self {
            case .event: return "calendar.badge.plus"
            case .task: return "checklist"
            case .expense: return "dollarsign.circle"
            }
        }
    }

    enum State: String, Codable {
        case pending, added, dismissed
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var date: Date?
    /// Events only: end time, or for all-day events the last day.
    var endDate: Date?
    var isAllDay: Bool = false
    var amountCents: Int?
    var area: LifeArea = .other
    var expenseCategory: Expense.Category = .other
    var memberIDs: [UUID] = []
    /// The sentence it came from, shown under the suggestion so it can be checked.
    var excerpt: String = ""
    var state: State = .pending
}
