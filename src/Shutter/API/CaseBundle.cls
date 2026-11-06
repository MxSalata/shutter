/// One case's bundle for audit and support handoff (CONTRACTS 5): its evidence, plans, gate decisions, approvals,
/// attempts, verifications and closure receipt, as one JSON file whose first line says it is redacted. The redaction is
/// the model view's (Shutter.Util.ModelView): the same tokens, the same allowlists, the same denied keys, read from the
/// stored rows. A bundle goes further in three places, since a file leaves with no one to ask: note text stays in IRIS
/// whatever the site's model switch says, what a person typed (an approver's comment, a hand closure's reason) stays in
/// IRIS since no map covers it, and a last sweep of the finished object refuses the file if a value of the map is left.
/// It fails closed as the view does: a case that cannot be redacted gets no file and no record.
Class Shutter.API.CaseBundle Extends %RegisteredObject
{

/// The file's first line. Ward, bed, times and user names stay, as they do for a model, and the line says so.
Parameter REDACTION = "REDACTED: patient identifiers, name parts and the date of birth are replaced by this case's tokens, and demographics, note text and what people typed are left out. The map back stays in IRIS. Ward, bed, times, message control ids and staff user names remain, so handle this file as sensitive.";

/// Build the file and record who took it. "" with why set when there is no file: nothing is then recorded. A file with
/// no record is no file, since the record is the audit of what left.
ClassMethod Download(case As Shutter.Store.Case, user As %String, Output why As %String) As %String
{
    Set why = "", text = ""
    Try {
        Set text = ..Text(case, user, .why)
    } Catch ex {
        Set text = "", why = "The bundle of case " _ case.CaseId _ " could not be built, so nothing was redacted or sent (" _ ex.Name _ ")"
    }
    If text = "" Quit ""
    Set sc = case.Note("note", "Case bundle downloaded by " _ user _ ", identifiers redacted; SHA-256 " _ ##class(Shutter.Util.Digest).SHA256Hex(text), user)
    If $$$ISERR(sc) {
        Set why = "The download of case " _ case.CaseId _ " could not be recorded on the case, so no file was made; try again"
        Quit ""
    }
    Quit text
}

/// The file's text, redacted and swept, or "" with why set. Learns the case's identifiers from every part first, as the
/// business process does from its evidence: the map only grows, and a token once given stays.
ClassMethod Text(case As Shutter.Store.Case, user As %String, Output why As %String) As %String
{
    Set why = "", refused = "The bundle of case " _ case.CaseId _ " cannot be redacted, so no file was made: "
    Set parts = ..Parts(case)
    Set sc = ##class(Shutter.Util.ModelView).Learn(case, parts)
    If $$$ISERR(sc) { Set why = refused _ "its message cannot be read for the names to replace" Quit "" }
    If ##class(Shutter.Util.ModelView).Reduce(case, {}).%IsDefined("error") { Set why = refused _ "its identifiers have no tokens" Quit "" }
    Set mv = "Shutter.Util.ModelView"
    Set out = {}
    Set out.format = "shutter-case-bundle/1"
    Set out.generatedAt = ##class(Shutter.Util.Time).NowUTC()
    Set out.generatedBy = $CLASSMETHOD(mv, "Tokenise", case, user)
    Set out.case = ..Header(case)
    For part = "evidence", "plans", "gateDecisions", "approvals", "attempts", "verifications" {
        Do out.%Set(part, $CLASSMETHOD(mv, "Reduce", case, parts.%Get(part)))
    }
    If parts.%GetTypeOf("receipt") = "object" { Set out.receipt = ..Receipt(case, parts.receipt) } Else { Do out.%Set("receipt", "", "null") }
    Set out.notIncluded = ["the map from tokens to values", "note text", "comments and reasons people typed", "the case's event log", "the agents' runs", "escalation emails"]
    Do ..DropNoteText(out)
    Set left = ..Sweep(case, out)
    If left '= "" { Set why = refused _ "a " _ left _ " value was left in it" Quit "" }
    // One JSON document, with the statement alone on the first line, ahead of everything else in the file.
    Quit "{""redaction"":""" _ ..#REDACTION _ """," _ $CHAR(10) _ $EXTRACT(out.%ToJSON(), 2, *)
}

/// The stored rows as the app's routes read them, with JSON held as text parsed: left as a string, it would only be
/// tokenised, where parsed it is reduced by its shape.
ClassMethod Parts(case As Shutter.Store.Case) As %DynamicObject [ Private ]
{
    Set id = case.%Id(), json = "Shutter.Util.Json", parts = {}
    // Every snapshot, oldest first: each plan and approval names the digest of the one it rests on.
    Set evidence = $CLASSMETHOD(json, "Rows", "Shutter.Store.Snapshot", "SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ? ORDER BY Seq", id)
    Set iter = evidence.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set s = ##class(Shutter.Store.Snapshot).%OpenId(row.id)
        Set row.summary = s.SummaryObject(), row.items = s.Items()
    }
    Set parts.evidence = evidence
    Set plans = $CLASSMETHOD(json, "Rows", "Shutter.Store.Plan", "SELECT ID FROM Shutter_Store.Plan WHERE ""Case"" = ? ORDER BY ID", id)
    Do ..ParseFields(plans, "plan", "preconditions", "evidenceRefs", "disagreements")
    Set parts.plans = plans
    Set gates = $CLASSMETHOD(json, "Rows", "Shutter.Store.GateDecision", "SELECT ID FROM Shutter_Store.GateDecision WHERE ""Case"" = ? ORDER BY ID", id)
    Do ..ParseFields(gates, "checks")
    Set parts.gateDecisions = gates
    Set approvals = $CLASSMETHOD(json, "Rows", "Shutter.Store.Approval", "SELECT ID FROM Shutter_Store.Approval WHERE ""Case"" = ? ORDER BY ID", id)
    Set iter = approvals.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Do row.%Set("commentPresent", row.comment '= "", "boolean")
        Do row.%Remove("comment")
    }
    Set parts.approvals = approvals
    Set attempts = $CLASSMETHOD(json, "Rows", "Shutter.Store.ExecutionAttempt", "SELECT ID FROM Shutter_Store.ExecutionAttempt WHERE ""Case"" = ? ORDER BY ID", id)
    Do ..ParseFields(attempts, "receipt", "response")
    Set parts.attempts = attempts
    Set verifications = $CLASSMETHOD(json, "Rows", "Shutter.Store.Verification", "SELECT ID FROM Shutter_Store.Verification WHERE ""Case"" = ? ORDER BY ID", id)
    Do ..ParseFields(verifications, "detail")
    Set parts.verifications = verifications
    If case.IsClosed() { Set parts.receipt = ##class(Shutter.API.Dispatch).ClosureObject(case) } Else { Do parts.%Set("receipt", "", "null") }
    // The fields that name identifiers under keys the map's learning does not read.
    Set parts.named = {"operation_key": (case.OperationKey), "patient_id": (case.PatientId), "encounter_id": (case.EncounterId), "prior_patient_id": (case.PriorPatientId), "prior_encounter_id": (case.PriorEncounterId)}
    Quit parts
}

/// Each row's named fields, from JSON text to JSON. Text that does not parse goes as null, never as text.
ClassMethod ParseFields(rows As %DynamicArray, fields...) [ Private ]
{
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        For f = 1:1:$GET(fields) {
            Set key = fields(f)
            Continue:row.%GetTypeOf(key)'="string"
            Set parsed = ##class(Shutter.Util.Json).Parse(row.%Get(key), .psc)
            If $ISOBJECT(parsed) && (row.%Get(key) '= "") { Do row.%Set(key, parsed) } Else { Do row.%Set(key, "", "null") }
        }
    }
}

/// Which case this is, by its operational fields. Built here, since the view's allowlist for a node with a state is a
/// receiver's body.
ClassMethod Header(case As Shutter.Store.Case) As %DynamicObject [ Private ]
{
    Set mv = "Shutter.Util.ModelView", o = {}
    Set o.caseId = case.CaseId, o.state = case.State, o.disposition = case.Disposition, o.mode = case.Mode
    Set o.event = case.Event, o.receiver = case.Receiver, o.failureKind = case.FailureKind, o.failureReasonCode = case.FailureReasonCode
    Set o.openedAt = case.OpenedAt, o.closedAt = case.ClosedAt, o.version = case.Version
    Set o.operationKey = $CLASSMETHOD(mv, "Tokenise", case, case.OperationKey)
    Quit o
}

/// The closure receipt, whole (GET /cases/{id}/closure). The state goes round the view, for the reason Header gives; a
/// hand closure's or an abandon's outcome keeps who and how, and not the reason they typed.
ClassMethod Receipt(case As Shutter.Store.Case, receipt As %DynamicObject) As %DynamicObject [ Private ]
{
    Set state = receipt.state
    Do receipt.%Remove("state")
    If $LISTFIND($LISTBUILD("handled_by_hand", "abandoned"), case.Disposition) Set receipt.outcome = $PIECE(case.Outcome, ":", 1) _ "; the reason stays in IRIS"
    Set out = ##class(Shutter.Util.ModelView).Reduce(case, receipt)
    Set out.state = state
    Quit out
}

/// Note text out of a reduced object: the site's switch lets its model read notes, which says nothing of a file.
ClassMethod DropNoteText(node As %DynamicAbstractObject)
{
    Set iter = node.%GetIterator()
    While iter.%GetNext(.key, .v) {
        Continue:'$ISOBJECT(v)
        If (key = "notes") && v.%IsA("%DynamicArray") {
            Set notes = v.%GetIterator()
            While notes.%GetNext(.n, .note) {
                If $ISOBJECT(note) && note.%IsDefined("text") { Do note.%Remove("text") Set note.note = "The text stays in IRIS" }
            }
        } Else {
            Do ..DropNoteText(v)
        }
    }
}

/// The last check before a file leaves: the kind of the first value of the case's map left in the object (a string, a
/// number, a key, which the view does not rewrite), never the value itself; "" when none is left. Strings are read as
/// the view replaces them; a key only as written, so a surname Ward does not catch the key ward.
ClassMethod Sweep(case As Shutter.Store.Case, node As %DynamicAbstractObject) As %String
{
    Set list = ##class(Shutter.Store.CaseToken).Map(case)
    Kill map
    For i = 1:1:$LISTLENGTH(list) { Set map(i) = $LIST(list, i) }
    Set map = $LISTLENGTH(list)
    Quit ..SweepNode(node, .map)
}

ClassMethod SweepNode(node As %DynamicAbstractObject, ByRef map) As %String [ Private ]
{
    Set mv = "Shutter.Util.ModelView", isArray = node.%IsA("%DynamicArray"), iter = node.%GetIterator(), found = ""
    While (found = "") && iter.%GetNext(.key, .v) {
        Set type = node.%GetTypeOf(key)
        For i = 1:1:map {
            Set value = $LIST(map(i), 2), token = $LIST(map(i), 1)
            If 'isArray && ($CLASSMETHOD(mv, "ReplaceBounded", key, value, token, 0) '= key) { Set found = $LIST(map(i), 3) Quit }
            If (type = "string") && ($CLASSMETHOD(mv, "ReplaceBounded", v, value, token, $LENGTH(value) > 2) '= v) { Set found = $LIST(map(i), 3) Quit }
            If (type = "number") && (v = value) { Set found = $LIST(map(i), 3) Quit }
        }
        If (found = "") && $ISOBJECT(v) Set found = ..SweepNode(v, .map)
    }
    Quit found
}

}
