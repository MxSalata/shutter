/// What the production review's agent is sent (docs/CONTRACTS.md, 13.6, and the model's view): the goal and the context
/// of the request Shutter.Process.Review.BuildAgentRequest builds, which the runner puts in front of the model as they are.
/// An application that logs an error naming a patient puts that name in the event log's text, and the text before its first
/// colon is the error group's signature: here a made-up patient, ZEBEDEE TESTPATIENT, MRN T9990001, NHS number 9990001234,
/// born 19700101, is logged by one item and by one routing rule, and none of it may reach the request, while the operator's
/// own review keeps every word. Every name and number here is made up; nothing is stored.
Class Shutter.Test.ReviewPayload Extends %UnitTest.TestCase
{

/// The made-up patient's pieces, each of which must stay out of the request.
Parameter NEEDLES = "ZEBEDEE,TESTPATIENT,T9990001,9990001234,19700101";

/// The error an application logged, as the event log holds it.
Parameter EXAMPLE = "Patient ZEBEDEE, TESTPATIENT (MRN T9990001, NHS 9990001234) not found at the receiver: PID|1||T9990001^^^HOSP^MR||ZEBEDEE^TESTPATIENT||19700101|F";

/// The hazardous production of Shutter.Test.Review, with the made-up patient's errors added to its event log and rule log.
ClassMethod Data(withPatient As %Boolean = 1) As %DynamicObject
{
    Set data = ##class(Shutter.Test.Review).Hazard()
    Quit:'withPatient data
    Set example = ..#EXAMPLE
    Do data.logErrors.%Push({"configName": "Lab Out", "sourceClass": "UT.Operation", "sourceMethod": "OnMessage", "signature": (##class(Shutter.Review.Sweep).Signature(example)), "count": 4, "latestId": "720", "latestAt": "2026-10-25T09:40:00Z", "latestMessageId": "960", "exampleText": (example)})
    Do data.ruleErrors.%Push({"ruleName": "UT.Router", "ruleSet": "UT.Router", "count": 2, "latestId": "33", "errorMsg": "Rule failed for ZEBEDEE^TESTPATIENT, MRN T9990001"})
    Quit data
}

/// The review's result as Shutter.Review.Sweep.Run gives it, over the data.
ClassMethod Result(data As %DynamicObject) As %DynamicObject
{
    Set cases = {"Lab Out": {"count": 4, "unique": 3, "latest": ["C-000004", "C-000003"]}, "_total": {"count": 9, "unique": 7, "latest": ["C-000009"]}}
    Set window = ##class(Shutter.Test.Review).Window()
    Set findings = ##class(Shutter.Review.Sweep).Evaluate(data, cases, window)
    Set result = {"namespace": "UT", "production": "UT.Production", "productionState": "running", "window": (window), "caseAggregates": (cases)}
    Set result.fingerprint = ##class(Shutter.Review.Sweep).Fingerprint(findings)
    Do ##class(Shutter.Review.Sweep).BaselineRank(findings)
    Set result.summary = {"bySeverity": {}, "findings": (findings.%Size())}
    Set result.findings = findings
    Quit result
}

ClassMethod Request(result As %DynamicObject) As Shutter.Bridge.Msg.AgentRequest
{
    Set r = ##class(Shutter.Store.Review).%New()
    Set r.ReviewId = "PR-UT-PAYLOAD", r.Namespace = "UT", r.Production = "UT.Production"
    Quit ##class(Shutter.Process.Review).BuildAgentRequest(r, result, 4, 60000, "operator")
}

/// The request names none of the made-up patient's pieces, in its goal, its context or its keys, while the review the
/// operator reads keeps the signature and the example; the error group is still there for the agent, under its digest.
Method TestNoPatientInThePayload()
{
    Set result = ..Result(..Data())
    Set stored = ##class(Shutter.Test.Review).Find(result.findings, "ERRORS_GROUPED", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(stored), "the made-up patient's errors make an error group on Lab Out")
    Quit:'$ISOBJECT(stored)
    Do $$$AssertTrue(stored.found [ "ZEBEDEE", "the operator's finding keeps the signature: " _ stored.found)
    Do $$$AssertTrue(stored.evidence.example [ "T9990001", "and the example")
    Do $$$AssertTrue(stored.why [ "ZEBEDEE", "and the words that quote it")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Test.Review).Find(result.findings, "RULE_ERRORS", "UT.Router")), "the rule's error makes a finding too")
    Set req = ..Request(result)
    Do $$$AssertTrue($ISOBJECT(req), "the request is built")
    Quit:'$ISOBJECT(req)
    Set payload = req.Goal _ $CHAR(10) _ req.Context _ $CHAR(10) _ req.RecordKey _ $CHAR(10) _ req.SnapshotDigest _ $CHAR(10) _ req.CorrelationKey
    Set ptr = 0
    While $LISTNEXT($LISTFROMSTRING(..#NEEDLES), ptr, needle) {
        Do $$$AssertNotTrue(payload [ needle, needle _ " is not in what the model is sent")
    }
    // The stored review is the operator's: building the request copies it and leaves it whole.
    Do $$$AssertTrue(stored.found [ "ZEBEDEE", "the review keeps the signature after the request is built")
    Do $$$AssertTrue(stored.evidence.example [ "T9990001", "and the example")
    Set context = {}.%FromJSON(req.Context)
    Set sent = ##class(Shutter.Test.Review).Find(context.findings, "ERRORS_GROUPED", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(sent), "the error group still reaches the agent, by code and item")
    Quit:'$ISOBJECT(sent)
    Set shown = ##class(Shutter.Process.Review).ModelSignature(stored.found)
    Do $$$AssertEquals(sent.found, shown, "under its digest")
    Do $$$AssertTrue(shown ? 1"[withheld text "12(1N,1"a",1"b",1"c",1"d",1"e",1"f")1"]", "a digest of 12 hex digits: " _ shown)
    Do $$$AssertTrue(sent.why [ shown, "and the words name the digest: " _ sent.why)
    Do $$$AssertEquals(sent.evidence.count, 4, "with its count")
    Do $$$AssertEquals(sent.evidence.%IsDefined("example"), 0, "and no example")
    // An IRIS error code is the system's and carries nothing of a message: it reaches the agent as it is.
    Set code = ##class(Shutter.Test.Review).Find(context.findings, "ERRORS_GROUPED", "ADT to Ward")
    Do $$$AssertTrue($ISOBJECT(code) && (code.found = "ERROR <Ens>ErrBPTerminated"), "an IRIS error code is sent as it is")
}

/// The error group is a count from the logs: it is not in the configuration fingerprint, so the request's record key and
/// SnapshotDigest, which the recordings are found under, are the same with the patient's errors as without them.
Method TestKeysDoNotMove()
{
    Set with = ..Request(..Result(..Data(1)))
    Set without = ..Request(..Result(..Data(0)))
    Do $$$AssertTrue($ISOBJECT(with) && $ISOBJECT(without), "both requests are built")
    Quit:'$ISOBJECT(with)
    Do $$$AssertTrue(with.SnapshotDigest '= "", "the hazardous production has a fingerprint")
    Do $$$AssertEquals(with.SnapshotDigest, without.SnapshotDigest, "SnapshotDigest does not move with an error group")
    Do $$$AssertEquals(with.RecordKey, without.RecordKey, "nor does the record key")
}

/// The payload of a request, every part of it that leaves IRIS, as one text.
ClassMethod Payload(req As Shutter.Bridge.Msg.AgentRequest) As %String
{
    Quit req.Goal _ $CHAR(10) _ req.Context _ $CHAR(10) _ req.RecordKey _ $CHAR(10) _ req.SnapshotDigest _ $CHAR(10) _ req.CorrelationKey
}

/// An application's signature can hold the very marks the check's words use, "(s)" and "{count}": the words quote the
/// signature exactly as it is, so the request withholds it there too, and nothing of the made-up patient reaches the model.
Method TestSignatureWithPlaceholderMarks()
{
    Set data = ..Data(0)
    Do data.logErrors.%Push({"configName": "Lab Out", "sourceClass": "UT.Operation", "sourceMethod": "OnMessage", "signature": "Result(s) for ZEBEDEE TESTPATIENT rejected", "count": 4, "latestId": "721", "latestAt": "2026-10-25T09:41:00Z", "latestMessageId": "961", "exampleText": "Result(s) for ZEBEDEE TESTPATIENT rejected: T9990001"})
    Do data.logErrors.%Push({"configName": "Ward Out", "sourceClass": "UT.Operation", "sourceMethod": "OnMessage", "signature": "ZEBEDEE {count} TESTPATIENT", "count": 4, "latestId": "722", "latestAt": "2026-10-25T09:42:00Z", "latestMessageId": "962", "exampleText": "ZEBEDEE {count} TESTPATIENT: 19700101"})
    Set result = ..Result(data)
    Set stored = ##class(Shutter.Test.Review).Find(result.findings, "ERRORS_GROUPED", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(stored), "the error group on Lab Out is found")
    Quit:'$ISOBJECT(stored)
    Do $$$AssertTrue(stored.why [ "4 errors with the signature Result(s) for ZEBEDEE TESTPATIENT rejected in the window", "the operator's words quote the signature as it is, and the plural still follows the count: " _ stored.why)
    Set other = ##class(Shutter.Test.Review).Find(result.findings, "ERRORS_GROUPED", "Ward Out")
    Do $$$AssertTrue($ISOBJECT(other) && (other.why [ "the signature ZEBEDEE {count} TESTPATIENT in the window"), "a {count} in a signature is not filled in")
    Set req = ..Request(result)
    Do $$$AssertTrue($ISOBJECT(req), "the request is built")
    Quit:'$ISOBJECT(req)
    Set payload = ..Payload(req)
    Set ptr = 0
    While $LISTNEXT($LISTFROMSTRING(..#NEEDLES), ptr, needle) {
        Do $$$AssertNotTrue(payload [ needle, needle _ " is not in what the model is sent")
    }
    Set context = {}.%FromJSON(req.Context)
    Set sent = ##class(Shutter.Test.Review).Find(context.findings, "ERRORS_GROUPED", "Lab Out")
    Do $$$AssertTrue($ISOBJECT(sent) && (sent.why [ ##class(Shutter.Process.Review).ModelSignature(stored.found)), "the words name the digest")
}

/// The fill of a check's words reads the rule's text once: a value put in is never filled again.
Method TestFillReadsTheRuleOnce()
{
    Set c = "Shutter.Review.Checks"
    Do $$$AssertEquals($CLASSMETHOD(c, "Fill", "{count} error(s) with {found} on {item}", {"item": "", "found": "A(s) {count} {item}", "count": 4}), "4 errors with A(s) {count} {item} on the production itself", "found stands as it is")
    Do $$$AssertEquals($CLASSMETHOD(c, "Fill", "{count} error(s)", {"count": 1}), "1 error", "one takes no plural")
    Do $$$AssertEquals($CLASSMETHOD(c, "Fill", "{count} error(s) {other} {found", {"count": 2, "found": "x"}), "2 errors {other} {found", "an unknown or unclosed mark is left as it is")
    Do $$$AssertEquals($CLASSMETHOD(c, "Fill", "error(s) on {item}", {"item": "Lab(s) Out"}), "error(s) on Lab(s) Out", "with no count the plural mark stays, and an item is not read again")
    Do $$$AssertEquals($CLASSMETHOD(c, "Fill", "", {"count": 2}), "", "nothing gives nothing")
}

/// The case aggregates' keys come from the cases' own fields, which POST /intake and a connector fill: an item, a reason
/// code and an outcome can each hold a patient's name. The model reads the production's items and a code's shape as they
/// are, any other key as a digest, with every count as it was; the keys do not move with the aggregates.
Method TestAggregateKeys()
{
    Set data = ..Data(0)
    Set result = ..Result(data)
    Set clean = ..Request(result)
    Set names = []
    Set iter = data.items.%GetIterator()
    While iter.%GetNext(.i, .item) { Do names.%Push(item.name) }
    Set result.itemNames = names
    Set leak = "patient ZEBEDEE TESTPATIENT MRN T9990001 unknown"
    Set lab = {"count": 4, "unique": 3, "byFailureKind": {"delivery_failed": 3, "rejected": 1}, "byOutcome": {"AR": 1, "T9990001": 2, "(none)": 1}, "byReasonCode": {"ward_unavailable": 1, "HTTP_503": 1}, "byState": {"escalated": 4}, "latest": ["C-000004", "C-000003"]}
    Do lab.byReasonCode.%Set(leak, 2)
    Set ward = {"count": 2, "unique": 2, "byFailureKind": {}, "byOutcome": {}, "byReasonCode": {"9990001234": 1, "19700101": 1}, "byState": {}, "latest": ["C-000007"]}
    Set feed = {"count": 1, "unique": 1, "byFailureKind": {}, "byOutcome": {}, "byReasonCode": {}, "byState": {}, "latest": ["C-000008"]}
    Set total = {"count": 7, "unique": 6, "byFailureKind": {}, "byOutcome": {}, "byReasonCode": {"ward_unavailable": 1}, "byState": {}, "latest": ["C-000009"]}
    Do total.byReasonCode.%Set(leak, 2)
    Set cases = {}
    Do cases.%Set("Lab Out", lab), cases.%Set("Ward Out", ward), cases.%Set("ZEBEDEE TESTPATIENT ward feed", feed), cases.%Set("_total", total)
    Set result.caseAggregates = cases
    Set req = ..Request(result)
    Do $$$AssertTrue($ISOBJECT(req), "the request is built")
    Quit:'$ISOBJECT(req)
    Set payload = ..Payload(req)
    Set ptr = 0
    While $LISTNEXT($LISTFROMSTRING(..#NEEDLES), ptr, needle) {
        Do $$$AssertNotTrue(payload [ needle, needle _ " is not in what the model is sent")
    }
    Set sent = {}.%FromJSON(req.Context).cases
    Do $$$AssertTrue($ISOBJECT(sent.%Get("Lab Out")) && $ISOBJECT(sent.%Get("Ward Out")), "the production's items are named as they are")
    Set shown = ##class(Shutter.Process.Review).Withheld("ZEBEDEE TESTPATIENT ward feed")
    Do $$$AssertTrue($ISOBJECT(sent.%Get(shown)), "an item key that is no item of the production goes as its digest: " _ shown)
    Do $$$AssertEquals(sent.%Get(shown).count, 1, "with its count")
    Set a = sent.%Get("Lab Out")
    Do $$$AssertEquals(a.count, 4, "the item's count is as it was")
    Do $$$AssertEquals(a.latest.%Get(0), "C-000004", "and its newest case ids")
    Do $$$AssertEquals(a.byFailureKind."delivery_failed", 3, "a failure kind is a code and is kept")
    Do $$$AssertEquals(a.byReasonCode."ward_unavailable", 1, "a reason code of a code's shape is kept")
    Do $$$AssertEquals(a.byReasonCode."HTTP_503", 1, "with digits in it")
    Do $$$AssertEquals(a.byOutcome.AR, 1, "an outcome code is kept")
    Do $$$AssertEquals(a.byOutcome."(none)", 1, "and the sweep's word for no value")
    Do $$$AssertEquals(a.byReasonCode.%Get(##class(Shutter.Process.Review).Withheld(leak)), 2, "a reason code that is free text goes as its digest, with its count")
    Do $$$AssertEquals(a.byOutcome.%Get(##class(Shutter.Process.Review).Withheld("T9990001")), 2, "a code's shape with an identifier's run of digits is withheld too")
    Do $$$AssertEquals(a.byState.escalated, 4, "a state is kept")
    Do $$$AssertEquals(sent."_total".byReasonCode.%Get(##class(Shutter.Process.Review).Withheld(leak)), 2, "the production's totals are reduced the same way")
    Do $$$AssertEquals(sent."_total".count, 7, "and keep their count")
    // The stored aggregates are the operator's: building the request leaves them whole.
    Do $$$AssertEquals(cases.%Get("Lab Out").byReasonCode.%Get(leak), 2, "the review keeps the reason code's text")
    Do $$$AssertTrue($ISOBJECT(cases.%Get("ZEBEDEE TESTPATIENT ward feed")), "and the item key")
    Do $$$AssertEquals(req.SnapshotDigest, clean.SnapshotDigest, "SnapshotDigest does not move with the aggregates")
    Do $$$AssertEquals(req.RecordKey, clean.RecordKey, "nor does the record key")
}

/// A key of the aggregates as the model reads it.
Method TestModelKey()
{
    Set m = "Shutter.Process.Review"
    Set known("Lab Out") = ""
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelKey", "Lab Out", .known), "Lab Out", "an item of the production is kept")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelKey", "NO_BOARD_ANSWER", .known), "NO_BOARD_ANSWER", "a code is kept")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelKey", "(none)", .known), "(none)", "the word for no value is kept")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelKey", "", .known), "", "nothing gives nothing")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelKey", "Lab In", .known), $CLASSMETHOD(m, "Withheld", "Lab In"), "a name with a space that is no known item is withheld")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelKey", "ABC1234", .known), $CLASSMETHOD(m, "Withheld", "ABC1234"), "four digits in a row are withheld")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelKey", $TRANSLATE($JUSTIFY("", 41), " ", "A"), .known), $CLASSMETHOD(m, "Withheld", $TRANSLATE($JUSTIFY("", 41), " ", "A")), "more than 40 marks is withheld")
}

/// The model's form of a signature: IRIS error codes as they are, any other text as a digest that is the same each time.
Method TestModelSignature()
{
    Set m = "Shutter.Process.Review"
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelSignature", ""), "", "nothing gives nothing")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelSignature", "ERROR #5001"), "ERROR #5001", "an error number is kept")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelSignature", "ERROR <Ens>ErrBPTerminated"), "ERROR <Ens>ErrBPTerminated", "an Ens error code is kept")
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelSignature", "ERROR <%ObjectErrors>InvalidOref"), "ERROR <%ObjectErrors>InvalidOref", "a % domain is kept")
    Set text = "Patient ZEBEDEE, TESTPATIENT (MRN T9990001) not found"
    Set shown = $CLASSMETHOD(m, "ModelSignature", text)
    Do $$$AssertTrue($EXTRACT(shown, 1, 15) = "[withheld text ", "free text is withheld: " _ shown)
    Do $$$AssertEquals($CLASSMETHOD(m, "ModelSignature", text), shown, "the same text gives the same digest")
    Do $$$AssertTrue($CLASSMETHOD(m, "ModelSignature", text _ "!") '= shown, "another text another")
    Do $$$AssertTrue($EXTRACT($CLASSMETHOD(m, "ModelSignature", "ERROR #5001 for ZEBEDEE"), 1, 15) = "[withheld text ", "a code with words after it is withheld")
    Do $$$AssertTrue($EXTRACT($CLASSMETHOD(m, "ModelSignature", "<UNDEFINED>zOnMessage+3^UT.Operation.1 *ZEBEDEE"), 1, 15) = "[withheld text ", "a stack line, which can name a variable, is withheld")
}

}
