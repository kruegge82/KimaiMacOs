import Foundation
import KimaiKit
import Observation

/// Form state of the entry editor.
///
/// Kimai stores times with seconds, the form shows whole minutes. To keep an edit from
/// changing anything the user did not touch, the form remembers which of start, end and
/// duration were actually edited and only those are written back.
@Observable
final class EditorModel {
    enum Kind: Equatable {
        /// New finished record.
        case create
        /// New running timer (no end yet).
        case startTimer
        case edit(id: Int)
    }

    let kind: Kind
    /// Running records have no end; editing them never stops them.
    let isRunning: Bool
    let isExported: Bool
    /// The record as Kimai has it; `nil` for new records.
    private let original: Timesheet?
    private let initialBillable: Bool

    var description: String
    var booking: Booking?
    var begin: Date {
        didSet {
            guard begin != oldValue else { return }
            beginEdited = true
            showDuration()
        }
    }
    var end: Date {
        didSet {
            guard end != oldValue else { return }
            endEdited = true
            showDuration()
        }
    }
    var durationText = "" {
        didSet { if durationText != oldValue, !isShowingDuration { durationEdited = true } }
    }
    var durationIsValid = true
    var tagsText: String
    var billable: Bool
    var isSaving = false
    var errorMessage: String?

    private(set) var beginEdited = false
    private(set) var endEdited = false
    private(set) var durationEdited = false
    @ObservationIgnored private var isShowingDuration = false

    init(request: EditorRequest) {
        let draft: TimesheetDraft
        switch request.mode {
        case .create(let value):
            draft = value
            kind = value.end == nil ? .startTimer : .create
            isExported = false
            original = nil
        case .edit(let timesheet):
            draft = TimesheetDraft(timesheet: timesheet)
            kind = .edit(id: timesheet.id)
            isExported = timesheet.exported
            original = timesheet
        }
        isRunning = draft.end == nil
        description = draft.description
        booking = draft.projectID.flatMap { projectID in
            draft.activityID.map { Booking(projectID: projectID, activityID: $0) }
        }
        begin = Self.wholeMinute(draft.begin)
        end = Self.wholeMinute(draft.end ?? Date())
        tagsText = draft.tags.joined(separator: ", ")
        billable = draft.billable ?? true
        initialBillable = draft.billable ?? true
        showDuration()
    }

    private static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    var existingID: Int? {
        if case .edit(let id) = kind { return id }
        return nil
    }

    /// The start as it will be stored: the record's exact time unless the user changed it.
    private var effectiveBegin: Date {
        if let original, !beginEdited { return original.begin }
        return begin
    }

    private var effectiveEnd: Date {
        if let originalEnd = original?.end, !endEdited { return originalEnd }
        return end
    }

    var durationSeconds: Int { Int(effectiveEnd.timeIntervalSince(effectiveBegin)) }

    /// Writes the current duration into the text field without marking it as edited.
    private func showDuration() {
        guard !isRunning else { return }
        isShowingDuration = true
        durationText = durationSeconds > 0 ? DurationFormat.clock(durationSeconds) : ""
        isShowingDuration = false
        durationEdited = false
        durationIsValid = true
    }

    /// Applies a duration the user typed by moving the end; the start stays where it is.
    /// Does nothing if the field was not edited, so saving never recalculates times from
    /// the rounded display value.
    func commitDuration() {
        guard !isRunning, durationEdited else { return }
        let trimmed = durationText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showDuration()
            return
        }
        guard let seconds = DurationFormat.parse(trimmed), seconds >= 60 else {
            durationIsValid = false
            return
        }
        // Measured from the stored start (which may carry seconds), so the record really
        // gets the duration that was typed. Even if this happens to equal the displayed
        // end, it counts as an edit.
        end = effectiveBegin.addingTimeInterval(Double(seconds))
        endEdited = true
        showDuration()
    }

    /// First reason why the form cannot be saved, or `nil` if it can.
    var validationMessage: String? {
        if booking == nil { return L("Choose a project and an activity.") }
        if !isRunning {
            if !durationIsValid { return L("Enter the duration like 1:30, 1h 30m or 1,5.") }
            if effectiveEnd <= effectiveBegin { return L("The end has to be after the start.") }
        }
        return nil
    }

    var tags: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// What the user changed on an existing record. Untouched fields are left out.
    func changes() -> TimesheetChanges {
        guard let original else { return TimesheetChanges() }
        var changes = TimesheetChanges()
        if description.trimmingCharacters(in: .whitespacesAndNewlines) != original.trimmedDescription {
            changes.description = description
        }
        let originalBooking = original.projectID.flatMap { projectID in
            original.activityID.map { Booking(projectID: projectID, activityID: $0) }
        }
        if let booking, booking != originalBooking {
            changes.booking = booking
        }
        if beginEdited, begin != original.begin {
            changes.begin = begin
        }
        if !isRunning, endEdited, end != original.end {
            changes.end = end
        }
        if Set(tags.map(Catalog.fold)) != Set(original.tags.map(Catalog.fold)) {
            changes.tags = tags
        }
        if billable != initialBillable {
            changes.billable = billable
        }
        return changes
    }

    /// Values for a new record.
    func draft() -> TimesheetDraft {
        // "Billable" is only sent when the user changed it: accounts without the permission to
        // edit it get the whole request rejected if the field is present, and leaving it out
        // lets Kimai apply its own billable rules.
        TimesheetDraft(
            begin: begin, end: isRunning ? nil : end, projectID: booking?.projectID,
            activityID: booking?.activityID, description: description, tags: tags,
            billable: billable == initialBillable ? nil : billable)
    }
}
