/// The text of an escalation email (T29), built from what Shutter stored about the case, never by a model: the
/// patient's identifiers and date of birth, the event, what failed, why Shutter stopped, what the receiver holds,
/// the encounter's timeline (the feed and the index), and what Shutter did and did not send. It carries no name,
/// address or note text: the team checks the demographics in their own systems, or asks.
Class Shutter.Util.EscalationDraft
{

/// The team for the case: the one named; else, for a merge, the one whose sources include the case's source system
/// (the sending application, MSH-3: the PAS team decides a merge, T31); else the one whose receivers include the
/// case's receiver; else the first team in the site profile; else a team made of the approvers' escalation text (no
/// mailbox: the person fills it in).
ClassMethod Team(case As Shutter.Store.Case, teamId As %String = "") As %DynamicObject
{
    Set teams = ##class(Shutter.Store.SiteProfile).Current().%Get("teams")
    If $ISOBJECT(teams) && (teams.%Size() > 0) {
        Set first = "", bySource = "", byReceiver = "", it = teams.%GetIterator()
        Set source = $SELECT(case.SourceSystem '= "": case.SourceSystem, 1: $PIECE(case.OperationKey, "^", 1))
        While it.%GetNext(, .t) {
            Continue:'$ISOBJECT(t)
            If first = "" Set first = t
            If teamId '= "" { Return:(##class(Shutter.Util.Json).Str(t, "id") = teamId) t  Continue }
            If (case.Event = "merge") && '$ISOBJECT(bySource) && ..Lists(t.%Get("sources"), source) Set bySource = t
            If '$ISOBJECT(byReceiver) && ..Lists(t.%Get("receivers"), case.Receiver) Set byReceiver = t
        }
        If teamId '= "" Quit {}
        If $ISOBJECT(bySource) Quit bySource
        If $ISOBJECT(byReceiver) Quit byReceiver
        Quit first
    }
    Set approvers = ##class(Shutter.Store.SiteProfile).Current().%Get("approvers")
    Set text = $SELECT($ISOBJECT(approvers): ##class(Shutter.Util.Json).Str(approvers, "escalation"), 1: "")
    Quit {"id": "", "name": (text), "mailbox": ""}
}

/// The subject and body of the email for a case and a team.
ClassMethod Build(case As Shutter.Store.Case, team As %DynamicObject, Output subject As %String, Output body As %String) As %Status
{
    Set subject = "", body = ""
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case")
    Set json = "Shutter.Util.Json", nl = $CHAR(13, 10)
    Set summary = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.SummaryObject(), 1: "")
    If '$ISOBJECT(summary) Set summary = {}
    Set receiver = $SELECT(case.Receiver '= "": case.Receiver, 1: "the downstream system")
    Set label = ##class(Shutter.Store.SiteProfile).ReceiverLabel(receiver)
    Set ids = ..Identifiers(case)
    Set subject = "Shutter " _ case.CaseId _ ": manual check needed, " _ receiver _ $SELECT(case.EncounterId = "-": ", patient " _ case.PatientId _ " (no encounter)", 1: ", encounter " _ case.EncounterId)

    Set teamName = $SELECT($ISOBJECT(team): $CLASSMETHOD(json, "Str", team, "name"), 1: "")
    Set b = "To " _ $SELECT(teamName '= "": teamName, 1: "the team") _ "," _ nl _ nl
    If case.FailureKind = "withheld" {
        Set b = b _ "Shutter withheld a message to " _ label _ " that it never sends by itself (" _ case.FailureText _ "). Please apply or decline it by hand in the systems concerned; Shutter has sent nothing for this message." _ nl _ nl
    } Else {
        Set b = b _ "Shutter could not safely recover a failed message to " _ label _ ". Please compare the systems and correct them by hand; Shutter has sent nothing more for this message." _ nl _ nl
    }

    Set b = b _ "PATIENT" _ nl
    Set b = b _ "  Hospital number: " _ ids.hospital _ nl
    If ids.nhs '= "" Set b = b _ "  NHS number: " _ ids.nhs _ nl
    If ids.dob '= "" Set b = b _ "  Date of birth: " _ ids.dob _ nl
    Set b = b _ "  Encounter (visit number): " _ $SELECT(case.EncounterId = "-": "none (a patient-level message)", 1: case.EncounterId) _ nl _ nl

    Set b = b _ "THE EVENT" _ nl
    Set b = b _ "  " _ ..EventLine(case.Event, case.Ward, case.EventTime, case) _ nl
    Set b = b _ "  Source system: " _ case.SourceSystem _ ", message control id " _ case.SourceMessageId _ nl
    Set b = b _ "  Operation key: " _ case.OperationKey _ nl _ nl

    Set b = b _ "WHAT FAILED" _ nl
    Set b = b _ "  " _ $SELECT(case.FailureText '= "": case.FailureText, 1: case.FailureKind) _ nl _ nl

    Set b = b _ "WHY SHUTTER STOPPED" _ nl
    Set reason = ..Reason(case, .failing)
    If $ISOBJECT(reason) {
        Set b = b _ "  " _ reason.Title _ " (" _ reason.Code _ ")" _ nl
        If reason.Text '= "" Set b = b _ "  " _ reason.Text _ nl
        If reason.NextAction '= "" Set b = b _ "  Next action: " _ reason.NextAction _ nl
    } Else {
        Set b = b _ "  The case is " _ case.State _ ": " _ case.Headline _ nl
    }
    Set it = failing.%GetIterator()
    While it.%GetNext(, .c) {
        Set b = b _ "  Check " _ $CLASSMETHOD(json, "Str", c, "check") _ ": " _ $CLASSMETHOD(json, "Str", c, "result") _ ", " _ $CLASSMETHOD(json, "Str", c, "reason_code") _ $SELECT($CLASSMETHOD(json, "Str", c, "detail") '= "": ". " _ $CLASSMETHOD(json, "Str", c, "detail"), 1: "") _ nl
    }
    Set b = b _ nl

    Set b = b _ "WHAT " _ $ZCONVERT(receiver, "U") _ " HOLDS" _ nl
    Set state = summary.%Get("ward_state")
    If $ISOBJECT(state) && (state.%Get("state") '= "") {
        Set b = b _ "  " _ $ZCONVERT($CLASSMETHOD(json, "Str", state, "state"), "W") _ $SELECT($CLASSMETHOD(json, "Str", state, "ward") '= "": " in " _ $CLASSMETHOD(json, "Str", state, "ward"), 1: "") _ ", version " _ $CLASSMETHOD(json, "Str", state, "version") _ nl
        Set history = state.%Get("history")
        If $ISOBJECT(history) {
            Set hi = history.%GetIterator()
            While hi.%GetNext(, .h) {
                Set b = b _ "  - " _ ..EventLine($CLASSMETHOD(json, "Str", h, "event"), $CLASSMETHOD(json, "Str", h, "ward"), $CLASSMETHOD(json, "Str", h, "event_time")) _ $SELECT($CLASSMETHOD(json, "Str", h, "version") '= "": " (version " _ $CLASSMETHOD(json, "Str", h, "version") _ ")", 1: "") _ nl
            }
        }
    } Else {
        If case.EncounterId = "-" {
            Set b = b _ "  Not applicable: the message names no encounter (a patient-level message)." _ nl
        } Else {
            Set b = b _ "  Not known: the receiver's record of the encounter could not be read (HTTP " _ summary.%Get("ward_state_http_status") _ ")." _ nl
        }
    }
    Set b = b _ nl

    Set b = b _ "THE ENCOUNTER'S MESSAGES (the feed, and the index for routes Shutter does not deliver)" _ nl
    Set timeline = ##class(Shutter.Index.Timeline).ForCase(case)
    If '$ISOBJECT(timeline) || (timeline.%Size() = 0) Set timeline = summary.%Get("timeline")
    If $ISOBJECT(timeline) && (timeline.%Size() > 0) {
        Set ti = timeline.%GetIterator()
        While ti.%GetNext(, .ev) {
            Set src = $CLASSMETHOD(json, "Str", ev, "source")
            Set b = b _ "  - " _ ..EventLine($CLASSMETHOD(json, "Str", ev, "event"), $CLASSMETHOD(json, "Str", ev, "ward"), $CLASSMETHOD(json, "Str", ev, "event_time"))
            Set b = b _ ": " _ $CLASSMETHOD(json, "Str", ev, "outcome", "outcome unknown")
            Set b = b _ $SELECT(src = "index": " (found by the index on route " _ $CLASSMETHOD(json, "Str", ev, "route") _ ")", 1: "")
            Set b = b _ $SELECT($CLASSMETHOD(json, "Str", ev, "operation_key") = case.OperationKey: " <- this case", 1: "") _ nl
        }
    } Else {
        Set b = b _ "  None found." _ nl
    }
    Set b = b _ nl

    Set b = b _ "WHAT SHUTTER SENT" _ nl
    Set b = b _ "  " _ ..Attempts(case) _ nl _ nl

    Set b = b _ "WHEN IT IS CORRECTED" _ nl
    If (case.FailureKind = "withheld") || (case.EncounterId = "-") {
        Set b = b _ "  Reply to this email with what was changed, or record it on the case, then mark the case as handled by the team on the case page: Shutter sent nothing for this message and will send nothing, and it cannot verify a merge or a cancellation against " _ receiver _ "." _ nl _ nl
    } Else {
        Set b = b _ "  Reply to this email with what was changed, or record it on the case, then choose Reinvestigate on the case page: Shutter reads " _ receiver _ " again and verifies the correction." _ nl _ nl
    }

    Set b = b _ "REFERENCES" _ nl
    Set b = b _ "  Case: " _ case.CaseId _ " (Shutter, /shutter/index.html#/cases/" _ case.CaseId _ ")" _ nl
    If case.WorkflowSessionId '= "" Set b = b _ "  Visual Trace session: " _ case.WorkflowSessionId _ nl
    If case.SourceHeaderId '= "" Set b = b _ "  Original message header: " _ case.SourceHeaderId _ nl
    Set b = b _ nl _ "This email was drafted by Shutter from its record of the case and reviewed by the person who sent it." _ nl
    Set body = b
    Quit $$$OK
}

/// The hospital number (PID-3 typed MR, as the case carries it), the NHS number (PID-3 typed NH) and the date of
/// birth (PID-7), read from the original message inside IRIS.
ClassMethod Identifiers(case As Shutter.Store.Case) As %DynamicObject
{
    Set o = {"hospital": "", "nhs": "", "dob": ""}
    Set o.hospital = case.PatientId _ $SELECT(case.PatientIdAuthority '= "": " (" _ case.PatientIdAuthority _ ")", 1: "")
    Try {
        Set header = ##class(Ens.MessageHeader).%OpenId(case.SourceHeaderId)
        Quit:'$ISOBJECT(header)
        Set msg = ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId)
        Quit:'$ISOBJECT(msg)
        Set n = +##class(Shutter.Util.OperationKey).Value(msg, "PID", "3(*)")
        For i = 1:1:n {
            If $ZCONVERT(##class(Shutter.Util.OperationKey).Value(msg, "PID", "3(" _ i _ ").5"), "U") = "NH" Set o.nhs = ##class(Shutter.Util.OperationKey).Value(msg, "PID", "3(" _ i _ ").1") Quit
        }
        Set dob = $EXTRACT(##class(Shutter.Util.OperationKey).Value(msg, "PID", "7.1"), 1, 8)
        If dob ?8N Set o.dob = $EXTRACT(dob, 1, 4) _ "-" _ $EXTRACT(dob, 5, 6) _ "-" _ $EXTRACT(dob, 7, 8)
    } Catch {
    }
    Quit o
}

/// "Transfer to WARD-B at 2026-10-15 09:20 UTC". A cancel reads "Cancellation of the transfer at ..." (T31; a cancel carries no ward),
/// and a merge "Merge of <prior identifier> into <patient identifier>" when the case is given and carries the prior
/// patient identifier (Store.Case's PriorPatientId), else "Merge". The other indexed-only events read as plain words.
ClassMethod EventLine(event As %String, location As %String, time As %String, case As Shutter.Store.Case = "") As %String
{
    Set when = $SELECT(time = "": "", 1: " at " _ $TRANSLATE($EXTRACT(time, 1, 16), "T", " ") _ " UTC")
    If event = "merge" {
        Set prior = "", into = ""
        If $ISOBJECT(case) {
            Set prior = case.PriorPatientId _ $SELECT((case.PriorPatientId '= "") && (case.PriorPatientIdAuthority '= ""): " (" _ case.PriorPatientIdAuthority _ ")", 1: "")
            Set into = case.PatientId _ $SELECT((case.PatientId '= "") && (case.PatientIdAuthority '= ""): " (" _ case.PatientIdAuthority _ ")", 1: "")
        }
        If (prior '= "") && (into '= "") Quit "Merge of " _ prior _ " into " _ into _ when
        Quit "Merge" _ when
    }
    Set cancel = ($EXTRACT(event, 1, 7) = "cancel_")
    Set base = $SELECT(cancel: $EXTRACT(event, 8, *), 1: event)
    Set word = $CASE(base, "admit": "Admission", "transfer": "Transfer", "discharge": "Discharge", "update": "Update", "register": "Registration", "preadmit": "Pre-admission", "person_add": "Person added", "person_update": "Person updated", "": "An event", : $ZCONVERT(base, "W"))
    Set where = $SELECT(location = "": "", base = "admit": " to " _ location, base = "transfer": " to " _ location, base = "discharge": " from " _ location, 1: " at " _ location)
    If cancel Quit "Cancellation of the " _ $ZCONVERT(word, "L") _ where _ when
    Quit word _ where _ when
}

/// Whether a team's list (receivers, sources) names a value.
ClassMethod Lists(list As %DynamicArray, value As %String) As %Boolean [ Private ]
{
    If '$ISOBJECT(list) || (value = "") Quit 0
    Set it = list.%GetIterator()
    While it.%GetNext(, .v) { If ("" _ v) = value Return 1 }
    Quit 0
}

/// The block reason the case page shows, and the gate's failing checks (as GET /cases/:id/blocked-reason).
ClassMethod Reason(case As Shutter.Store.Case, Output failing As %DynamicArray) As Shutter.Store.BlockReason
{
    Set failing = [], code = "", id = case.%Id(), did = ""
    &sql(SELECT TOP 1 ID INTO :did FROM Shutter_Store.GateDecision WHERE "Case" = :id AND Outcome <> 'pass' ORDER BY ID DESC)
    If (SQLCODE = 0) && (did '= "") {
        Set d = ##class(Shutter.Store.GateDecision).%OpenId(did)
        Set checks = ##class(Shutter.Util.Json).Parse(d.ChecksJSON, .psc)
        If $ISOBJECT(checks) {
            Set it = checks.%GetIterator()
            While it.%GetNext(, .c) { If c.result '= "pass" { Do failing.%Push(c) If code = "" Set code = c."reason_code" } }
        }
    }
    If code = "" Set code = $SELECT(case.State = "escalated": "ESCALATED", case.State = "failed": "", 1: "BLOCKED")
    Quit $SELECT(code = "": "", 1: ##class(Shutter.Store.BlockReason).ByCode(code))
}

/// What Shutter sent for the case: nothing, or each write with its outcome.
ClassMethod Attempts(case As Shutter.Store.Case) As %String
{
    Set out = "", n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT At, Outcome, ExpectedVersion, HttpStatus FROM Shutter_Store.ExecutionAttempt WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set n = n + 1
        Set out = out _ $SELECT(out = "": "", 1: "; ") _ "a write at " _ $TRANSLATE($EXTRACT(rs.%Get("At"), 1, 16), "T", " ") _ " UTC expecting version " _ rs.%Get("ExpectedVersion") _ ": " _ rs.%Get("Outcome") _ " (HTTP " _ rs.%Get("HttpStatus") _ ")"
    }
    Quit $SELECT(n = 0: "Nothing: Shutter sent no write for this case.", 1: out _ ".")
}

}
