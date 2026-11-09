import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: FamilyStore
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Router.Tab.today)
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Router.Tab.calendar)
            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(Router.Tab.tasks)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(store.data.messagesNeedingReview.count)
                .tag(Router.Tab.inbox)
            SpendingView()
                .tabItem { Label("Spending", systemImage: "chart.bar") }
                .tag(Router.Tab.spending)
        }
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded }, set: { hasOnboarded = !$0 })) {
            OnboardingView { hasOnboarded = true }
                .environmentObject(store)
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { store.saveNow() }
        }
        .alert("Saved data couldn't be opened",
               isPresented: Binding(get: { store.loadProblem != nil }, set: { if !$0 { store.loadProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.loadProblem ?? "")
        }
    }
}

/// First launch: add the family, or look around with a sample one.
struct OnboardingView: View {
    @EnvironmentObject var store: FamilyStore
    let finish: () -> Void
    @State private var editing: FamilyMember? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "house.and.flag.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                        Text("Welcome to Kinboard").font(.largeTitle.bold())
                        Text("One place for the family calendar, to-dos, kids' trackers, spending, and all the messages from school, daycare and coaches.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(store.data.members) { m in
                        Button {
                            editing = m
                        } label: {
                            HStack {
                                MemberAvatar(member: m)
                                Text(m.name).foregroundStyle(.primary)
                                Spacer()
                                Text(m.role.label).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        editing = FamilyMember(name: "",
                                               role: store.data.members.contains(where: { $0.role == .parent }) ? .child : .parent,
                                               color: PaletteColor.allCases[store.data.members.count % PaletteColor.allCases.count])
                    } label: {
                        Label("Add a person", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Who's in your family?")
                } footer: {
                    Text("Add yourself, a partner, the kids — anyone whose schedule belongs here. Everything stays on this device.")
                }

                Section {
                    Button {
                        finish()
                    } label: {
                        Text(store.data.members.isEmpty ? "Skip for now" : "Get started")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)

                    if store.data.members.isEmpty {
                        Button {
                            store.loadSample()
                            finish()
                        } label: {
                            Text("Explore with a sample family")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .sheet(item: $editing) { member in
                MemberEditor(member: member)
            }
        }
    }
}
