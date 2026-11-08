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
