import Foundation

// Turns a school email, daycare note or coach's text into suggested events, to-dos and
// expenses. It's rules, not AI: it finds dates and dollar amounts, reads the words around
// them, and proposes something the parent confirms with one tap. Nothing is ever added
// without that tap, so a wrong guess costs a dismiss, not a bad calendar entry.

/// A date found in text.
struct DetectedDate {
    var range: Range<String.Index>
    var date: Date
    var duration: TimeInterval?
    /// The text named a clock time ("3pm", "6:30"), not just a day.
    var hasTime: Bool
    /// The text named a day ("Friday", "Nov 14"), not just a time.
    var hasDay: Bool
}

/// Finds dates in text. On iPhone this is `NSDataDetector`; the Linux checks use a small
/// stand-in, since `NSDataDetector` isn't implemented there.
protocol DateDetecting {
    func detectDates(in text: String) -> [DetectedDate]
}

/// Works out whether matched date text named a time, a day, or both. Shared by every
/// detector because `NSDataDetector` returns noon for "Friday" and gives no way to tell
/// that apart from "Friday at noon".
enum DateText {
    private static let timePattern = try! NSRegularExpression(
        pattern: #"\b\d{1,2}(:\d{2})?\s*([ap]\.?m\.?)(?![a-z])|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b|\bo'?clock\b"#,
        options: [.caseInsensitive])
    private static let dayPattern = try! NSRegularExpression(
        pattern: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?(?![a-z])|\b(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)[a-z]*\b|\b(today|tonight|tomorrow|yesterday|weekend)\b|\b\d{1,2}/\d{1,2}(/\d{2,4})?\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}(st|nd|rd|th)\b"#,
        options: [.caseInsensitive])

    static func hasTime(_ text: String) -> Bool { matches(timePattern, text) }
    static func hasDay(_ text: String) -> Bool { matches(dayPattern, text) }

    private static func matches(_ re: NSRegularExpression, _ text: String) -> Bool {
        re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

struct MessageExtractor {
    var detector: DateDetecting
    var calendar: Calendar
    var now: Date
    var members: [FamilyMember]

    static let maxSuggestions = 12

    // MARK: - Entry point

    func suggestions(for text: String, defaultMemberIDs: [UUID] = []) -> [Suggestion] {
        var results: [Suggestion] = []
        var seen = Set<String>()
        var lastDay: Date?
        var previousSentence = ""
        let wholeMessageArea = Self.guessArea(text)

        for sentence in Self.sentences(in: text) {
            defer { previousSentence = sentence }
            var dates = mergedDates(in: sentence)
            // A time on its own ("Doors open at 6") belongs to the last day mentioned.
            dates = dates.map { d in
                guard !d.hasDay, d.hasTime, let lastDay else { return d }
                var fixed = d
                let t = calendar.dateComponents([.hour, .minute], from: d.date)
                fixed.date = calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: lastDay) ?? d.date
                fixed.hasDay = true
                return fixed
            }
            if let day = dates.last(where: { $0.hasDay }) { lastDay = day.date }

            let amounts = Money.amounts(in: sentence)
            let lower = sentence.lowercased()
            let area = Self.guessArea(sentence) ?? wholeMessageArea ?? .other
            let category = Self.guessExpenseCategory(sentence, area: area)
            let mentioned = mentionedMembers(in: sentence)
            let people = mentioned.isEmpty ? defaultMemberIDs : mentioned
            let excerpt = Self.excerpt(sentence)

            let hasAction = Self.matches(Self.actionCue, lower)
            let hasEvent = Self.matches(Self.eventCue, lower)
            let removable = dates.map(\.range)

            func add(_ s: Suggestion) {
                let key = [s.kind.rawValue, s.title.lowercased(),
                           s.date.map { DayKey.make($0, calendar: calendar) } ?? "-",
                           s.amountCents.map(String.init) ?? "-"].joined(separator: "|")
                guard !seen.contains(key), results.count < Self.maxSuggestions else { return }
                seen.insert(key)
                results.append(s)
            }

            let datedDays = dates.filter(\.hasDay)
            if !datedDays.isEmpty {
                for d in datedDays.prefix(4) {
                    let deadline = isDeadline(sentence, before: d.range)
                    // A deadline is a to-do. Otherwise "please bring…" is a to-do, "picture day"
                    // is an event, and a sentence with both offers both.
                    let makeTask = deadline || hasAction
                    let makeEvent = !deadline && (hasEvent || !hasAction)

                    if makeEvent {
                        var title = Self.title(from: sentence, removing: removable, kind: .event)
                        // A flyer puts the heading on one line and the date on the next.
                        if title == Suggestion.Kind.event.label && !previousSentence.isEmpty
                            && mergedDates(in: previousSentence).isEmpty {
                            title = Self.title(from: previousSentence, removing: [], kind: .event)
                        }
                        var s = Suggestion(kind: .event, title: title, area: area,
                                           expenseCategory: category, memberIDs: people, excerpt: excerpt)
                        if d.hasTime {
                            s.date = d.date
                            s.endDate = d.date.addingTimeInterval(d.duration.flatMap { $0 > 0 ? $0 : nil } ?? 3600)
                        } else {
                            s.isAllDay = true
                            s.date = calendar.startOfDay(for: d.date)
                            if let duration = d.duration, duration >= 86_400 {
                                s.endDate = calendar.startOfDay(for: d.date.addingTimeInterval(duration - 1))
                            } else {
                                s.endDate = s.date
                            }
                        }
                        add(s)
                    }
                    if makeTask {
                        let title = taskTitle(sentence, removing: removable, amounts: amounts)
                        var s = Suggestion(kind: .task, title: title, area: area,
                                           expenseCategory: category, memberIDs: people, excerpt: excerpt)
                        s.date = d.hasTime ? d.date : calendar.startOfDay(for: d.date)
                        s.isAllDay = !d.hasTime
                        s.amountCents = amounts.first?.cents
                        add(s)
                    }
                }
            } else if hasAction && Self.matches(Self.strongActionCue, lower) {
                let title = taskTitle(sentence, removing: [], amounts: amounts)
                var s = Suggestion(kind: .task, title: title, area: area,
                                   expenseCategory: category, memberIDs: people, excerpt: excerpt)
                s.amountCents = amounts.first?.cents
                add(s)
            }

            for amount in amounts.prefix(2) {
                let title = Self.title(from: sentence, removing: removable + [amount.range], kind: .expense)
                var s = Suggestion(kind: .expense, title: title, area: area,
                                   expenseCategory: category, memberIDs: people, excerpt: excerpt)
                s.amountCents = amount.cents
                s.date = calendar.startOfDay(for: now)
                add(s)
            }
        }
        return results
    }

    /// To-do titles read best as an instruction. "The field trip costs $15, due Friday"
    /// becomes "Pay for field trip" rather than the sentence with its date cut out.
    private func taskTitle(_ sentence: String, removing ranges: [Range<String.Index>],
                           amounts: [(range: Range<String.Index>, cents: Int)]) -> String {
        let plain = Self.title(from: sentence, removing: ranges, kind: .task)
        guard let firstAmount = amounts.first else { return plain }
        let firstWord = plain.split(separator: " ").first.map { $0.lowercased() } ?? ""
        if Self.actionVerbs.contains(firstWord) { return plain }
        let subject = Self.title(from: sentence, removing: ranges + amounts.map(\.range) + [firstAmount.range], kind: .expense)
        guard let first = subject.first, subject != "Expense" else { return plain }
        return "Pay for " + first.lowercased() + subject.dropFirst()
    }

    static let actionVerbs: Set<String> = [
        "sign", "return", "bring", "send", "pack", "wear", "dress", "rsvp", "register", "fill", "complete",
        "submit", "pay", "pick", "drop", "call", "schedule", "book", "order", "buy", "turn", "reply", "label",
        "renew", "confirm", "email", "read", "practice", "check", "make", "get", "take", "put", "donate",
        "volunteer", "sign-up", "review", "print", "bake", "decorate", "update", "contact",
    ]

    // MARK: - Dates

    /// Detector output with "Nov 14" and "at 3pm" in the same sentence joined into one date.
    func mergedDates(in sentence: String) -> [DetectedDate] {
        var dates = detector.detectDates(in: sentence).sorted { $0.range.lowerBound < $1.range.lowerBound }
        var i = 0
        while i < dates.count {
            if dates[i].hasDay && !dates[i].hasTime,
               let j = dates.indices.first(where: { $0 > i && !dates[$0].hasDay && dates[$0].hasTime }) {
                let day = dates[i]
                let time = dates[j]
                let t = calendar.dateComponents([.hour, .minute], from: time.date)
                var merged = day
                merged.date = calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0,
                                            of: calendar.startOfDay(for: day.date)) ?? day.date
                merged.hasTime = true
                merged.duration = time.duration
                merged.range = min(day.range.lowerBound, time.range.lowerBound)..<max(day.range.upperBound, time.range.upperBound)
                dates[i] = merged
                dates.remove(at: j)
            }
            i += 1
        }
        return dates
    }

    /// "Return the form by Friday", "RSVP by 11/20", "due Monday" — a date that's a
    /// deadline rather than when something happens.
    func isDeadline(_ sentence: String, before range: Range<String.Index>) -> Bool {
        let prefix = sentence[sentence.startIndex..<range.lowerBound].lowercased()
        let lastWords = prefix.split(whereSeparator: { !$0.isLetter && $0 != "'" }).suffix(3).map(String.init)
        if lastWords.contains(where: { ["by", "before", "due", "deadline", "until", "later"].contains($0) }) {
            return true
        }
        return Self.matches(Self.deadlineCue, sentence.lowercased())
    }

    // MARK: - People

    func mentionedMembers(in text: String) -> [UUID] {
        members.filter { m in
            let name = m.firstName
            guard name.count >= 2 else { return false }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "('s)?\\b"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }.map(\.id)
    }

    /// Members named anywhere in the message, used to pre-fill who it's about.
    func mentionedMembersInMessage(_ text: String) -> [UUID] { mentionedMembers(in: text) }

    // MARK: - Sentences

    private static let noSplitAfter: Set<String> = [
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "mr", "mrs", "ms", "dr", "st", "ave", "rd", "no", "vs", "approx", "e.g", "i.e", "etc", "jr", "sr",
    ]

    /// Splits a message into lines, then lines into sentences, without splitting
    /// "Nov. 14" or "Dr. Patel".
    static func sentences(in text: String) -> [String] {
        var output: [String] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n").map { stripBullet(String($0)) }
        for line in lines where !line.isEmpty {
            var current = ""
            let chars = Array(line)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                current.append(c)
                if ".!?".contains(c), i + 2 < chars.count, chars[i + 1].isWhitespace {
                    let next = chars[i + 2]
                    let token = lastToken(of: current).lowercased()
                    let isMeridiem = token == "a.m" || token == "p.m"
                    let shouldSplit: Bool
                    if c != "." {
                        shouldSplit = next.isUppercase || next.isNumber
                    } else if isMeridiem {
                        shouldSplit = next.isUppercase
                    } else if noSplitAfter.contains(token) || (token.count == 1 && token.first!.isLetter) {
                        shouldSplit = false
                    } else {
                        shouldSplit = next.isUppercase || next.isNumber
                    }
                    if shouldSplit {
                        output.append(current.trimmingCharacters(in: .whitespaces))
                        current = ""
                    }
                }
                i += 1
            }
            let rest = current.trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { output.append(rest) }
        }
        return output
    }

    private static func lastToken(of text: String) -> String {
        var s = text
        if let last = s.last, ".!?".contains(last) { s.removeLast() }
        let token = s.split(whereSeparator: { $0.isWhitespace || $0 == "(" }).last.map(String.init) ?? ""
        return token
    }

    private static let bulletPattern = try! NSRegularExpression(pattern: #"^\s*(?:[-*•·–—>]+|\d{1,2}[.)])\s+"#)

    static func stripBullet(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = NSRange(trimmed.startIndex..., in: trimmed)
        return bulletPattern.stringByReplacingMatches(in: trimmed, range: ns, withTemplate: "")
    }

    /// Joins lines read off a photo back into sentences. A line break with no full stop
    /// before it, followed by a lowercase word or a connector, is a wrapped line rather
    /// than a new thought.
    static func reflow(_ lines: [String]) -> String {
        let connectors: Set<String> = ["on", "at", "by", "the", "is", "are", "for", "to", "and", "of", "from",
                                       "will", "be", "a", "an", "with", "in", "your", "our"]
        var out = ""
        var previous = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if out.isEmpty {
                out = line
            } else {
                let ended = previous.last.map { ".!?:".contains($0) } ?? true
                let lastWord = previous.split(separator: " ").last.map { $0.lowercased() } ?? ""
                let startsLower = line.first.map { $0.isLowercase } ?? false
                out += (!ended && (startsLower || connectors.contains(lastWord))) ? " " + line : "\n" + line
            }
            previous = line
        }
        return out
    }

    static func excerpt(_ sentence: String) -> String {
        sentence.count > 180 ? String(sentence.prefix(177)) + "…" : sentence
    }

    // MARK: - Titles

    private static let trailingConnectors: Set<String> = [
        "on", "at", "by", "is", "are", "be", "will", "was", "were", "this", "next", "coming",
        "for", "from", "starting", "due", "until", "before", "of", "the", "scheduled", "set",
        "happening", "held", "begins", "starts", "start", "begin", "and", "or", "to", "no", "later",
        "than", "every", "each", "costs", "cost", "a", "an", "also", "again", "here",
    ]

    private static let leadingFillers: [NSRegularExpression] = [
        #"^(?:hi|hello|hey|dear|good (?:morning|afternoon|evening))\b[^,!:]{0,40}[,!:]\s*"#,
        #"^(?:friendly |quick |gentle |important )?(?:reminder|note|fyi|update|heads up|save the date|announcement|attention|important|ps|p\.s\.)\s*[:!\-–—]\s*"#,
        #"^(?:just )?(?:a )?(?:friendly |quick |gentle )?reminder (?:that|to|about)\s+"#,
        #"^please (?:note|remember|be aware)(?: that| to)?\s+"#,
        #"^remember (?:to|that)\s+"#,
        #"^(?:don'?t|do not) forget (?:to|that|about)\s+"#,
        #"^(?:please|kindly|also|and|so)[,]?\s+"#,
        #"^(?:we will|we'll|we are|we're) (?:be )?(?:having|hosting|holding)\s+"#,
        #"^(?:we will|we'll) have\s+"#,
        #"^there (?:will be|is|are|'s)\s+"#,
        #"^(?:this|next) (?:week|month)(?:'s)?,?\s+"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let leadingArticle = try! NSRegularExpression(pattern: #"^(?:the|a|an|our|your)\s+"#,
                                                                options: [.caseInsensitive])

    /// A short title from a sentence: dates (and the "is on" / "by" leading into them)
    /// removed, greetings and "Reminder:" dropped, trailing filler trimmed.
    static func title(from sentence: String, removing ranges: [Range<String.Index>], kind: Suggestion.Kind) -> String {
        // Drop the matched ranges, trimming the connector words that led into each.
        var pieces: [String] = []
        var cursor = sentence.startIndex
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where range.lowerBound >= cursor {
            pieces.append(trimTrailingConnectors(String(sentence[cursor..<range.lowerBound])))
            cursor = range.upperBound
        }
        pieces.append(String(sentence[cursor...]))
        var text = pieces.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")

        text = collapseSpaces(text)
        var changed = true
        while changed {
            changed = false
            for re in leadingFillers {
                let ns = NSRange(text.startIndex..., in: text)
                if let m = re.firstMatch(in: text, range: ns), m.range.length > 0, m.range.length < ns.length {
                    text = String(text[Range(m.range, in: text)!.upperBound...])
                    changed = true
                }
            }
        }
        // Keep the first clause: "Team dues are $35 — please pay" is about the dues. Events
        // and expenses also stop at a comma ("Tournament, arrive early"); to-dos don't,
        // because "Bring snacks, water and sunscreen" needs all of it.
        for separator in [" — ", " – ", " - ", "; "] {
            if let r = text.range(of: separator), text.distance(from: text.startIndex, to: r.lowerBound) >= 3 {
                text = String(text[..<r.lowerBound])
            }
        }
        if kind != .task, let r = text.range(of: ", "), text.distance(from: text.startIndex, to: r.lowerBound) >= 4 {
            text = String(text[..<r.lowerBound])
        }
        text = trimTrailingConnectors(text)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—\"'“”()!?."))
        text = trimTrailingConnectors(text)
        if kind == .event || kind == .expense {
            let ns = NSRange(text.startIndex..., in: text)
            if let m = leadingArticle.firstMatch(in: text, range: ns), m.range.length < ns.length {
                text = String(text[Range(m.range, in: text)!.upperBound...])
            }
        }
        // Tidy separators left behind when a date sat between commas.
        text = text.replacingOccurrences(of: " ,", with: ",").replacingOccurrences(of: ",,", with: ",")
        text = collapseSpaces(text).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))

        if text.count > 70 {
            let cut = text.prefix(70)
            text = (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
        }
        guard let first = text.first else { return kind.label }
        // Flyers shout. "SPRING PICTURE DAY" reads better as "Spring Picture Day".
        let letters = text.filter(\.isLetter)
        if letters.count >= 4 && letters.allSatisfy(\.isUppercase) {
            return text.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return first.uppercased() + text.dropFirst()
    }

    private static func trimTrailingConnectors(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let last = words.last {
            let bare = last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;:-–—("))
            if bare.isEmpty || trailingConnectors.contains(bare) {
                words.removeLast()
            } else {
                break
            }
        }
        return words.joined(separator: " ")
    }

    private static func collapseSpaces(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Cues

    static let actionCue = try! NSRegularExpression(pattern: #"\b(please|remember to|don'?t forget|do not forget|need(?:s)? to|must|make sure|be sure to|sign|return|bring|send in|send|pack|wear|dress|rsvp|register|sign up|fill out|complete|submit|pay|pick up|drop off|call|schedule|book|order|buy|turn in|reply|label|renew|confirm)\b"#)
    static let strongActionCue = try! NSRegularExpression(pattern: #"\b(please|remember to|don'?t forget|do not forget|need(?:s)? to|must|make sure|be sure to|sign|return|bring|send in|pack|rsvp|register|sign up|fill out|submit|pay|turn in|renew)\b"#)
    static let eventCue = try! NSRegularExpression(pattern: #"\b(day|night|party|meeting|conferences?|practice|game|match|recital|concert|performance|show|play|trip|fair|festival|assembly|ceremony|graduation|appointment|appt|check-?up|visit|class|lessons?|camp|tournament|meet|rehearsal|celebration|dismissal|no school|closed|closure|holiday|break|open house|orientation|workshop|fundraiser|sale|potluck|picnic|parade|playdate|sleepover|birthday|ballet|dance|swim|soccer|baseball|basketball|hockey|gymnastics|karate|piano|tutoring|session|event|reunion|dinner|lunch|breakfast|service|scouts?|starts|begins)\b"#)
    static let deadlineCue = try! NSRegularExpression(pattern: #"\b(due|deadline|no later than|rsvp|register by|sign up by|return by|submit by|turn in by|last day to)\b"#)

    static func matches(_ re: NSRegularExpression, _ text: String) -> Bool {
        re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Categories

    private static let areaKeywords: [(LifeArea, [String])] = [
        (.medical, ["doctor", "dentist", "dental", "pediatric", "pediatrician", "clinic", "checkup", "check-up",
                    "vaccine", "vaccination", "shot", "prescription", "pharmacy", "orthodontist", "therapy",
                    "therapist", "allergist", "physical", "flu", "fever", "nurse", "medicine", "appointment"]),
        (.childcare, ["daycare", "day care", "preschool", "childcare", "child care", "nanny", "babysitter",
                      "sitter", "after-care", "aftercare", "before-care", "nursery"]),
        (.school, ["school", "teacher", "class", "classroom", "homework", "pta", "pto", "principal", "field trip",
                   "picture day", "report card", "conference", "conferences", "dismissal", "library", "book fair",
                   "permission slip", "spirit", "semester", "grade", "kindergarten", "recess", "lunch account"]),
        (.activities, ["practice", "game", "coach", "team", "tournament", "lesson", "lessons", "recital",
                       "rehearsal", "camp", "scouts", "soccer", "swim", "dance", "ballet", "piano", "karate",
                       "gymnastics", "baseball", "basketball", "hockey", "league", "uniform", "jersey"]),
        (.social, ["party", "birthday", "playdate", "sleepover", "celebration", "invitation", "invite", "wedding"]),
        (.household, ["groceries", "laundry", "trash", "chores", "cleaning", "repair", "bill"]),
    ]

    static func guessArea(_ text: String) -> LifeArea? {
        let lower = text.lowercased()
        var best: (LifeArea, Int)?
        for (area, words) in areaKeywords {
            let hits = words.filter { containsWord($0, in: lower) }.count
            if hits > 0, hits > (best?.1 ?? 0) { best = (area, hits) }
        }
        return best?.0
    }

    static func guessExpenseCategory(_ text: String, area: LifeArea) -> Expense.Category {
        let lower = text.lowercased()
        let specific: [(Expense.Category, [String])] = [
            (.clothing, ["shoes", "clothes", "clothing", "uniform", "jacket", "coat", "shirt", "costume"]),
            (.food, ["lunch", "snack", "snacks", "pizza", "food", "milk"]),
            (.gifts, ["gift", "present", "party", "birthday"]),
            (.toys, ["book", "books", "toy", "toys", "book fair"]),
            (.babySupplies, ["diapers", "wipes", "formula", "bottles", "stroller"]),
            (.travel, ["trip", "museum", "zoo", "tickets", "admission", "bus"]),
        ]
        for (category, words) in specific where words.contains(where: { containsWord($0, in: lower) }) {
            // A school field trip is still School spending.
            if category == .travel && area == .school { return .school }
            return category
        }
        switch area {
        case .school: return .school
        case .childcare: return .childcare
        case .medical: return .medical
        case .activities: return .activities
        case .social: return .gifts
        case .household, .other: return .other
        }
    }

    static func guessSource(_ text: String) -> InboxMessage.Source {
        switch guessArea(text) {
        case .school: return .school
        case .childcare: return .daycare
        case .medical: return .medical
        case .activities: return .activities
        case .social: return .family
        default: return .other
        }
    }

    private static func containsWord(_ word: String, in lower: String) -> Bool {
        var searchStart = lower.startIndex
        while let r = lower.range(of: word, range: searchStart..<lower.endIndex) {
            let beforeOK = r.lowerBound == lower.startIndex || !lower[lower.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == lower.endIndex || !lower[r.upperBound].isLetter
            if beforeOK && afterOK { return true }
            searchStart = r.upperBound
        }
        return false
    }
}
