import Foundation

// Turning an accepted suggestion into the real thing. Kept here rather than in the views
// so the self-checks cover it.

extension Suggestion {
    func makeEvent(messageID: UUID?, calendar: Calendar, now: Date = Date()) -> FamilyEvent {
        let fallbackStart = calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                          of: calendar.date(byAdding: .day, value: 1, to: now) ?? now) ?? now
        let start = date ?? fallbackStart
        var event = FamilyEvent(title: title, start: start, end: start, area: area, memberIDs: memberIDs,
                                sourceMessageID: messageID)
        if isAllDay {
            event.isAllDay = true
            event.start = calendar.startOfDay(for: start)
            event.end = max(event.start, calendar.startOfDay(for: endDate ?? start))
        } else {
            event.end = max(start, endDate ?? start.addingTimeInterval(3600))
        }
        event.notes = excerpt
        event.reminder = isAllDay ? .day1 : .hour1
        return event
    }

    func makeTask(messageID: UUID?, now: Date = Date()) -> TaskItem {
        var task = TaskItem(title: title, notes: excerpt, dueDate: date, hasDueTime: date != nil && !isAllDay,
                            area: area, memberIDs: memberIDs, createdAt: now, sourceMessageID: messageID)
        task.remind = date != nil
        return task
    }

    func makeExpense(messageID: UUID?, calendar: Calendar, now: Date = Date()) -> Expense {
        Expense(title: title, amountCents: amountCents ?? 0, date: date ?? calendar.startOfDay(for: now),
                category: expenseCategory, memberIDs: memberIDs, notes: excerpt, sourceMessageID: messageID)
    }
}

extension FamilyData {
    /// Adds the item a suggestion describes and marks the suggestion added. Returns the new
    /// item's id. When nothing is left to review, the message is filed as done.
    @discardableResult
    mutating func accept(suggestionID: UUID, inMessage messageID: UUID, calendar: Calendar, now: Date = Date()) -> UUID? {
        guard let m = messages.firstIndex(where: { $0.id == messageID }),
              let s = messages[m].suggestions.firstIndex(where: { $0.id == suggestionID }) else { return nil }
        let suggestion = messages[m].suggestions[s]
        let newID: UUID
        switch suggestion.kind {
        case .event:
            let e = suggestion.makeEvent(messageID: messageID, calendar: calendar, now: now)
            events.append(e)
            newID = e.id
        case .task:
            let t = suggestion.makeTask(messageID: messageID, now: now)
            tasks.append(t)
            newID = t.id
        case .expense:
            let e = suggestion.makeExpense(messageID: messageID, calendar: calendar, now: now)
            expenses.append(e)
            newID = e.id
        }
        markSuggestion(suggestionID, inMessage: messageID, as: .added)
        return newID
    }

    mutating func markSuggestion(_ suggestionID: UUID, inMessage messageID: UUID, as state: Suggestion.State) {
        guard let m = messages.firstIndex(where: { $0.id == messageID }),
              let s = messages[m].suggestions.firstIndex(where: { $0.id == suggestionID }) else { return }
        messages[m].suggestions[s].state = state
        if state != .pending && messages[m].pendingSuggestions.isEmpty {
            messages[m].status = .done
        }
    }
}
