import Charts
import PhotosUI
import SwiftUI

struct SpendingView: View {
    @EnvironmentObject var store: FamilyStore
    @State private var month = Date()
    @State private var editing: Expense? = nil
    @State private var memberFilter: UUID? = nil
    @State private var showBudgets = false

    struct CategoryTotal: Identifiable {
        let category: Expense.Category
        let cents: Int
        var id: String { category.rawValue }
    }

    struct MonthTotal: Identifiable {
        let month: Date
        let cents: Int
        var id: Date { month }
    }

    private var calendar: Calendar { store.calendar }

    private func matchesFilter(_ e: Expense) -> Bool {
        memberFilter.map { e.memberIDs.contains($0) || e.paidByID == $0 } ?? true
    }

    private var monthExpenses: [Expense] {
        store.data.expenses(inMonthOf: month, calendar: calendar)
            .filter(matchesFilter)
            .sorted { $0.date > $1.date }
    }

    private var categoryTotals: [CategoryTotal] {
        var totals: [Expense.Category: Int] = [:]
        for e in monthExpenses { totals[e.category, default: 0] += e.amountCents }
        return totals.map { CategoryTotal(category: $0.key, cents: $0.value) }
            .sorted { $0.cents > $1.cents }
    }

    private var trend: [MonthTotal] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        return (0..<6).reversed().compactMap { back -> MonthTotal? in
            guard let m = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
            let cents = store.data.expenses(inMonthOf: m, calendar: calendar).filter(matchesFilter)
                .reduce(0) { $0 + $1.amountCents }
            return MonthTotal(month: m, cents: cents)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { summary }
                if !categoryTotals.isEmpty {
                    Section("By category") { categoryChart }
                }
                Section("Last 6 months") { trendChart }
                budgetSection
                Section("Expenses") {
                    if monthExpenses.isEmpty {
                        Text("Nothing logged this month.").foregroundStyle(.secondary)
                    }
                    ForEach(monthExpenses) { e in
                        ExpenseRow(expense: e) { editing = e }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteExpense(e.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Spending")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                        .disabled(calendar.isDate(month, equalTo: Date(), toGranularity: .month))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Person", selection: $memberFilter) {
                            Text("Everyone").tag(UUID?.none)
                            ForEach(store.data.members) { m in
                                Text(m.name).tag(UUID?.some(m.id))
                            }
                        }
                    } label: {
                        Image(systemName: memberFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter by person")
                    Button {
                        let date = calendar.isDate(month, equalTo: Date(), toGranularity: .month)
                            ? Date() : (calendar.dateInterval(of: .month, for: month)?.start ?? Date())
                        editing = Expense(title: "", amountCents: 0, date: date, category: .other,
                                          memberIDs: memberFilter.map { [$0] } ?? [])
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New expense")
                }
            }
            .sheet(item: $editing) { e in
                ExpenseEditor(original: e)
            }
            .sheet(isPresented: $showBudgets) {
                BudgetEditor()
            }
        }
    }

    // MARK: Sections

    private var summary: some View {
        let spent = monthExpenses.reduce(0) { $0 + $1.amountCents }
        let budget = memberFilter == nil ? store.data.totalBudgetCents : 0
        let pending = store.data.pendingReimbursementCents
        return VStack(alignment: .leading, spacing: 8) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.money(spent)).font(.largeTitle.bold()).monospacedDigit()
                if budget > 0 {
                    Text("of \(Fmt.money(budget)) budget").foregroundStyle(.secondary)
                }
            }
            if budget > 0 {
                ProgressView(value: Double(min(spent, budget)), total: Double(budget))
                    .tint(spent > budget ? Color.red : Color.accentColor)
                Text(spent > budget ? "\(Fmt.money(spent - budget)) over" : "\(Fmt.money(budget - spent)) left")
                    .font(.caption)
                    .foregroundStyle(spent > budget ? Color.red : Color.secondary)
            }
            if pending > 0 {
                Label("\(Fmt.money(pending)) to be reimbursed (FSA, HSA or insurance)", systemImage: "arrow.uturn.backward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var categoryChart: some View {
        let totals = categoryTotals
        return Chart(totals) { item in
            BarMark(x: .value("Spent", Double(item.cents) / 100),
                    y: .value("Category", item.category.label))
                .foregroundStyle(item.category.tint)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(Fmt.moneyShort(item.cents)).font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: CGFloat(totals.count) * 34 + 10)
        .padding(.vertical, 6)
    }

    private var trendChart: some View {
        Chart(trend) { item in
            BarMark(x: .value("Month", item.month, unit: .month),
                    y: .value("Spent", Double(item.cents) / 100))
                .foregroundStyle(calendar.isDate(item.month, equalTo: month, toGranularity: .month)
                                 ? Color.accentColor : Color.accentColor.opacity(0.35))
                .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Fmt.moneyShort(Int(v * 100)))
                    }
                }
            }
        }
        .frame(height: 170)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var budgetSection: some View {
        let spentBy = Dictionary(uniqueKeysWithValues: categoryTotals.map { ($0.category, $0.cents) })
        let budgeted = Expense.Category.allCases.filter { store.data.budgetCents(for: $0) != nil }
        Section {
            if budgeted.isEmpty {
                Text("Set monthly budgets to see how each category is tracking.")
                    .foregroundStyle(.secondary)
            }
            ForEach(budgeted) { category in
                let budget = store.data.budgetCents(for: category) ?? 0
                let spent = spentBy[category] ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(category.label, systemImage: category.symbol)
                        Spacer()
                        Text("\(Fmt.moneyShort(spent)) / \(Fmt.moneyShort(budget))")
                            .monospacedDigit()
                            .foregroundStyle(spent > budget ? Color.red : Color.secondary)
                    }
                    .font(.subheadline)
                    ProgressView(value: Double(min(spent, budget)), total: Double(max(budget, 1)))
                        .tint(spent > budget ? Color.red : category.tint)
                }
            }
            Button(budgeted.isEmpty ? "Set Budgets" : "Edit Budgets") { showBudgets = true }
        } header: {
            Text("Budgets")
        } footer: {
            if memberFilter != nil {
                Text("Budgets are for the whole family; the bars show only the selected person's spending.")
            }
        }
    }

    private func shift(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) { month = next }
    }
}

struct ExpenseRow: View {
    @EnvironmentObject var store: FamilyStore
    let expense: Expense
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: expense.category.symbol)
                    .foregroundStyle(expense.category.tint)
                    .frame(width: 32, height: 32)
                    .background(expense.category.tint.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.title.isEmpty ? expense.category.label : expense.title).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.money(expense.amountCents)).monospacedDigit()
                    if expense.reimbursement == .toSubmit || expense.reimbursement == .submitted {
                        Text(expense.reimbursement.label).font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts = [Fmt.shortDay(expense.date)]
        let names = store.data.members(expense.memberIDs).map(\.firstName)
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        if let payer = store.data.member(expense.paidByID) { parts.append("paid by \(payer.firstName)") }
        if expense.receiptFile != nil { parts.append("receipt") }
        return parts.joined(separator: " · ")
    }
}

struct ExpenseEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss
    let original: Expense
    let onSaved: ((Expense) -> Void)?
    @State private var draft: Expense
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showReceipt = false
    @State private var confirmDelete = false

    init(original: Expense, onSaved: ((Expense) -> Void)? = nil) {
        self.original = original
        self.onSaved = onSaved
        _draft = State(initialValue: original)
    }

    private var isNew: Bool { !store.data.expenses.contains { $0.id == original.id } }

    private var amount: Binding<Int?> {
        Binding(get: { draft.amountCents == 0 ? nil : draft.amountCents },
                set: { draft.amountCents = max(0, $0 ?? 0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Fmt.currencyCode).foregroundStyle(.secondary)
                        AmountField(title: "0.00", cents: amount)
                            .font(.title2.bold())
                    }
                    TextField("What was it? e.g. Soccer cleats", text: $draft.title)
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    Picker("Category", selection: $draft.category) {
                        ForEach(Expense.Category.allCases) { c in
                            Label(c.label, systemImage: c.symbol).tag(c)
                        }
                    }
                }
                Section("For") {
                    MemberMultiPicker(members: store.data.children.isEmpty ? store.data.members : store.data.children,
                                      selection: $draft.memberIDs)
                }
                Section {
                    MemberSinglePicker(title: "Paid by", members: store.data.adults, selection: $draft.paidByID)
                    Picker("Reimbursement", selection: $draft.reimbursement) {
                        ForEach(Expense.Reimbursement.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                } footer: {
                    Text("Track FSA, HSA or insurance claims here — Spending shows what's still owed back to you.")
                }
                Section("Receipt") {
                    if let file = draft.receiptFile, let image = UIImage(contentsOfFile: store.receiptURL(file).path) {
                        Button {
                            showReceipt = true
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        Button("Remove Receipt", role: .destructive) {
                            draft.receiptFile = nil
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(draft.receiptFile == nil ? "Add a receipt photo" : "Replace receipt photo", systemImage: "doc.text.image")
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...8)
                }
                if !isNew {
                    Section {
                        Button("Delete Expense", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.amountCents <= 0)
                }
            }
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                photoItem = nil
                Task { await attach(item) }
            }
            .sheet(isPresented: $showReceipt) {
                ReceiptViewer(url: draft.receiptFile.map { store.receiptURL($0) })
            }
            .confirmationDialog("Delete this expense?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Expense", role: .destructive) {
                    store.deleteExpense(original.id)
                    dismiss()
                }
            }
        }
    }

    @MainActor
    private func attach(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = image.downscaled(maxDimension: 1800).jpegData(compressionQuality: 0.7),
              let name = store.storeReceipt(jpeg) else { return }
        // A receipt picked and then replaced before saving is nobody's.
        if let previous = draft.receiptFile, previous != original.receiptFile { store.deleteReceipt(previous) }
        draft.receiptFile = name
    }

    private func cancel() {
        if let file = draft.receiptFile, file != original.receiptFile { store.deleteReceipt(file) }
        dismiss()
    }

    private func save() {
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = draft.category.label }
        if let old = original.receiptFile, old != draft.receiptFile, !isNew { store.deleteReceipt(old) }
        store.save(draft)
        onSaved?(draft)
        dismiss()
    }
}

struct ReceiptViewer: View {
    let url: URL?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url, let image = UIImage(contentsOfFile: url.path) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                } else {
                    ContentUnavailableView("No receipt", systemImage: "doc.text.image")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if let url {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: url)
                    }
                }
            }
        }
    }
}

struct BudgetEditor: View {
    @EnvironmentObject var store: FamilyStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Expense.Category.allCases) { category in
                        HStack {
                            Label(category.label, systemImage: category.symbol)
                            Spacer()
                            AmountField(title: "No budget", cents: Binding(
                                get: { store.data.budgetCents(for: category) },
                                set: { store.setBudget($0, for: category) }))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                    }
                } footer: {
                    Text("Monthly amounts. Leave blank for no budget.")
                }
            }
            .navigationTitle("Monthly Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension UIImage {
    /// Receipt photos don't need 12 megapixels.
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
