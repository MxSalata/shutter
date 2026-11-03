/// A table of hostile and malformed agent outputs against the schema checks (Shutter.Schema.Findings and Plan; CONTRACTS 6.6,
/// v1.35): each row says whether the check must refuse it. The checks never throw, always answer an array of problems, and
/// accept ordinary Unicode. The schema classes belong to the aihub module, so on an instance without them the table is
/// reported as skipped ($$$AssertSkipped, which the runner counts apart from the passes); it runs on the AI Hub build.
Class Shutter.Test.Hostile Extends %UnitTest.TestCase
{

ClassMethod Rows() As %DynamicArray
{
    Set long = ""
    For i = 1:1:2101 { Set long = long _ "x" }
    Set good = "{""disposition"":""resend"",""confidence"":0.8,""summary"":""fine"",""evidence_refs"":[""message""]}"
    Quit [
        {"kind": "findings", "name": "a good finding", "json": (good), "cite": "message,validation", "refuse": false},
        {"kind": "findings", "name": "empty text", "json": "", "cite": "", "refuse": true},
        {"kind": "findings", "name": "prose, not JSON", "json": "I think we should resend.", "cite": "", "refuse": true},
        {"kind": "findings", "name": "prose around JSON", "json": ("Here it is: " _ good _ " Done."), "cite": "", "refuse": true},
        {"kind": "findings", "name": "truncated JSON", "json": "{\"disposition\":\"resend\",\"confidence\":0.8,\"summ", "cite": "", "refuse": true},
        {"kind": "findings", "name": "two objects", "json": (good _ good), "cite": "", "refuse": true},
        {"kind": "findings", "name": "NaN confidence", "json": "{\"disposition\":\"resend\",\"confidence\":NaN,\"summary\":\"x\",\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "findings", "name": "confidence as a word", "json": "{\"disposition\":\"resend\",\"confidence\":\"high\",\"summary\":\"x\",\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "findings", "name": "confidence over 1", "json": "{\"disposition\":\"resend\",\"confidence\":1.5,\"summary\":\"x\",\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "findings", "name": "evidence_refs a string", "json": "{\"disposition\":\"resend\",\"confidence\":0.5,\"summary\":\"x\",\"evidence_refs\":\"message\"}", "cite": "", "refuse": true},
        {"kind": "findings", "name": "a reference to evidence not given", "json": "{\"disposition\":\"resend\",\"confidence\":0.5,\"summary\":\"x\",\"evidence_refs\":[\"message\",\"other_case\"]}", "cite": "message,validation", "refuse": true},
        {"kind": "findings", "name": "the same reference with no list to check", "json": "{\"disposition\":\"resend\",\"confidence\":0.5,\"summary\":\"x\",\"evidence_refs\":[\"other_case\"]}", "cite": "", "refuse": false},
        {"kind": "findings", "name": "a summary over 2000 characters", "json": ("{""disposition"":""resend"",""confidence"":0.5,""summary"":""" _ long _ """,""evidence_refs"":[]}"), "cite": "", "refuse": true},
        {"kind": "findings", "name": "a disposition in capitals", "json": "{\"disposition\":\"RESEND\",\"confidence\":0.5,\"summary\":\"x\",\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "findings", "name": "a zero-width character inside the disposition", "json": "{\"disposition\":\"re\u200bsend\",\"confidence\":0.5,\"summary\":\"x\",\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "findings", "name": "a bidi control in the summary (accepted here, stripped at the store)", "json": "{\"disposition\":\"resend\",\"confidence\":0.5,\"summary\":\"now\u202E won\",\"evidence_refs\":[]}", "cite": "", "refuse": false},
        {"kind": "findings", "name": "ordinary Unicode in the summary", "json": "{\"disposition\":\"resend\",\"confidence\":0.5,\"summary\":\"Überweisung nach Станция, 3 µg\",\"evidence_refs\":[]}", "cite": "", "refuse": false},
        {"kind": "findings", "name": "a duplicate key (the last wins, the object is valid)", "json": "{\"disposition\":\"escalate\",\"disposition\":\"resend\",\"confidence\":0.5,\"summary\":\"x\",\"evidence_refs\":[]}", "cite": "", "refuse": false},
        {"kind": "findings", "name": "missing summary", "json": "{\"disposition\":\"resend\",\"confidence\":0.5,\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "plan", "name": "a good plan", "json": "{\"disposition\":\"resend\",\"summary\":\"x\",\"action\":{\"type\":\"resend\",\"operation_key\":\"K\",\"expected_version\":3},\"evidence_refs\":[\"message\"]}", "cite": "message", "refuse": false},
        {"kind": "plan", "name": "an action type that is not allowed", "json": "{\"disposition\":\"resend\",\"summary\":\"x\",\"action\":{\"type\":\"delete\",\"operation_key\":\"K\"},\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "plan", "name": "a resend with no expected version", "json": "{\"disposition\":\"resend\",\"summary\":\"x\",\"action\":{\"type\":\"resend\",\"operation_key\":\"K\"},\"evidence_refs\":[]}", "cite": "", "refuse": true},
        {"kind": "plan", "name": "an outcome with no catalogue entry", "json": "{\"disposition\":\"escalate\",\"summary\":\"x\",\"action\":{\"type\":\"none\"},\"evidence_refs\":[],\"outcome\":\"preferred\"}", "cite": "", "refuse": true},
        {"kind": "plan", "name": "a why over 2000 characters", "json": ("{""disposition"":""escalate"",""summary"":""x"",""why"":""" _ long _ """,""action"":{""type"":""none""},""evidence_refs"":[]}"), "cite": "", "refuse": true},
        {"kind": "plan", "name": "no action at all", "json": "{\"disposition\":\"escalate\",\"summary\":\"x\",\"evidence_refs\":[]}", "cite": "", "refuse": true}
    ]
}

Method TestTheTable()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Schema.Findings") {
        Do $$$AssertSkipped("The aihub module is not on this instance: the hostile-output table is skipped (it runs on the AI Hub build)")
        Quit
    }
    Set rows = ..Rows(), it = rows.%GetIterator(), n = 0
    While it.%GetNext(, .row) {
        Set n = n + 1
        Set cls = $SELECT(row.kind = "plan": "Shutter.Schema.Plan", 1: "Shutter.Schema.Findings")
        Set problems = ""
        Try {
            Set problems = $CLASSMETHOD(cls, "Check", row.json, row.cite)
        } Catch ex {
            Do $$$AssertTrue(0, row.name _ ": the check threw " _ ex.DisplayString())
            Continue
        }
        Do $$$AssertTrue($ISOBJECT(problems) && problems.%IsA("%Library.DynamicArray"), row.name _ ": an array of problems comes back")
        If row.refuse {
            Do $$$AssertTrue(problems.%Size() > 0, row.name _ ": refused: " _ problems.%ToJSON())
        } Else {
            Do $$$AssertEquals(problems.%Size(), 0, row.name _ ": accepted: " _ problems.%ToJSON())
        }
    }
    Do $$$AssertTrue(n >= 20, n _ " rows")
}

/// The names the prompts used before v1.39, error for the failure and later_event for the timeline, stay citable: the
/// runner lists them with what a finding or a plan may cite whenever the evidence has the key they stand for, so the
/// recordings and the evaluation table pass the check, and a name outside the evidence is refused as before. The runner
/// belongs to the aihub module, so on an instance without it this is reported as skipped, as the table is.
Method TestEarlierNamesStayCitable()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub") || '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Schema.Findings") {
        Do $$$AssertSkipped("The aihub module is not on this instance: the evidence-key check is skipped (it runs on the AI Hub build)")
        Quit
    }
    // A receipt with a committed body, so that error is not already a key one level down (as receipt.error is when there is none).
    Set context = {"case_id": "C-000003", "evidence": {"operation": {"operation_key": "K", "event": "transfer"}, "failure": {"kind": "error", "outcome": "nack", "reason_code": "AR", "http_status": 409}, "message": {"message_control_id": "MSG00001"}, "receipt": {"operation_key": "K", "applied_at": "2026-10-15T08:50:00Z", "version_after": 4}, "timeline": [{"event": "transfer", "later": true, "operation_key": "K2"}], "route": {"receiver": "ward_api"}}}
    Set ids = ##class(Shutter.Bridge.Runner.AIHub).EvidenceIdsOf(context.%ToJSON())
    Set known = "," _ ids _ ","
    Do $$$AssertTrue((known [ ",failure,") && (known [ ",timeline,") && (known [ ",reason_code,"), "the keys and the keys one level down: " _ ids)
    Do $$$AssertTrue((known [ ",error,") && (known [ ",later_event,"), "the earlier names of the failure and the timeline: " _ ids)
    Do $$$AssertEquals($LENGTH(known, ",error,"), 2, "error is listed once")
    Set good = "{""disposition"":""reconcile"",""confidence"":0.7,""summary"":""committed"",""evidence_refs"":[""error"",""later_event"",""receipt""]}"
    Set problems = ##class(Shutter.Schema.Findings).Check(good, ids)
    Do $$$AssertEquals(problems.%Size(), 0, "a finding citing error and later_event is accepted: " _ problems.%ToJSON())
    Set bad = "{""disposition"":""reconcile"",""confidence"":0.7,""summary"":""x"",""evidence_refs"":[""later_event"",""MSG00001""]}"
    Set problems = ##class(Shutter.Schema.Findings).Check(bad, ids)
    Do $$$AssertEquals(problems.%Size(), 1, "an identifier from the content is refused as before: " _ problems.%ToJSON())
    Set named = $SELECT(problems.%Size() = 1: $PIECE(problems.%Get(0), ";", 1), 1: "")
    Do $$$AssertTrue((named [ "MSG00001") && (named '[ "later_event"), "naming only the unknown one: " _ named)
    // Without the key they stand for, the names are not listed.
    Set context = {"evidence": {"message": {"message_control_id": "MSG00001"}}}
    Set ids = ##class(Shutter.Bridge.Runner.AIHub).EvidenceIdsOf(context.%ToJSON())
    Do $$$AssertEquals(ids, "message,message_control_id", "no failure and no timeline, no earlier name: " _ ids)
    Do $$$AssertEquals(##class(Shutter.Bridge.Runner.AIHub).EvidenceIdsOf(""), "", "no context, nothing to cite")
}

}
