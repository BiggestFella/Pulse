# Workout Builder & Set-Editing Fixes Implementation Plan (Part B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three workout-builder UX defects from testing feedback — exercises can't be reordered, multi-select loses tap order, and the reps field can't be cleared / lacks +/- steppers / has misaligned column headers.

**Architecture:** SwiftUI + `@Observable` MVVM. Reorder logic and selection-order are model concerns (unit-tested in `WorkoutBuilderModelTests`); the picker and set-editor changes are view-local SwiftUI state (verified via the existing UI test target). No data-layer or schema changes.

**Tech Stack:** SwiftUI (iOS 17+), Swift Concurrency, XCTest. Project generated via XcodeGen (`project.yml`); source folders are globbed, so editing existing files needs no `xcodegen generate`.

**Source spec:** `docs/superpowers/specs/2026-06-11-library-folders-and-builder-fixes-design.md` (Part B).

**Test command (unit gate):**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests test
```
The `-only-testing:PulseTests` gate is mandatory — the PulseUITests runner crashes on the current Xcode/iOS (known defect); UI-test changes are committed but not run as the gate.

---

## File Structure

- Modify `Pulse/Features/Builders/WorkoutBuilderModel.swift` — add `move(from:to:)`; add `isReordering` flag.
- Modify `Pulse/Features/Builders/WorkoutBuilderView.swift` — reorder edit mode (flat `List` + `.onMove`); a Reorder toggle.
- Modify `Pulse/Features/Builders/ExercisePickerSheet.swift` — selection becomes an ordered array so tap order is preserved.
- Modify `Pulse/Features/Builders/SetEditorSheet.swift` — reps becomes a clearable string-bound field with +/- steppers; header columns use the data row's fixed widths.
- Modify `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift` — new tests for `move` and selection-order.

---

## Task 1: Reorder — model `move(from:to:)`

**Files:**
- Modify: `Pulse/Features/Builders/WorkoutBuilderModel.swift`
- Test: `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `WorkoutBuilderModelTests`:

```swift
func testMoveReordersItems() {
    let model = makeModel()                 // seeded: [Flat bench, Incline press]
    let firstID = model.items[0].id
    model.move(from: IndexSet(integer: 0), to: 2)   // move row 0 to the end
    XCTAssertEqual(model.items.last?.id, firstID)
    XCTAssertEqual(model.items.count, 2)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutBuilderModelTests/testMoveReordersItems test
```
Expected: FAIL — `value of type 'WorkoutBuilderModel' has no member 'move'` (compile error).

- [ ] **Step 3: Write minimal implementation**

In `WorkoutBuilderModel.swift`, after `removeItem(id:)` (around line 73), add:

```swift
/// Reorder exercises (drag-to-move from the builder's edit mode). Operates on
/// the flat `items` array; moving a row out of a contiguous superset run
/// naturally breaks that run, which matches the user's intent.
func move(from source: IndexSet, to destination: Int) {
    items.move(fromOffsets: source, toOffset: destination)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutBuilderModelTests/testMoveReordersItems test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/WorkoutBuilderModel.swift PulseTests/Features/Builders/WorkoutBuilderModelTests.swift
git commit -m "feat(builder): add move(from:to:) to reorder exercises [BAK-27]"
```

---

## Task 2: Reorder — edit-mode UI in the builder

**Files:**
- Modify: `Pulse/Features/Builders/WorkoutBuilderModel.swift`
- Modify: `Pulse/Features/Builders/WorkoutBuilderView.swift`

This is view wiring (no unit test; verified in the running app). The flat reorder list only appears while reordering, so the superset-card layout is untouched in normal mode.

- [ ] **Step 1: Add the edit-mode flag to the model**

In `WorkoutBuilderModel.swift`, with the other UI-state vars (near line 11), add:

```swift
var isReordering = false
```

- [ ] **Step 2: Add a Reorder toggle to the EXERCISES header**

In `WorkoutBuilderView.swift`, replace the header `HStack` (lines 28-34) with:

```swift
HStack {
    StatLabel("EXERCISES · \(model.items.count)")
        .accessibilityIdentifier("eyebrow-EXERCISES · \(model.items.count)")
    Spacer()
    if model.items.count > 1 {
        Button { model.isReordering.toggle() } label: {
            Text(model.isReordering ? "DONE" : "REORDER")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(theme.accent)
        }
        .accessibilityIdentifier("reorder-toggle")
    }
    StatLabel("\(model.totalSets) SETS")
        .accessibilityIdentifier("eyebrow-\(model.totalSets) SETS")
}
```

- [ ] **Step 3: Render the flat reorder list when editing**

In `WorkoutBuilderView.swift`, replace `exerciseList` (line 36) usage with a switch. Change line 36 from `exerciseList` to:

```swift
if model.isReordering { reorderList } else { exerciseList }
```

Then add this computed view next to `exerciseList` (after line 106):

```swift
/// Flat, drag-to-reorder list shown only in edit mode. Uses a plain List so
/// `.onMove` works; superset grouping is suspended here and recomputed from
/// `items` when the user leaves edit mode.
private var reorderList: some View {
    List {
        ForEach(model.items) { item in
            HStack(spacing: theme.spacing[2]) {
                Image(systemName: "line.3.horizontal").foregroundStyle(theme.inkFaint)
                Text(item.exercise.name)
                    .foregroundStyle(theme.ink)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("reorder-row-\(item.exercise.name)")
        }
        .onMove { model.move(from: $0, to: $1) }
    }
    .listStyle(.plain)
    .scrollDisabled(true)
    .frame(height: CGFloat(model.items.count) * 48)
    .environment(\.editMode, .constant(.active))
}
```

- [ ] **Step 4: Build and verify in the simulator**

Run:
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, PulseTests pass (this confirms the view compiles; reorder gesture itself is verified manually).

Then run the app (Library → + → workout builder), tap REORDER, drag a row, tap DONE — confirm order changes and persists into the saved workout.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/WorkoutBuilderModel.swift Pulse/Features/Builders/WorkoutBuilderView.swift
git commit -m "feat(builder): drag-to-reorder exercises in edit mode [BAK-27]"
```

---

## Task 3: Preserve exercise selection order in the picker

**Files:**
- Modify: `Pulse/Features/Builders/ExercisePickerSheet.swift`
- Test: `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`

`WorkoutBuilderModel.addExercises` already appends in the order it receives ids; the bug is the picker passing an unordered `Set`. First lock the model contract with a test, then fix the picker.

- [ ] **Step 1: Write the failing test (model contract)**

Add to `WorkoutBuilderModelTests`:

```swift
func testAddExercisesPreservesPassedOrder() async {
    let model = makeModel()
    await model.loadCatalog()
    // Three distinct catalog ids in a deliberate order.
    let a = model.catalog[0].exercises[0].id
    let b = model.catalog[1].exercises[0].id
    let c = model.catalog[1].exercises[1].id
    let before = model.items.count
    model.addExercises([c, a, b])
    let addedNames = Array(model.items.suffix(model.items.count - before)).map { $0.exercise.id }
    XCTAssertEqual(addedNames, [c, a, b])  // exact insertion order preserved
}
```

- [ ] **Step 2: Run test to verify it passes already (documents the contract)**

Run:
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutBuilderModelTests/testAddExercisesPreservesPassedOrder test
```
Expected: PASS. (The model already preserves order; this guards against regressions. The real defect is in the view — fixed next.)

- [ ] **Step 3: Change the picker selection to an ordered array**

In `ExercisePickerSheet.swift`, line 16, replace:

```swift
@State private var selected: Set<Exercise.ID> = []
```
with:
```swift
@State private var selected: [Exercise.ID] = []   // ordered by tap, preserved on confirm
```

- [ ] **Step 4: Update the three use sites to array semantics**

In `ExercisePickerSheet.swift`:

Line 103 — `onConfirm` already takes an array; simplify:
```swift
Button { onConfirm(selected) } label: {
```

Lines 114-119 (`row`) — replace the membership/toggle logic:
```swift
let added = alreadyAdded.contains(ex.id)
let isSel = selected.contains(ex.id)
let equipment = ex.variations.first?.equipment ?? ""
Button {
    guard !added else { return }
    if let i = selected.firstIndex(of: ex.id) { selected.remove(at: i) }
    else { selected.append(ex.id) }
} label: {
```

(`selected.isEmpty` / `selected.count` on lines 104 and 107 work unchanged on an array.)

- [ ] **Step 5: Build and verify**

Run:
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, PulseTests pass.

Then in the app: open the picker, tap exercises in a specific order (e.g. 3rd, then 1st, then 2nd), confirm — the builder list shows them in that tap order.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/Builders/ExercisePickerSheet.swift PulseTests/Features/Builders/WorkoutBuilderModelTests.swift
git commit -m "fix(builder): preserve exercise selection order in picker [BAK-27]"
```

---

## Task 4: Reps field — clearable input + steppers + header alignment

**Files:**
- Modify: `Pulse/Features/Builders/SetEditorSheet.swift`

View-local fix. The reps `TextField` uses `format: .number` on an `Int` binding, which blocks an empty intermediate state. Replace with a string-backed field that commits on blur, add +/- steppers for parity with RIR, and align the header columns to the data row's fixed widths. The model's existing `updateSet` (with `max(0,)` clamp) is the commit target — no model change.

- [ ] **Step 1: Add a focus state and fixed column widths**

In `SetEditorSheet.swift`, add to the struct's properties (after line 12):

```swift
// Per-row focus identity (the set index currently being typed into), so only
// the focused row shows its draft — a shared Bool would leak the draft to every row.
@FocusState private var focusedReps: Int?
@State private var repsDraft = ""
// Shared column widths so the header labels line up with the data row.
private let setColWidth: CGFloat = 28
private let repsColWidth: CGFloat = 132   // stepper(−) + value + stepper(+)
private let rirColWidth: CGFloat = 96
```

- [ ] **Step 2: Align the header row to those widths**

Replace the header `HStack` (lines 41-47) with:

```swift
HStack(spacing: theme.spacing[3]) {
    StatLabel("SET").frame(width: setColWidth, alignment: .leading)
    StatLabel("REPS").frame(width: repsColWidth, alignment: .center)
    StatLabel("RIR").frame(width: rirColWidth, alignment: .center)
    Spacer()
}
```

- [ ] **Step 3: Replace the reps TextField with a clearable, steppered field**

In `setRow` (lines 80-88), replace the reps `TextField` block with:

```swift
HStack(spacing: theme.spacing[1]) {
    Button("−") {
        model.updateSet(itemID: item.id, index: idx, reps: set.reps - 1, rir: set.rir, type: set.type)
    }
    .accessibilityIdentifier("set-reps-dec-\(idx)")

    TextField("0", text: Binding(
        get: { focusedReps == idx ? repsDraft : String(set.reps) },
        set: { repsDraft = $0.filter(\.isNumber) }))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .focused($focusedReps, equals: idx)
        .font(.system(size: 20, weight: .bold, design: .monospaced))
        .foregroundStyle(theme.ink)
        .frame(width: 56)
        .accessibilityIdentifier("set-reps-\(idx)")
        .onChange(of: focusedReps) { old, new in
            if new == idx {
                repsDraft = String(set.reps)            // entering this field — seed the draft
            } else if old == idx {
                let value = repsDraft.isEmpty ? 0 : (Int(repsDraft) ?? set.reps)
                model.updateSet(itemID: item.id, index: idx, reps: value, rir: set.rir, type: set.type)
            }
        }

    Button("+") {
        model.updateSet(itemID: item.id, index: idx, reps: set.reps + 1, rir: set.rir, type: set.type)
    }
    .accessibilityIdentifier("set-reps-inc-\(idx)")
}
.font(.system(size: 16, weight: .bold))
.foregroundStyle(theme.ink)
.frame(width: repsColWidth)
```

> Each row carries its own `.onChange(of: focusedReps)`: when focus moves from row *i* to row *j*, row *i* sees `old == idx` and commits its draft, while row *j* sees `new == idx` and seeds a fresh draft. The draft never leaks across rows because the `get:` only returns it when `focusedReps == idx`.

- [ ] **Step 4: Constrain the RIR group to its column width**

In `setRow`, the RIR `HStack` (lines 90-101) — add a width to match the header. After its `.foregroundStyle(theme.ink)` (line 103) add:

```swift
.frame(width: rirColWidth)
```

And constrain the SET badge: wrap `BuilderBadge(...)` (line 78) as:

```swift
BuilderBadge(text: "\(idx + 1)", tinted: set.type != .working)
    .frame(width: setColWidth, alignment: .leading)
```

- [ ] **Step 5: Build and verify**

Run:
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, PulseTests pass.

Then in the app, open a set editor: confirm (a) the reps field can be backspaced to empty and retyped, (b) +/- buttons change reps and clamp at 0, (c) the REPS and RIR labels sit directly above their fields.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/Builders/SetEditorSheet.swift
git commit -m "fix(builder): clearable reps field with steppers + aligned headers [BAK-27]"
```

---

## Task 5: Final verification

- [ ] **Step 1: Run the full unit gate**

Run:
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: TEST SUCCEEDED — all PulseTests pass, including `testMoveReordersItems` and `testAddExercisesPreservesPassedOrder`.

- [ ] **Step 2: Manual acceptance pass (running app)**

Confirm each Part B acceptance criterion from the spec:
- Selecting exercises in order A, B, C adds them in that order.
- Builder rows can be dragged to reorder (REORDER mode); order persists on save.
- The reps field clears to empty and retypes; +/- steppers adjust reps; REPS/RIR labels align with their fields.
