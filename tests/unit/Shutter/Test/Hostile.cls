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

}
