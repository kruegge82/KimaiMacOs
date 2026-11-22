import KimaiKit
import SwiftUI

/// Sheet for creating and correcting records.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var form: EditorModel
    @State private var showPicker = false
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field {
        case description
        case duration
    }

    init(request: EditorRequest) {
        _form = State(initialValue: EditorModel(request: request))
    }

    private var title: String {
        switch form.kind {
        case .create: L("New Entry")
        case .startTimer: L("Start Timer")
        case .edit: form.isRunning ? L("Edit Running Entry") : L("Edit Entry")
        }
    }

    private var saveTitle: String {
        form.kind == .startTimer ? L("Start") : L("Save")
    }

    var body: some View {
        @Bindable var form = form
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

            Form {
                Section {
                    TextField(
                        L("Description"), text: $form.description,
                        prompt: Text(L("What did you work on?")), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...6)
                        .multilineTextAlignment(.leading)
                        .focused($focus, equals: .description)
                    LabeledContent(L("Project")) {
                        BookingPickerButton(booking: $form.booking, isPresented: $showPicker)
                            .frame(maxWidth: 300)
                    }
                }
                Section {
                    DatePicker(L("Start"), selection: $form.begin)
                    if form.isRunning {
                        LabeledContent(L("End")) {
                            Text(form.kind == .startTimer ? L("Open – the timer starts running") : L("Still running"))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        DatePicker(L("End"), selection: $form.end)
                        LabeledContent(L("Duration")) {
                            TextField(L("Duration"), text: $form.durationText, prompt: Text(verbatim: "1:30"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .focused($focus, equals: .duration)
                                .help(L("For example 1:30, 1h 30m, 90m or 1,5 (hours)"))
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if !form.isRunning {
                            Text(L("Changing the duration moves the end. For example 1:30, 1h 30m or 1,5."))
                        }
                        timeZoneNote
                    }
                }
                Section {
                    TextField(L("Tags"), text: $form.tagsText, prompt: Text(L("Separated by commas")))
                    Toggle(L("Billable"), isOn: $form.billable)
                }
                if form.isExported {
                    Label(
                        L("This entry was exported. Kimai may refuse changes."),
                        systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                if let message = form.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(L("Error: %@", message))
                }
            }
            .formStyle(.grouped)
            .onSubmit(save)

            Divider()
            footer
        }
        .frame(width: 520)
        .onAppear { focus = .description }
        .onChange(of: focus) { old, _ in
            if old == .duration { form.commitDuration() }
        }
        .disabled(form.isSaving)
        .confirmationDialog(L("Delete this entry?"), isPresented: $confirmDelete) {
            Button(L("Delete"), role: .destructive, action: delete)
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The entry will be removed from Kimai. This cannot be undone."))
        }
    }

    @ViewBuilder
    private var timeZoneNote: some View {
        if let profileZone = model.user?.timeZone,
           profileZone.secondsFromGMT(for: form.begin) != TimeZone.current.secondsFromGMT(for: form.begin) {
            Text(L(
                "Times are shown in this Mac's time zone (%@). Your Kimai profile uses %@.",
                TimeZone.current.identifier, profileZone.identifier))
        }
    }

    private var footer: some View {
        HStack {
            if form.existingID != nil {
                Button(L("Delete…"), role: .destructive) { confirmDelete = true }
            }
            Spacer()
            if form.isSaving {
                ProgressView().controlSize(.small)
            }
            Button(L("Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(saveTitle, action: save)
                .keyboardShortcut(.defaultAction)
            // ⌘S as a second way to save, as in every document-style editor.
            Button("", action: save)
                .keyboardShortcut("s", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func save() {
        guard !form.isSaving else { return }
        form.commitDuration()
        if let message = form.validationMessage {
            form.errorMessage = message
            return
        }
        form.errorMessage = nil
        form.isSaving = true
        Task {
            let error: KimaiError?
            if let id = form.existingID {
                error = await model.update(id: id, changes: form.changes())
            } else {
                error = await model.create(form.draft())
            }
            form.isSaving = false
            if let error {
                // Keep the sheet open so nothing the user typed is lost.
                form.errorMessage = ErrorText.message(for: error)
            } else {
                dismiss()
            }
        }
    }

    private func delete() {
        guard let id = form.existingID,
              let entry = (model.entries + model.activeEntries).first(where: { $0.id == id })
        else { return }
        form.isSaving = true
        Task {
            let deleted = await model.delete(entry)
            form.isSaving = false
            if deleted { dismiss() }
        }
    }
}
