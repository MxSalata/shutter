/// What to check at the receiver on a stopped case (Shutter.Util.ReceiverCheck; CONTRACTS 5.2): one test per variant, the
/// allowlist against a synthetic Base64 payload and canary strings, the site's runbook line, and a source check that the
/// class makes no call out. The case is saved under its own id and removed after each test.
Class Shutter.Test.ReceiverCheck Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-RC-0001";

/// Words that must not reach the card, wherever a message or a snapshot carries them.
Parameter CANARY = "CANARYNOTE7731";

Parameter BASE64 = "JVBERi0xLjQKQ0FOQVJZQkFTRTY0UEFZTE9BRA==";

Property CaseRowId As %String;

Property Headers As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ..Purge()
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Purge()
    Set h = ""
    For {
        Set h = $ORDER(i%Headers(h))
        Quit:h=""
        Set header = ##class(Ens.MessageHeader).%OpenId(h)
        If $ISOBJECT(header) Do ##class(EnsLib.HL7.Message).%DeleteId(header.MessageBodyId)
        Do ##class(Ens.MessageHeader).%DeleteId(h)
    }
    Kill i%Headers
    Quit $$$OK
}

Method Purge()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { Do ##class(Shutter.Store.Case).PurgeCase(rs.%Get("ID")) }
}

/// A stopped case with a sealed snapshot of the given summary.
Method Case(event As %String, kind As %String, summary As %DynamicObject = "", receiver As %String = "Downstream Out", headerId As %String = "", text As %String = "") As Shutter.Store.Case
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9100^ENC-9100^" _ event _ "^2026-10-15T08:20:00Z"
    Set c.Event = event, c.EncounterId = "ENC-9100", c.PatientId = "MRN9100", c.PatientIdAuthority = "HOSP"
    Set c.FailureKind = kind, c.State = "escalated", c.Receiver = receiver, c.EventTime = "2026-10-15T08:20:00Z"
    Set c.Ward = "WARD-B", c.Bed = "BAY2-04", c.SourceSystem = "PAS", c.SourceMessageId = "MSG9100", c.SourceHeaderId = headerId
    Set c.FailureText = $SELECT(text '= "": text, 1: "Delivery unavailable " _ ..#CANARY)
    Do $$$AssertStatusOK(c.%Save(), "the case saves")
    Set ..CaseRowId = c.%Id()
    If $ISOBJECT(summary) {
        Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
        Do $$$AssertStatusOK(snap.Seal(summary), "the snapshot seals")
        Do c.SetSnapshot(snap)
    }
    Quit ##class(Shutter.Store.Case).%OpenId(c.%Id())
}

/// A receiver that answered: the encounter as read, with its history.
ClassMethod ReadSummary(ward As %String = "WARD-A", history As %DynamicArray = "") As %DynamicObject
{
    Set s = {"ward_state_http_status": 200, "observed_at": "2026-11-02T14:18:46Z", "later_events": 0, "receipt": {"error": "no_receipt"}, "receipt_http_status": 404, "timeline": []}
    Set s."ward_state" = {"encounter_id": "ENC-9100", "patient_id": "MRN9100", "state": "admitted", "ward": (ward), "bed": "BAY1-01", "version": 2}
    Set s."ward_state".history = $SELECT($ISOBJECT(history): history, 1: [])
    Set s.message = {"notes": [{"segment": "OBX", "text": (..#BASE64)}, {"segment": "NTE", "text": (..#CANARY)}], "patient_name": (..#CANARY)}
    Quit s
}

/// An HL7 message stored with a header, as the intake stores its copy; returns the header's id.
Method Stored(text As %String) As %String
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString($REPLACE(text, "\r", $CHAR(13)), .sc)
    Do $$$AssertStatusOK(sc, "the message imports")
    Do msg.%Save()
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = msg.%Id()
    Do h.%Save()
    Set i%Headers(h.%Id()) = ""
    Quit h.%Id()
}

ClassMethod Doc(control As %String = "DOC1", txa As %String = "TXA|1|CN|TX|20261105090000||||||||DOCNUM-77|||||LA") As %String
{
    Quit "MSH|^~\&|DOCS|DOC|DMS|DOC|20261105090500||MDM^T02|" _ control _ "|P|2.5.1\rPID|1||MRN9100^^^HOSP^MR||" _ ..#CANARY _ "^BOB||19800202|M\rPV1|1|O|CLINIC1||||||||||||||||ENC-9100\r" _ txa _ "\rNTE|1||" _ ..#CANARY _ "\rOBX|1|ED|DOC^Letter||^application^pdf^Base64^" _ ..#BASE64 _ "||||||F\r"
}

ClassMethod Oru(obr As %String = "OBR|1|PL2|FILL-88|FBC^Full blood count|||20261105083000||||||||||||||||||F", more As %String = "") As %String
{
    Quit "MSH|^~\&|LIMS|PATH|OCS|PATH|20261105090500||ORU^R01|ORU1|P|2.5.1\rPID|1||MRN9100^^^HOSP^MR||" _ ..#CANARY _ "^BOB||19800202|M\rPV1|1|O|CLINIC1||||||||||||||||ENC-9100\rORC|RE|PL2|FILL-88\r" _ obr _ "\rNTE|1||" _ ..#CANARY _ "\rOBX|1|ED|PDF^Report||^application^pdf^Base64^" _ ..#BASE64 _ "||||||F\r" _ more
}

/// The field on the card whose label starts with the given words.
ClassMethod Field(out As %DynamicObject, label As %String) As %DynamicObject
{
    Set it = out.messageRequest.fields.%GetIterator()
    While it.%GetNext(, .f) { If $EXTRACT(f.label, 1, $LENGTH(label)) = label Return f }
    Quit ""
}

Method AssertClean(out As %DynamicObject)
{
    Set text = out.%ToJSON()
    Do $$$AssertTrue(text '[ ..#BASE64, "no Base64 payload on the card")
    Do $$$AssertTrue(text '[ "CANARY", "no canary on the card")
    For key = """verified""", """safe_to_resend""", """action""", """confidence""", """expected""" { Do $$$AssertTrue(text '[ key, "no field " _ key) }
    Set low = $ZCONVERT(text, "L")
    For words = "safe to resend", "expected result", "safe to send" { Do $$$AssertTrue(low '[ words, "the words never say " _ words) }
}

Method TestNoApiReceiver()
{
    // A read that got no answer here; tests/e2e/receiver_check.py plays a receiver with no API at all.
    Set c = ..Case("transfer", "delivery_failed", {"ward_state": {}, "ward_state_http_status": 0, "observed_at": "2026-11-02T14:18:46Z", "later_events": 0, "timeline": []})
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "manual_compare", "nothing more specific: compare by hand")
    Do $$$AssertTrue(out.guideDigest ?1"sha256:"64AN, "one digest of the words: " _ out.guideDigest)
    Do $$$AssertEquals(out.receiverEvidence, "unavailable", "no receiver evidence")
    Do $$$AssertTrue(out.evidenceNote [ "don't show what the receiver holds now", "it says so: " _ out.evidenceNote)
    Do $$$AssertTrue(out.queueWarning [ "may still arrive", "the queue warning")
    Do $$$AssertEquals(out.identity.encounterId, "ENC-9100", "the identity strip names the encounter")
    Do $$$AssertEquals(..Field(out, "Ward").value, "WARD-B", "what the message asked")
    Do $$$AssertEquals(..Field(out, "Ward").source, "message", "from the message")
    Do $$$AssertTrue(out.checks.%Get(0).where [ "movement history", "where to look")
    Do $$$AssertEquals(out.checks.%Get(0).meanings.%Size(), 4, "what each answer would mean")
    Do $$$AssertTrue(out.unknown.%Size() > 0, "what remains unknown")
    Do ..AssertClean(out)
}

Method TestUsableEvidenceIsDated()
{
    Set c = ..Case("transfer", "delivery_failed", ..ReadSummary())
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.receiverEvidence, "read", "read")
    Do $$$AssertTrue(out.evidenceNote [ "2026-11-02 14:18:46 UTC", "dated: " _ out.evidenceNote)
    Do $$$AssertEquals(out.receiverRead.ward, "WARD-A", "the ward as read")
    Do ..AssertClean(out)
}

Method TestLaterMovement()
{
    Set history = [{"event": "admit", "ward": "WARD-A", "event_time": "2026-10-15T08:00:00Z", "operation_key": "PAS^a"}, {"event": "transfer", "ward": "WARD-C", "bed": "BAY1-07", "event_time": "2026-10-15T08:20:00Z", "operation_key": "BEDMGR^b"}]
    Set c = ..Case("transfer", "delivery_failed", ..ReadSummary("WARD-C", history))
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "later_movement", "a later movement is known")
    Do $$$AssertTrue(out.laterMovement.summary [ "WARD-C", "it is named: " _ out.laterMovement.summary)
    Do $$$AssertTrue(out.messageRequest.note [ "Never move the patient back", "the note: " _ out.messageRequest.note)
    Do ..AssertClean(out)
}

Method TestAlreadyApplied()
{
    Set s = ..ReadSummary("WARD-B")
    Set s."receipt_http_status" = 200, s.receipt = {"operation_key": "PAS^HOSP^MRN9100^ENC-9100^transfer^2026-10-15T08:20:00Z", "ward": "WARD-B"}
    Set c = ..Case("transfer", "uncertain_outcome", s)
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "already_applied", "a receipt names this operation")
    Do ..AssertClean(out)
    // A matching location with no receipt is not this outcome.
    Do ..Purge()
    Set c = ..Case("transfer", "delivery_failed", ..ReadSummary("WARD-B"))
    Do $$$AssertNotEquals(##class(Shutter.Util.ReceiverCheck).ForCase(c).variant, "already_applied", "not made from a matching location")
}

Method TestOccupiedBedNamesNoOtherPatient()
{
    Set s = ..ReadSummary()
    Set s."bed_conflict" = {"refused": true, "ward": "WARD-B", "bed": "BAY2-04", "occupant": {"encounter_id": "ENC-OTHER-CANARY", "ward": "WARD-B"}, "occupant_movement": {"operation_key": "PAS^HOSP^MRN-OTHER-CANARY", "case_id": "C-CANARY"}, "status": "occupant_staying", "note": "CANARY occupant"}
    Set c = ..Case("transfer", "rejected", s, , , "Delivery refused (bed_occupied) by CANARY occupant MRN-OTHER")
    Set c.FailureReasonCode = "bed_occupied", c.WaitsOnCase = "C-CANARY"
    Do c.%Save()
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "refusal", "a refusal")
    Do $$$AssertTrue(out.messageRequest.summary [ "occupied", "said in fixed words: " _ out.messageRequest.summary)
    Do $$$AssertTrue(out.%ToJSON() '[ "MRN-OTHER", "no other patient's number")
    Do $$$AssertTrue(out.%ToJSON() '[ "ENC-OTHER", "no other patient's encounter")
    Do ..AssertClean(out)
}

Method TestUnknownEncounterOrDoubtfulTime()
{
    Set s = ..ReadSummary()
    Set s.catalogue = {"entry": "E13"}
    Set c = ..Case("transfer", "delivery_failed", s)
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "identity_or_time", "a doubtful time")
    Do $$$AssertEquals(..Field(out, "Effective time").source, "doubtful", "the time is marked doubtful")
    Do ..AssertClean(out)
    Do ..Purge()
    Set s = {"ward_state": {"error": "not_found"}, "ward_state_http_status": 404, "later_events": 0, "timeline": [], "catalogue": {"entry": "E11"}}
    Set c = ..Case("transfer", "delivery_failed", s)
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "identity_or_time", "an unknown encounter")
    Do $$$AssertTrue(out.checks.%Get(0).meanings.%ToJSON() [ "guess", "never guess the record: " _ out.checks.%Get(0).meanings.%ToJSON())
}

Method TestUncertainOutcome()
{
    Set c = ..Case("transfer", "uncertain_outcome", ..ReadSummary())
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "uncertain", "the outcome is uncertain")
    Do $$$AssertTrue(out.messageRequest.summary [ "The send got no answer.", "the summary says the send got no answer: " _ out.messageRequest.summary)
    Do $$$AssertNotTrue(out.messageRequest.summary [ "Shutter sent", "a site's own engine may have sent it")
    Do $$$AssertTrue(out.checks.%Get(0).meanings.%ToJSON() [ "finished", "a match doesn't show the attempt finished")
    Do ..AssertClean(out)
}

Method TestHistoryCorrection()
{
    Set c = ..Case("transfer", "delivery_failed", ..ReadSummary("WARD-C"))
    Set plan = ##class(Shutter.Store.Plan).%New()
    Do plan.CaseSetObjectId(c.%Id())
    Set plan.Version = 1, plan.CreatedBy = "unit", plan.Disposition = "escalate"
    Set plan.Json = {"disposition": "escalate", "correction_steps": {"steps": ["Step CANARY"]}}.%ToJSON()
    Do $$$AssertStatusOK(plan.%Save(), "the plan saves")
    Set c.CurrentPlan = plan
    Do c.%Save()
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "history_correction", "the history needs correcting")
    Do $$$AssertTrue(out.checks.%Get(0).meanings.%ToJSON() [ "current placement", "the current placement is kept")
    Do ..AssertClean(out)
}

Method TestFailedT02()
{
    Set c = ..Case("T02", "unmappable", {"later_events": 0, "timeline": [], "ward_state": {"state": "admitted"}, "ward_state_http_status": 200}, , ..Stored(..Doc()), "This message is MDM, not ADT: Shutter resends only ADT")
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "document", "a document check")
    Do $$$AssertEquals(out.receiverEvidence, "unavailable", "Shutter reads no document list")
    Do $$$AssertEquals(..Field(out, "Document number").value, "DOCNUM-77", "TXA-12")
    Do $$$AssertEquals(..Field(out, "Document time").value, "2026-11-05 09:00:00 UTC", "TXA-4")
    Do $$$AssertEquals(..Field(out, "Status").value, "LA", "TXA-17")
    Do $$$AssertEquals(out.identity.messageType, "MDM^T02", "the message type")
    Do $$$AssertEquals(out.identity.timeLabel, "Message time", "not called the event time")
    Do $$$AssertTrue(out.checks.%Get(0).where [ "unfiled", "the document list and the unfiled queue")
    Do ..AssertClean(out)
    Do $$$AssertNotEquals(..Field(out, "Document number").value, "DOC1", "MSH-10 is not offered as the document number")
}

Method TestT02WithoutANumber()
{
    Set c = ..Case("T02", "unmappable", {"later_events": 0}, , ..Stored(..Doc("CTRL2", "TXA|1|CN|TX")), "This message is MDM, not ADT: Shutter resends only ADT")
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Set f = ..Field(out, "Document number")
    Do $$$AssertEquals(f.value, "Not available from this message", "said, not blank")
    Do $$$AssertEquals(f.source, "unavailable", "marked")
    Do $$$AssertEquals(out.identity.controlId, "MSG9100", "the control id stays in the identity strip")
}

Method TestT02WithNoStoredMessage()
{
    Set c = ..Case("T02", "unmappable", "", , "", "This message is MDM, not ADT: Shutter resends only ADT")
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "document", "still a document check")
    Do $$$AssertEquals(..Field(out, "Document number").source, "unavailable", "nothing to read it from")
    Do $$$AssertEquals(out.snapshotId, "", "no snapshot yet")
}

Method TestFailedOruR01()
{
    Set c = ..Case("R01", "unmappable", {"later_events": 0}, , ..Stored(..Oru()), "This message is ORU, not ADT: Shutter resends only ADT")
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "result", "a result check")
    Set f = ..Field(out, "Order or report number")
    Do $$$AssertEquals(f.value, "FILL-88", "OBR-3 first")
    Do $$$AssertTrue(f.label [ "filler", "says which number: " _ f.label)
    Do $$$AssertEquals(..Field(out, "Observation time").value, "2026-11-05 08:30:00 UTC", "OBR-7")
    Do $$$AssertEquals(..Field(out, "Status").value, "F", "OBR-25")
    Do $$$AssertEquals(out.limitations.%Size(), 0, "one report item")
    Do ..AssertClean(out)
}

Method TestOruSeveralItemsAndPlacerNumber()
{
    Set c = ..Case("R01", "unmappable", {"later_events": 0}, , ..Stored(..Oru("OBR|1|PL2||FBC", "OBR|2|PL3||LFT\r")), "This message is ORU, not ADT: Shutter resends only ADT")
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(..Field(out, "Order or report number").value, "PL2", "the placer's when there is no filler's")
    Do $$$AssertEquals(out.limitations.%Size(), 1, "more than one item is said")
    Do $$$AssertTrue(out.limitations.%Get(0) [ "more than one", out.limitations.%Get(0))
    Do ..AssertClean(out)
}

Method TestOtherMessagesGetNoCheckOfTheirOwn()
{
    Set c = ..Case("O01", "unmappable", {"later_events": 0}, , "", "This message is ORM, not ADT: Shutter resends only ADT")
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "other_message", "not built for")
    Do $$$AssertTrue(out.limitations.%Size() = 1, "it says so")
    Set c.Event = "T04"
    Do $$$AssertEquals(##class(Shutter.Util.ReceiverCheck).ForCase(c).variant, "other_message", "T04 too")
}

Method TestWithheld()
{
    Set c = ..Case("merge", "withheld", ..ReadSummary(), , , "Withheld by the site's policy: merges go to the PAS team")
    Set c.PriorPatientId = "MRN9099"
    Do c.%Save()
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.variant, "withheld", "a withheld merge")
    Do $$$AssertTrue(out.messageRequest.summary [ "MRN9099", "what it asked: " _ out.messageRequest.summary)
    Do $$$AssertTrue(out.checks.%Get(0).meanings.%ToJSON() [ "neither approves", "the card neither approves nor proves")
    Do ..AssertClean(out)
    Set c.Event = "cancel_transfer"
    Do $$$AssertEquals(##class(Shutter.Util.ReceiverCheck).ForCase(c).variant, "withheld", "a withheld cancel")
}

Method TestMissingValuesAreSaid()
{
    Set c = ..Case("transfer", "delivery_failed", "")
    Set c.Bed = "", c.EncounterId = "-", c.PatientIdAuthority = ""
    Do c.%Save()
    Set out = ##class(Shutter.Util.ReceiverCheck).ForCase(c)
    Do $$$AssertEquals(out.identity.encounterId, "No encounter supplied", "a message with no visit")
    Do $$$AssertEquals(out.identity.authority, "Not available from this message", "no authority")
    Do $$$AssertEquals(..Field(out, "Bed").value, "Not available from this message", "no bed")
}

Method TestRunbookIsShownAsAHint()
{
    Do $$$AssertEquals(##class(Shutter.Util.ReceiverCheck).RunbookOf("A receiver no profile names"), "", "absent when the receiver has none")
    Set p = {"receivers": [{"name": "R", "manual_check": {"runbook": "In Encounter > Movements, search hospital number and visit number."}}]}
    Do $$$AssertEquals(##class(Shutter.Util.ReceiverCheck).RunbookIn(p, "R"), "In Encounter > Movements, search hospital number and visit number.", "read back")
    Set p.receivers.%Get(0)."manual_check".runbook = "<b>stored before the rule</b>"
    Do $$$AssertEquals(##class(Shutter.Util.ReceiverCheck).RunbookIn(p, "R"), "", "a line that fails the rule is not shown")
}

Method TestRunbookValidation()
{
    Set rc = "Shutter.Util.ReceiverCheck"
    Do $$$AssertEquals($CLASSMETHOD(rc, "ManualCheckProblem", {"runbook": "In Encounter > Movements, search the visit number; compare ward, bed and time."}), "", "a plain line passes")
    For bad = "<b>x</b>", "see http://pas.example/x", "see www.example.org", "password: hunter2", "api key = abc", "patient 1234567", "two" _ $CHAR(10) _ "lines", "  ", $TRANSLATE($JUSTIFY("", 301), " ", "x") {
        Do $$$AssertTrue($CLASSMETHOD(rc, "ManualCheckProblem", {"runbook": (bad)}) '= "", "refused: " _ $EXTRACT(bad, 1, 30))
    }
    Do $$$AssertEquals($CLASSMETHOD(rc, "ManualCheckProblem", {"runbook": ($TRANSLATE($JUSTIFY("", 300), " ", "x"))}), "", "300 characters pass")
    Do $$$AssertTrue($CLASSMETHOD(rc, "ManualCheckProblem", {"other": "x"}) [ "unknown", "an unknown key")
    Do $$$AssertTrue($CLASSMETHOD(rc, "ManualCheckProblem", {"runbook": 5}) '= "", "a number")
    Do $$$AssertTrue($CLASSMETHOD(rc, "ManualCheckProblem", "text") '= "", "not an object")
    // Through the profile's own validator, which names the field.
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Set p.receivers.%Get(0)."manual_check" = {"runbook": "<script>"}
    Set problem = ##class(Shutter.Store.SiteProfile).Validate(p)
    Do $$$AssertTrue(problem [ "receivers[0].manual_check", "the profile refuses it: " _ problem)
    Set p.receivers.%Get(0)."manual_check" = {"runbook": "Clinical Documents: check Filed and Unfiled."}
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "the profile takes a good line")
}

/// The email for a stopped case makes no promise a receiver Shutter cannot read would break.
Method TestTheEscalationPromisesNoVerification()
{
    Set c = ..Case("transfer", "delivery_failed", ..ReadSummary())
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(c, {"name": "Team"}, .subject, .body), "the draft builds")
    Do $$$AssertTrue(body '[ "verifies the correction", "no such promise")
    Do $$$AssertTrue(body [ "does not show that this message was delivered", "it says what a new investigation doesn't show")
}

/// The class names no way out: no HTTP, no production request, no receiver path, no model; and it writes nothing.
Method TestTheClassCallsNothingOut()
{
    Set def = ##class(%Dictionary.ClassDefinition).%OpenId("Shutter.Util.ReceiverCheck")
    Set text = ""
    For i = 1:1:def.Methods.Count() {
        Set stream = def.Methods.GetAt(i).Implementation
        Do stream.Rewind()
        Set text = text _ stream.Read(1000000)
    }
    For word = "%Net.", "SendRequest", "Ens.Director", "%Save", "%Delete", "%AI", "Transition(", "Note(", "INSERT ", "UPDATE " {
        Do $$$AssertTrue(text '[ word, "the class does not use " _ word)
    }
}

}
