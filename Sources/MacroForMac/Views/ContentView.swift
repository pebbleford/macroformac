import SwiftUI
import MacroCore

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var selectedStepID: MacroStep.ID?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacroListView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } content: {
            Group {
                if let id = app.selectedMacroID, app.macros[id: id] != nil {
                    MacroDetailView(
                        macro: $app.macros.element(id: id).unwrapped(or: Macro(id: id, name: "")),
                        selectedStepID: $selectedStepID
                    )
                    .id(id)
                } else {
                    EmptyLibraryView()
                }
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 460)
        } detail: {
            if let macroID = app.selectedMacroID,
               let stepID = selectedStepID,
               app.macros[id: macroID]?.steps[id: stepID] != nil {
                StepEditorView(
                    step: $app.macros.element(id: macroID)
                        .unwrapped(or: Macro(id: macroID, name: ""))
                        .steps
                        .element(id: stepID)
                        .unwrapped(or: MacroStep(id: stepID, action: .delay(.init())))
                )
                .id(stepID)
            } else {
                PlaceholderView(
                    symbol: "slider.horizontal.3",
                    title: "No Step Selected",
                    message: "Select a step to edit it, or use + to add one."
                )
            }
        }
        .frame(minWidth: 940, minHeight: 540)
        // A floating card, not part of the columns: putting it inside a split-view column broke
        // that column's layout so the sidebar and editor were never drawn.
        .overlay(alignment: .bottom) {
            if !app.accessibilityGranted || Permissions.isTranslocated {
                PermissionBanner()
                    .frame(maxWidth: 640)
                    .padding(16)
            }
        }
        .onChange(of: app.selectedMacroID) { _ in
            selectedStepID = nil
        }
        .onAppear {
            app.openMainWindowAction = { openWindow(id: "main") }
            app.refreshPermissions()
        }
    }
}

extension Binding {
    /// A binding to the element with the given id in an array binding (nil if it's gone).
    func element<Element: Identifiable>(id: Element.ID) -> Binding<Element?> where Value == [Element] {
        Binding<Element?>(
            get: { self.wrappedValue[id: id] },
            set: { self.wrappedValue[id: id] = $0 }
        )
    }

    /// Turns a `Binding<T?>` into a `Binding<T>`, using `fallback` if the value disappears
    /// (e.g. while a deleted item animates away).
    func unwrapped<Wrapped>(or fallback: Wrapped) -> Binding<Wrapped> where Value == Wrapped? {
        Binding<Wrapped>(
            get: { self.wrappedValue ?? fallback },
            set: { self.wrappedValue = $0 }
        )
    }
}

struct PlaceholderView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyLibraryView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            Text(app.macros.isEmpty ? "No Macros Yet" : "No Macro Selected")
                .font(.title2.weight(.semibold))
            Text("A macro is a list of steps — typing, shortcuts, clicks, apps, scripts — that runs with one click or a keyboard shortcut.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack {
                Button {
                    app.addMacro()
                } label: {
                    Label("New Macro", systemImage: "plus")
                }
                Button {
                    app.startRecording(into: nil)
                } label: {
                    Label("Record a Macro", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
