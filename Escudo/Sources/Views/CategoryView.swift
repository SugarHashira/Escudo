import Combine
import CoreData
import CoreHaptics
import Popovers
import SwiftUI
import UIKit

enum CategoryViewMode {
    case welcome, settings, transaction
}

struct CategoryView: View {
    var mode: CategoryViewMode
    @Namespace var animation

    @State var newCategory = false

    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""
    @State var positive = false

    var body: some View {
        VStack(spacing: 5) {
            CategoryListView(mode: mode, showToast: $showToast, toastTitle: $toastTitle, toastImage: $toastImage, positive: $positive)

            HStack {
                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                    Text("New")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                }
                .foregroundColor(Color.PrimaryText)
                .padding(6)
                .padding(.horizontal, 4.5)
                .background(Color.SecondaryBackground, in: Capsule())
                .contentShape(Rectangle())
                .onTapGesture {
                    newCategory = true
                }
            }
            .padding(25)
        }
        .sheet(isPresented: $newCategory) {
            if #available(iOS 16.0, *) {
                NewCategoryAlert(bottomSpacers: false)
                    .presentationDetents([.height(310)])
            } else {
                NewCategoryAlert(bottomSpacers: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: .all)
        .background(Color.PrimaryBackground)
    }
}

/// Reassigns all transactions in `category` to an "Unknown" catch-all before deletion.
/// Creates the Unknown category if it doesn't exist.
private func reassignToUnknown(category: Category, moc: NSManagedObjectContext) {
    let txs = (category.transactions as? Set<Transaction>) ?? []
    guard !txs.isEmpty else { return }

    // Find or create Unknown category matching same income type
    let req: NSFetchRequest<Category> = Category.fetchRequest()
    req.predicate = NSPredicate(format: "name == %@ AND income == %d", "Unknown", category.income)
    let unknown: Category
    if let existing = (try? moc.fetch(req))?.first {
        unknown = existing
    } else {
        let cat = Category(context: moc)
        cat.id          = UUID()
        cat.name        = "Unknown"
        cat.emoji       = "❓"
        cat.colour      = "8E8E93"
        cat.income      = category.income
        cat.dateCreated = Date()
        cat.order       = Int64.max
        unknown = cat
    }
    txs.forEach { $0.category = unknown }
}

struct CategoryListView: View {
    var mode: CategoryViewMode

    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var bottomEdge: Double = 15

    @AppStorage("categorySuggestions", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var showSuggestions: Bool = false
    @State var suggestionsToast = false

    @State private var offset: CGFloat = 0

    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)]) private var categories: FetchedResults<Category>

    @State var isEditing = false

    // delete mode
    @State private var deleteMode = false
    @State private var toDelete: Category?
    var alertMessage: String {
        "Delete '" + (toDelete?.wrappedName ?? "") + "'?"
    }

    // edit mode
    @State private var toEdit: Category?

    // toasts
    @Binding var showToast: Bool
    @Binding var toastTitle: String
    @Binding var toastImage: String
    @Binding var positive: Bool

    // force-refresh toggle for UserDefaults-backed flags
    @State private var refreshID = UUID()

    var toastColor: Color {
        positive ? Color.IncomeGreen : Color.AlertRed
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        VStack(spacing: 5) {
            if showToast {
                HStack(spacing: 6.5) {
                    Image(systemName: toastImage)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(toastColor)

                    Text(toastTitle)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                        .foregroundColor(toastColor)
                }
                .padding(8)
                .background(toastColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                .frame(maxWidth: 250)
                .frame(height: 35)
                .padding(20)
            } else {
                if mode == .welcome {
                    HStack(spacing: 8) {
                        if categories.count > 1 {
                            if isEditing {
                                Circle()
                                    .fill(Color.IncomeGreen.opacity(0.23))
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "checkmark")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                            .foregroundColor(Color.IncomeGreen)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            } else {
                                Circle()
                                    .fill(Color.SecondaryBackground)
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            }
                        }

                        Circle()
                            .fill(Color.SecondaryBackground)
                            .frame(width: 33, height: 33)
                            .overlay {
                                Image(systemName: showSuggestions ? "eye.slash" : "eye")
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    .foregroundColor(Color.SubtitleText)
                                    .offset(y: 0.8)
                            }
                            .onTapGesture {
                                withAnimation {
                                    showSuggestions.toggle()
                                }
                            }

                        Spacer()

                        Circle()
                            .fill(!categories.isEmpty ? Color.IncomeGreen.opacity(0.23) : Color.clear)
                            .frame(width: 33, height: 33)
                            .overlay {
                                ZStack {
                                    Image(systemName: "arrow.right")
                                        .font(.system(.callout, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(!categories.isEmpty ? Color.IncomeGreen : Color.Outline.opacity(0.8))

                                    if categories.count == 0 {
                                        Circle()
                                            .stroke(Color.Outline.opacity(0.4), lineWidth: 1.3)
                                            .frame(width: 33, height: 33)
                                    }
                                }
                            }
                            .onTapGesture {
                                if categories.count > 0 {
                                    dismiss()
                                }
                            }
                    }
                    .frame(height: 35)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text("Categories")
                            .font(.system(.title3, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .padding(20)

                } else {
                    HStack(spacing: 8) {
                        if mode == .settings {
                            Circle()
                                .fill(Color.SecondaryBackground)
                                .frame(width: 33, height: 33)
                                .overlay {
                                    Image(systemName: "chevron.left")
                                        .font(.system(.body, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(Color.SubtitleText)
                                        .offset(y: 0.8)
                                }
                                .onTapGesture {
                                    self.presentationMode.wrappedValue.dismiss()
                                }
                        } else {
                            Circle()
                                .fill(Color.SecondaryBackground)
                                .frame(width: 33, height: 33)
                                .overlay {
                                    Image(systemName: "chevron.down")
                                        .font(.system(.body, design: .rounded).weight(.semibold))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(Color.SubtitleText)
                                        .offset(y: 0.8)
                                }
                                .onTapGesture {
                                    dismiss()
                                }
                        }

                        Spacer()

                        Circle()
                            .fill(Color.SecondaryBackground)
                            .frame(width: 33, height: 33)
                            .overlay {
                                Image(systemName: showSuggestions ? "eye.slash" : "eye")
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                    .foregroundColor(Color.SubtitleText)
                                    .offset(y: 0.8)
                            }
                            .onTapGesture {
                                withAnimation {
                                    showSuggestions.toggle()
                                }
                            }

                        if categories.count > 1 {
                            if isEditing {
                                Circle()
                                    .fill(Color.IncomeGreen.opacity(0.23))
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "checkmark")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                            .foregroundColor(Color.IncomeGreen)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            } else {
                                Circle()
                                    .fill(Color.SecondaryBackground)
                                    .frame(width: 33, height: 33)
                                    .overlay {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.system(.callout, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                    .onTapGesture {
                                        withAnimation {
                                            isEditing.toggle()
                                        }
                                    }
                            }
                        }
                    }
                    .frame(height: 35)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text("Categories")
                            .font(.system(.title3, design: .rounded).weight(mode == .settings ? .semibold : .medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .padding(20)
                }
            }

            VStack {
                if #available(iOS 16.0, *) {
                    List {
                        Section(header: Text("ALL CATEGORIES").foregroundColor(Color.SubtitleText)) {
                            if categories.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "tray")
                                        .font(.system(.largeTitle, design: .rounded).weight(.light))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(Color.SubtitleText)

                                    Text("no_expense_categories")
                                        .font(.system(.body, design: .rounded).weight(.medium))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .italic()
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(Color.SubtitleText)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 37)
                                .listRowBackground(Color.SettingsBackground)
                            } else {
                                ForEach(categories) { category in
                                    CategoryRowView(category: category, toDelete: toDelete, onToggle: {
                                        refreshID = UUID()
                                    })
                                    .padding(.vertical, 5)
                                    .listRowBackground(Color.SettingsBackground)
                                    .listRowSeparatorTint(Color.Outline)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toEdit = category
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            toDelete = category
                                        } label: {
                                            Image(systemName: "trash.fill")
                                        }
                                        .tint(Color.AlertRed)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            toEdit = category
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .tint(Color("Yellow"))
                                    }
                                }
                                .onMove(perform: moveItem)
                            }
                        }
                    }
                    .id(refreshID)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                } else {
                    List {
                        Section(header: Text("ALL CATEGORIES").foregroundColor(Color.SubtitleText)) {
                            if categories.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "tray")
                                        .font(.system(.largeTitle, design: .rounded).weight(.light))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .foregroundColor(Color.SubtitleText)

                                    Text("No categories found, click the 'New' button to add some.")
                                        .font(.system(.body, design: .rounded).weight(.medium))
                                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(Color.SubtitleText)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 37)
                                .listRowBackground(Color.SettingsBackground)
                            } else {
                                ForEach(categories) { category in
                                    CategoryRowView(category: category, toDelete: toDelete, onToggle: {
                                        refreshID = UUID()
                                    })
                                    .padding(.vertical, 5)
                                    .listRowBackground(Color.SettingsBackground)
                                    .listRowSeparatorTint(Color.Outline)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toEdit = category
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            toDelete = category
                                        } label: {
                                            Image(systemName: "trash.fill")
                                        }
                                        .tint(Color.AlertRed)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            toEdit = category
                                        } label: {
                                            Image(systemName: "pencil")
                                        }
                                        .tint(Color("Yellow"))
                                    }
                                }
                                .onMove(perform: moveItem)
                            }
                        }
                    }
                    .id(refreshID)
                    .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: toDelete) { _ in
            if toDelete != nil {
                deleteMode = true
            }
        }
        .fullScreenCover(isPresented: $deleteMode, onDismiss: {
            toDelete = nil
        }) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        deleteMode = false
                    }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Delete '\(toDelete?.wrappedName ?? "")'?")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.PrimaryText)

                    Text("Transactions in this category will be moved to Unknown.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.SubtitleText)
                        .padding(.bottom, 15)

                    Button {
                        withAnimation {
                            if let gonnaDelete = toDelete {
                                reassignToUnknown(category: gonnaDelete, moc: moc)
                                moc.delete(gonnaDelete)
                            }
                            dataController.save()
                        }
                        toDelete = nil
                        deleteMode = false
                    } label: {
                        Text("Delete")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(height: 45)
                            .frame(maxWidth: .infinity)
                            .background(Color.AlertRed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .padding(.bottom, 8)

                    Button {
                        withAnimation(.easeOut(duration: 0.7)) {
                            deleteMode = false
                            offset = 0
                        }

                    } label: {
                        Text("Cancel")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.PrimaryText.opacity(0.9))
                            .frame(height: 45)
                            .frame(maxWidth: .infinity)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
                .offset(y: offset)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if gesture.translation.height < 0 {
                                offset = gesture.translation.height / 3
                            } else {
                                offset = gesture.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 20 {
                                deleteMode = false
                                offset = 0
                            } else {
                                withAnimation {
                                    offset = 0
                                }
                            }
                        }
                )
                .padding(.horizontal, 17)
                .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
            }
            .edgesIgnoringSafeArea(.all)
            .background(BackgroundBlurView())
        }
        .sheet(item: $toEdit, onDismiss: {
            toEdit = nil
            refreshID = UUID()
        }) { category in
            if #available(iOS 16.0, *) {
                EditCategoryAlert(toEdit: category, showRootToast: $showToast, rootToastTitle: $toastTitle, rootToastImage: $toastImage, positive: $positive, bottomSpacers: false)
                    .presentationDetents([.height(330)])
            } else {
                EditCategoryAlert(toEdit: category, showRootToast: $showToast, rootToastTitle: $toastTitle, rootToastImage: $toastImage, positive: $positive, bottomSpacers: true)
            }
        }
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: showSuggestions) { newValue in
            if !newValue {
                toastTitle = "Suggestions Hidden"
                toastImage = "eye.slash"
                showToast = true
                positive = true
            }
        }
    }

    private func moveItem(at sets: IndexSet, destination: Int) {
        let itemToMove = sets.first!

        if itemToMove < destination {
            var startIndex = itemToMove + 1
            let endIndex = destination - 1
            var startOrder = categories[itemToMove].order
            while startIndex <= endIndex {
                categories[startIndex].order = startOrder
                startOrder = startOrder + 1
                startIndex = startIndex + 1
            }
            categories[itemToMove].order = startOrder
        } else if destination < itemToMove {
            var startIndex = destination
            let endIndex = itemToMove - 1
            var startOrder = categories[destination].order + 1
            let newOrder = categories[destination].order
            while startIndex <= endIndex {
                categories[startIndex].order = startOrder
                startOrder = startOrder + 1
                startIndex = startIndex + 1
            }
            categories[itemToMove].order = newOrder
        }

        do {
            dataController.save()
        } catch {
            print(error.localizedDescription)
        }
    }

    init(mode: CategoryViewMode, showToast: Binding<Bool>, toastTitle: Binding<String>, toastImage: Binding<String>, positive: Binding<Bool>) {
        _showToast = showToast
        _toastTitle = toastTitle
        _toastImage = toastImage
        _positive = positive
        self.mode = mode
    }
}

// MARK: - Category row with type chips

struct CategoryRowView: View {
    @ObservedObject var category: Category
    let toDelete: Category?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(category.wrappedEmoji)
                    .font(.system(.subheadline, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Text(category.wrappedName)
                    .font(.system(.body, design: .rounded))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
                    .foregroundColor(toDelete == category ? Color.AlertRed : Color.PrimaryText)

                Spacer()

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(hex: category.wrappedColour))
                    .frame(width: 20, height: 20)
            }

            HStack(spacing: 6) {
                TypeChip(label: "Expense", active: category.usedForExpense, activeColor: Color.AlertRed) {
                    category.usedForExpense.toggle()
                    onToggle()
                }
                TypeChip(label: "Income", active: category.usedForIncome, activeColor: Color.IncomeGreen) {
                    category.usedForIncome.toggle()
                    onToggle()
                }
            }
        }
    }
}

struct TypeChip: View {
    let label: String
    let active: Bool
    let activeColor: Color
    let onTap: () -> Void

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundColor(active ? activeColor : Color.SubtitleText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(active ? activeColor.opacity(0.15) : Color.SecondaryBackground)
            )
            .overlay(
                Capsule().stroke(active ? activeColor.opacity(0.4) : Color.Outline.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Capsule())
            .onTapGesture {
                onTap()
            }
    }
}

struct NewCategoryAlert: View {
    let budgetMode: Bool
    let bottomSpacers: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    // existing categories (used for colour cycling)
    @FetchRequest(sortDescriptors: [SortDescriptor(\.order)], predicate: NSPredicate(format: "income = %d", false)) private var expenseCategories: FetchedResults<Category>
    @State private var availableColours: [String] = Color.colorArray.filter { $0 != "#" }

    // new flags
    @State private var forExpense: Bool = true
    @State private var forIncome: Bool = false

    // state
    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var showingColourPicker = false
    @State private var selectedColour: String = "#FFFFFF"

    @FocusState var focusedField: FocusedField?

    enum FocusedField: Hashable {
        case emoji, name
    }

    // toasts
    @State var outcome = CategoryError.none
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""
    @State var positive = false

    var toastColor: Color {
        positive ? Color.IncomeGreen : Color.AlertRed
    }

    var addButtonDisabled: Bool {
        return newName.trimmingCharacters(in: .whitespacesAndNewlines) == "" || newEmoji == ""
    }

    @State var showNativePicker: Bool = false
    @State var customSelectedColor = Color.white

    var body: some View {
        VStack {
            VStack {
                VStack {
                    if showToast {
                        HStack(spacing: 5) {
                            Image(systemName: toastImage)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundColor(toastColor)

                            Text(toastTitle)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .lineLimit(1)
                                .foregroundColor(toastColor)
                        }
                        .padding(6)
                        .background(toastColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                        .frame(maxWidth: 200)
                    } else {
                        Text("New Category")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .padding(.top, 4)
                    }
                }
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }
                }

                Spacer()

                ZStack {
                    EmojiTextField(text: $newEmoji)
                        .focused($focusedField, equals: .emoji)
                        .onReceive(Just(newEmoji), perform: { _ in
                            if String(self.newEmoji.onlyEmoji().suffix(1)) != self.newEmoji.onlyEmoji().prefix(1) {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().suffix(1))
                            } else {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().prefix(1))
                            }
                        })
                        .font(.system(size: 160))
                        .padding(8)
                        .frame(width: 80, height: 80, alignment: .center)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .emoji && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    if newEmoji == "" {
                        Image("emoji-happy")
                            .resizable()
                            .foregroundColor(Color.PrimaryText)
                            .frame(width: 35, height: 35, alignment: .center)
                            .allowsHitTesting(false)
                    }
                }

                Spacer()

                // Type flags
                HStack(spacing: 12) {
                    Toggle(isOn: $forExpense) {
                        Text("Expense")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .tint(Color.AlertRed)

                    Divider().frame(height: 24)

                    Toggle(isOn: $forIncome) {
                        Text("Income")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .tint(Color.IncomeGreen)
                }
                .padding(.horizontal, 4)

                Spacer()

                HStack {
                    Button {
                        showingColourPicker = true
                    } label: {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(hex: selectedColour))
                            .padding(8)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .frame(width: 50, height: 50)
                            .overlay {
                                if showingColourPicker {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color.SubtitleText, lineWidth: 2.2)
                                }
                            }
                    }
                    .popover(present: $showingColourPicker, attributes: {
                        $0.position = .absolute(
                            originAnchor: .topLeft,
                            popoverAnchor: .bottomLeft
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        ColourPickerView(selectedColor: $selectedColour, showMenu: $showingColourPicker, showNativePicker: $showNativePicker)
                            .environment(\.managedObjectContext, self.moc)

                    } background: {
                        Color.PrimaryBackground.opacity(0.3)
                    }

                    NormalTextField(text: $newName, placeholder: "Category Name", action: verification)
                        .focused($focusedField, equals: .name)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .foregroundColor(Color.PrimaryText)
                        .frame(height: 50)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .name && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    Button {
                        verification()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(Color.LightIcon)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .frame(width: 50, height: 50)
                            .background(Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(13)
            .frame(maxHeight: bottomSpacers ? 420 : .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: customSelectedColor) { _ in
            selectedColour = customSelectedColor.toHex() ?? "#FFFFFF"
        }
        .colorPickerSheet(isPresented: $showNativePicker, selection: $customSelectedColor, supportsAlpha: false, title: "")
        .onAppear {
            expenseCategories.forEach { category in
                if availableColours.contains(category.wrappedColour) {
                    availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                }
            }

            if availableColours.isEmpty {
                selectedColour = "#FFFFFF"
            } else {
                selectedColour = availableColours[0]
            }
        }
    }

    func verification() {
        // Use income=false for duplicate checking (order assignment purposes)
        let results = dataController.categoryCheck(name: newName, emoji: newEmoji, income: false)

        outcome = results.error

        if outcome != .none {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            switch outcome {
            case .incomplete:
                toastTitle = "Incomplete Entry"
                toastImage = "questionmark.app"
            case .missingEmoji:
                toastTitle = "Missing Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .missingName:
                toastTitle = "Missing Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            case .duplicate:
                toastTitle = "Duplicate Found"
                toastImage = "externaldrive"
            case .duplicateEmoji:
                toastTitle = "Duplicate Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .duplicateName:
                toastTitle = "Duplicate Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            default:
                return
            }

            positive = false
            showToast = true

        } else {
            toastTitle = "Added \(newName)"

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            let category = Category(context: moc)
            category.name = newName.trimmingCharacters(in: .whitespaces).capitalized
            category.emoji = newEmoji
            category.dateCreated = Date.now
            category.id = UUID()
            category.colour = selectedColour
            category.order = results.order
            // Keep CoreData income field based on primary use for backward compat
            category.income = forIncome && !forExpense
            dataController.save()

            // Set new UserDefaults flags
            category.usedForExpense = forExpense
            category.usedForIncome = forIncome

            newName = ""
            newEmoji = ""

            availableColours = Color.colorArray.filter { $0 != "#" }
            expenseCategories.forEach { cat in
                if availableColours.contains(cat.wrappedColour) {
                    availableColours.remove(at: availableColours.firstIndex(of: cat.wrappedColour) ?? 0)
                }
            }

            if availableColours.isEmpty {
                selectedColour = "#FFFFFF"
            } else {
                selectedColour = availableColours[0]
            }

            if budgetMode {
                dismiss()
                return
            } else {
                focusedField = .emoji
                toastImage = "checkmark.circle.fill"
                positive = true
                showToast = true
            }
        }
    }

    init(bottomSpacers: Bool, budgetMode: Bool = false) {
        self.budgetMode = budgetMode
        self.bottomSpacers = bottomSpacers
    }
}

struct EditCategoryAlert: View {
    let toEdit: Category
    @Binding var showRootToast: Bool
    @Binding var rootToastTitle: String
    @Binding var rootToastImage: String
    @Binding var positive: Bool

    let bottomSpacers: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var moc
    @Environment(\.colorScheme) var systemColorScheme
    @EnvironmentObject var dataController: DataController

    // state
    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var showingColourPicker = false
    @State private var selectedColour: String = "#FFFFFF"
    @State private var forExpense: Bool = true
    @State private var forIncome: Bool = false

    @FocusState var focusedField: FocusedField?

    enum FocusedField: Hashable {
        case emoji, name
    }

    // toasts
    @State var outcome = CategoryError.none
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    // delete mode
    @State private var deleteMode = false
    @State private var toDelete: Category?
    var alertMessage: String {
        "Delete '" + (toDelete?.wrappedName ?? "") + "'?"
    }

    @State var showNativePicker: Bool = false
    @State var customSelectedColor = Color.white

    var body: some View {
        VStack {
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }

                    Spacer()

                    if showToast {
                        HStack(spacing: 5) {
                            Image(systemName: toastImage)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .foregroundColor(Color.AlertRed)

                            Text(toastTitle)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                .lineLimit(1)
                                .foregroundColor(Color.AlertRed)
                        }
                        .padding(6)
                        .background(Color.AlertRed.opacity(0.23), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                        .frame(maxWidth: 200)
                    } else {
                        Text("Edit Category")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }

                    Spacer()

                    Button {
                        toDelete = toEdit
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundColor(Color.AlertRed)
                            .padding(7)
                            .background(Color.AlertRed.opacity(0.23), in: Circle())
                            .contentShape(Circle())
                    }
                }
                .frame(height: 30)

                Spacer()

                ZStack {
                    EmojiTextField(text: $newEmoji)
                        .focused($focusedField, equals: .emoji)
                        .onReceive(Just(newEmoji), perform: { _ in
                            if String(self.newEmoji.onlyEmoji().suffix(1)) != self.newEmoji.onlyEmoji().prefix(1) {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().suffix(1))
                            } else {
                                self.newEmoji = String(self.newEmoji.onlyEmoji().prefix(1))
                            }
                        })
                        .font(.system(size: 160))
                        .padding(8)
                        .frame(width: 80, height: 80, alignment: .center)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .emoji && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    if newEmoji == "" {
                        Image("emoji-happy")
                            .resizable()
                            .foregroundColor(Color.PrimaryText)
                            .frame(width: 35, height: 35, alignment: .center)
                            .allowsHitTesting(false)
                    }
                }

                Spacer()

                // Type flags
                HStack(spacing: 12) {
                    Toggle(isOn: $forExpense) {
                        Text("Expense")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .tint(Color.AlertRed)

                    Divider().frame(height: 24)

                    Toggle(isOn: $forIncome) {
                        Text("Income")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .tint(Color.IncomeGreen)
                }
                .padding(.horizontal, 4)

                Spacer()

                HStack {
                    Button {
                        showingColourPicker = true
                    } label: {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(hex: selectedColour))
                            .padding(8)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .frame(width: 50, height: 50)
                            .overlay {
                                if showingColourPicker {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color.SubtitleText, lineWidth: 2.2)
                                }
                            }
                    }
                    .popover(present: $showingColourPicker, attributes: {
                        $0.position = .absolute(
                            originAnchor: .topLeft,
                            popoverAnchor: .bottomLeft
                        )
                        $0.rubberBandingMode = .none
                        $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
                        $0.presentation.animation = .easeInOut(duration: 0.2)
                        $0.dismissal.animation = .easeInOut(duration: 0.3)
                    }) {
                        ColourPickerView(selectedColor: $selectedColour, showMenu: $showingColourPicker, showNativePicker: $showNativePicker, toEdit: toEdit)
                            .environment(\.managedObjectContext, self.moc)

                    } background: {
                        Color.PrimaryBackground.opacity(0.3)
                    }

                    NormalTextField(text: $newName, placeholder: "Category Name", action: verification)
                        .focused($focusedField, equals: .name)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .frame(height: 50)
                        .foregroundColor(Color.PrimaryText)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder((focusedField == .name && !showingColourPicker) ? Color.SubtitleText : Color.clear, lineWidth: 2.2)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.SecondaryBackground))
                        }

                    Button {
                        verification()
                    } label: {
                        Image(systemName: "checkmark")
                            .foregroundColor(Color.LightIcon)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .frame(width: 50, height: 50)
                            .background(Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(13)
            .frame(maxHeight: bottomSpacers ? 420 : .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .fullScreenCover(item: $toDelete, onDismiss: {
            toDelete = nil
        }) { category in
            DeleteCategoryAlert(toDelete: category, deleted: $deleteMode)
        }
        .onChange(of: customSelectedColor) { _ in
            selectedColour = customSelectedColor.toHex() ?? "#FFFFFF"
        }
        .colorPickerSheet(isPresented: $showNativePicker, selection: $customSelectedColor, supportsAlpha: false, title: "")
        .onChange(of: deleteMode) { _ in
            dismiss()
        }
        .onAppear {
            newName = toEdit.wrappedName
            newEmoji = toEdit.wrappedEmoji
            selectedColour = toEdit.wrappedColour
            forExpense = toEdit.usedForExpense
            forIncome = toEdit.usedForIncome
        }
    }

    func verification() {
        let results = dataController.categoryCheckEdit(name: newName, emoji: newEmoji, toEdit: toEdit)

        outcome = results.error

        if outcome != .none {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            switch outcome {
            case .incomplete:
                toastTitle = "Incomplete Entry"
                toastImage = "questionmark.app"
            case .missingEmoji:
                toastTitle = "Missing Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .missingName:
                toastTitle = "Missing Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            case .duplicate:
                toastTitle = "Duplicate Found"
                toastImage = "externaldrive"
            case .duplicateEmoji:
                toastTitle = "Duplicate Emoji"
                toastImage = "person.fill"
                focusedField = .emoji
            case .duplicateName:
                toastTitle = "Duplicate Name"
                toastImage = "character.cursor.ibeam"
                focusedField = .name
            default:
                return
            }

            showToast = true
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            toEdit.name = newName.trimmingCharacters(in: .whitespaces).capitalized
            toEdit.emoji = newEmoji
            toEdit.colour = selectedColour
            // Update UserDefaults flags
            toEdit.usedForExpense = forExpense
            toEdit.usedForIncome = forIncome
            // Keep CoreData income consistent
            toEdit.income = forIncome && !forExpense

            dataController.save()

            rootToastTitle = "Edited \(newName)"
            rootToastImage = "checkmark.circle.fill"
            positive = true
            showRootToast = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                dismiss()
            }
        }
    }
}

struct DeleteCategoryAlert: View {
    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss
    let toDelete: Category
    @Binding var deleted: Bool
    @Environment(\.colorScheme) var systemColorScheme

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            VStack(alignment: .leading, spacing: 1.5) {
                Text("Delete '\(toDelete.wrappedName)'?")
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.PrimaryText)

                Text("Transactions will be moved to Unknown, not deleted.")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundColor(.SubtitleText)
                    .padding(.bottom, 15)
                    .accessibility(hidden: true)

                Button {
                    deleted = true
                    dismiss()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            reassignToUnknown(category: toDelete, moc: moc)
                            moc.delete(toDelete)
                            dataController.save()
                        }
                    }

                } label: {
                    Text("Delete")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundColor(.white)
                        .frame(height: 45)
                        .frame(maxWidth: .infinity)
                        .background(Color.AlertRed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .padding(.bottom, 8)

                Button {
                    withAnimation(.easeOut(duration: 0.7)) {
                        dismiss()
                    }

                } label: {
                    Text("Cancel")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.PrimaryText.opacity(0.9))
                        .frame(height: 45)
                        .frame(maxWidth: .infinity)
                        .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .padding(13)
//            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
            .offset(y: offset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.height < 0 {
                            offset = gesture.translation.height / 3
                        } else {
                            offset = gesture.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 20 {
                            dismiss()
                        } else {
                            withAnimation {
                                offset = 0
                            }
                        }
                    }
            )
//            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
//                .onEnded({ value in
//                    if value.translation.height > 0 {
//                        dismiss()
//                    }
//                }))
            .padding(.horizontal, 17)
            .padding(.bottom, bottomEdge == 0 ? 13 : bottomEdge)
        }
        .edgesIgnoringSafeArea(.all)
        .background(BackgroundBlurView())
    }
}

struct SuggestedCategoriesView: View {
    let income: Bool
    @FetchRequest private var categories: FetchedResults<Category>

    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController

    var nameArray: [String] {
        var emptyArray = [String]()

        categories.forEach { category in
            emptyArray.append(category.wrappedName)
        }

        return emptyArray
    }

    var emojiArray: [String] {
        var emptyArray = [String]()

        categories.forEach { category in
            emptyArray.append(category.wrappedEmoji)
        }

        return emptyArray
    }

    var suggestions: [SuggestedCategory] {
        var holding = [SuggestedCategory]()

        if income {
            SuggestedCategory.incomes.forEach { category in
                if !nameArray.contains(category.name) && !emojiArray.contains(category.emoji) {
                    holding.append(category)
                }
            }
        } else {
            SuggestedCategory.expenses.forEach { category in
                if !nameArray.contains(category.name) && !emojiArray.contains(category.emoji) {
                    holding.append(category)
                }
            }
        }

        return holding
    }

    @State private var availableColours: [String] = Color.colorArray.filter { $0 != "#" }
    @State private var selectedColour = "1"

    var body: some View {
        if !suggestions.isEmpty {
            Section(header: Text("SUGGESTED").foregroundColor(Color.SubtitleText)) {
                ForEach(suggestions, id: \.self) { category in
                    HStack(spacing: 8) {
                        Text(category.emoji)
//                            .font(.system(size: 15))
                            .font(.system(.subheadline, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Text(LocalizedStringKey(category.name))
                            .font(.system(.body, design: .rounded))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 18.5, weight: .regular, design: .rounded))
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "plus")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
//                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(4)
                            .background(Color.SecondaryBackground, in: Circle())
                            .contentShape(Circle())
                    }
                    .padding(.vertical, 5)
                    .foregroundColor(Color.PrimaryText)
                    .listRowBackground(Color.SettingsBackground)
                    .listRowSeparatorTint(Color.Outline)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // double check

                        let (outcome, _) = dataController.categoryCheck(name: category.name, emoji: category.emoji, income: income)

                        if outcome != .none {
                            return
                        }

                        let impactMed = UIImpactFeedbackGenerator(style: .light)
                        impactMed.impactOccurred()

                        if !income {
                            let suggestedCategory = Category(context: moc)
                            suggestedCategory.name = NSLocalizedString(category.name, comment: "category name")
                            suggestedCategory.emoji = category.emoji
                            suggestedCategory.dateCreated = Date.now
                            suggestedCategory.id = UUID()
                            suggestedCategory.colour = selectedColour
                            suggestedCategory.order = (categories.last?.order ?? 0) + 1
                            suggestedCategory.income = false
                            dataController.save()

                            availableColours = Color.colorArray.filter { $0 != "#" }
                            categories.forEach { category in
                                if availableColours.contains(category.wrappedColour) {
                                    availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                                }
                            }

                            if availableColours.isEmpty {
                                selectedColour = "#FFFFFF"
                            } else {
                                selectedColour = availableColours[0]
                            }
                        } else {
                            let suggestedCategory = Category(context: moc)
                            suggestedCategory.name = NSLocalizedString(category.name, comment: "category name")
                            suggestedCategory.emoji = category.emoji
                            suggestedCategory.dateCreated = Date.now
                            suggestedCategory.id = UUID()
                            suggestedCategory.colour = "#76FBB0"
                            suggestedCategory.order = (categories.last?.order ?? 0) + 1
                            suggestedCategory.income = true
                            dataController.save()
                        }
                    }
                }
            }
            .onAppear {
                if !income {
                    categories.forEach { category in
                        if availableColours.contains(category.wrappedColour) {
                            availableColours.remove(at: availableColours.firstIndex(of: category.wrappedColour) ?? 0)
                        }
                    }

                    if availableColours.isEmpty {
                        selectedColour = "#FFFFFF"
                    } else {
                        selectedColour = availableColours[0]
                    }
                }
            }
        }
    }

    init(income: Bool) {
        _categories = FetchRequest<Category>(sortDescriptors: [
            SortDescriptor(\.order)
        ], predicate: NSPredicate(format: "income = %d", income))

        self.income = income
    }
}

class UIEmojiTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        .activeInputModes.first(where: { $0.primaryLanguage == "emoji" })
    }

    override func caretRect(for _: UITextPosition) -> CGRect {
        return CGRect.zero
    }
}

struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeUIView(context: Context) -> UIEmojiTextField {
        let emojiTextField = UIEmojiTextField()
        emojiTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        emojiTextField.placeholder = placeholder
        emojiTextField.text = text
        emojiTextField.delegate = context.coordinator
        emojiTextField.font = UIFont(name: "HelveticaNeue", size: 50)
        emojiTextField.textAlignment = .center
        emojiTextField.endFloatingCursor()
        emojiTextField.becomeFirstResponder()
        return emojiTextField
    }

    func updateUIView(_ uiView: UIEmojiTextField, context _: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiTextField

        init(parent: EmojiTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = textField.text ?? ""
            }
        }
    }
}

struct NormalTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var action: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.placeholder = placeholder
        textField.autocapitalizationType = .words
        textField.text = text
        textField.delegate = context.coordinator

        textField.font = UIFont.roundedSpecial(ofStyle: .title2, weight: .medium, size: 17)
//
//        UIFont.rounded(ofSize: 20, weight: .medium)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context _: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NormalTextField

        init(parent: NormalTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.text = textField.text ?? ""
            }
        }

        func textFieldShouldReturn(_: UITextField) -> Bool {
            parent.action()

            return true
        }
    }
}

struct ColourPickerView: View {
    var selectedColours: [String]

    @Binding var showMenu: Bool
    @Binding var selectedColour: String

    @Binding var showNativePicker: Bool

    @State var customMode: Bool = false
    @State var customSelectedColor = Color.white

    @State var testing = false
    let columns = [
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40), spacing: 6),
        GridItem(.fixed(40))
    ]

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Color.colorArray, id: \.self) { suggestedColor in
                if suggestedColor == "#" {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .pink]), center: .center))

                        RoundedRectangle(cornerRadius: 6)
                            .fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground"))
                            .padding(4)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(customSelectedColor)
                            .padding(8)

                        if customMode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(customSelectedColor.luminance() > 0.5 ? Color.black : Color.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.black)
                        }
                    }
                    .frame(width: 40, height: 40, alignment: .center)
                    .onTapGesture {
                        showMenu = false
                        showNativePicker = true
                    }
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: suggestedColor))
                        .frame(height: 40)
                        .opacity(selectedColours.contains(suggestedColor) ? 0.2 : 1)
                        .onTapGesture {
                            if !selectedColours.contains(suggestedColor) {
                                withAnimation {
                                    selectedColour = suggestedColor
                                    customMode = false
                                    showMenu = false
                                }
                            }
                        }
                        .overlay {
                            if selectedColour == suggestedColor && !customMode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color(hex: suggestedColor).luminance() > 0.5 ? Color.black : Color.white)
                            }
                        }
                }
            }
        }
        .padding(6)
        .frame(width: 282)
        .background(RoundedRectangle(cornerRadius: 9).fill(darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
    }

    init(selectedColor: Binding<String>, showMenu: Binding<Bool>, showNativePicker: Binding<Bool>, toEdit: Category? = nil) {
        _selectedColour = selectedColor
        _showMenu = showMenu
        _showNativePicker = showNativePicker

        if !Color.colorArray.contains(selectedColor.wrappedValue) {
            _customMode = State(initialValue: true)
            _customSelectedColor = State(initialValue: Color(hex: selectedColor.wrappedValue))
        }

        var selectedColours = [String]()

        let dataController = DataController.shared

        let categories = dataController.getAllCategories(income: false)

        categories.forEach { category in
            selectedColours.append(category.wrappedColour)
        }

        if let editted = toEdit {
            if !selectedColours.isEmpty {
                selectedColours.remove(at: selectedColours.firstIndex(of: editted.wrappedColour) ?? 0)
            }
        }

        self.selectedColours = selectedColours
    }
}

struct OpenAICompletionsResponse: Decodable {
    let id: String
    let choices: [OpenAICompletionsOptions]
}

struct OpenAICompletionsOptions: Decodable {
    let text: String
}
