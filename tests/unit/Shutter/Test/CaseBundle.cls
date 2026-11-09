/// One case's bundle for audit and support handoff (Shutter.API.CaseBundle): the first line says it is redacted, it holds
/// the seven parts, nothing the model view removes is in it, what people typed stays in IRIS, it refuses rather than
/// sends a case it cannot redact, and each download leaves a record. An approver's unredacted file says so on its first
/// line, needs a reason, and takes nothing from the redacted one. No download changes a closed case's receipt. The test
/// case and its rows are saved under their own ids and removed afterwards.
Class Shutter.Test.CaseBundle Extends %UnitTest.TestCase
{

Property CaseRowId As %String;

Property HeaderId As %String;

Property BodyId As %String;

Parameter MESSAGE = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015082000||ADT^A02^ADT_A02|UTCB1|P|2.5.1<CR>EVN|A02|20261015082000||||20261015082000<CR>PID|1||MRN9103^^^HOSP^MR~9991001018^^^NHS^NH||LI^AN^J~LEWIS^ANNE||19800101|F<CR>PV1|1|I|WARD-B^BAY1^01^HOSP||||||||||||||||ENC-9103";

Parameter KEY = "PAS^HOSP^MRN9103^ENC-9103^transfer^2026-10-15T08:20:00Z";

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString($REPLACE(..#MESSAGE, "<CR>", $CHAR(13)), .sc)
    Quit:$$$ISERR(sc) sc
    Do msg.PokeDocType("2.5.1:ADT_A02")
    Set sc = msg.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..BodyId = msg.%Id()
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = msg.%Id()
    Set sc = h.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..HeaderId = h.%Id()
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "UT-BUNDLE", c.OperationKey = ..#KEY, c.Event = "transfer", c.EncounterId = "ENC-9103"
    Set c.PatientId = "MRN9103", c.PatientIdAuthority = "HOSP", c.FailureKind = "rejected", c.SourceHeaderId = h.%Id()
    Set c.FailureText = "422 for LI, AN (MRN9103)", c.Receiver = "Bed Manager", c.Headline = "Lewis, Anne: transfer refused"
    Set sc = c.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..CaseRowId = c.%Id()
    Quit ..Fill(c)
}

/// A snapshot, a plan, a gate decision, an approval with a comment, an attempt and a verification, each holding the
/// patient's identifiers the way the stored rows do.
Method Fill(c As Shutter.Store.Case) As %Status
{
    Set summary = {"case_id": "UT-BUNDLE", "scenario": "", "operation": {"operation_key": (..#KEY), "encounter_id": "ENC-9103", "patient_id": "MRN9103", "event": "transfer", "ward": "WARD-B", "payload_digest": "sha256:ab"}}
    Set summary.failure = {"kind": "rejected", "outcome": "rejected", "text": "422 for LI, AN (mrn9103) born 19800101"}
    Set summary.message = {"message_control_id": "UTCB1", "message_type": "ADT^A02", "sending_application": "PAS", "patient_identifier": "MRN9103^^^HOSP^MR", "visit_number": "ENC-9103", "patient_name": "LEWIS^ANNE", "date_of_birth": "1980-01-01", "notes": [{"segment": "NTE", "position": 1, "text": "Mrs Lewis fell at home"}]}
    Set summary."ward_state" = {"encounter_id": "ENC-9103", "patient_id": "MRN9103", "state": "admitted", "ward": "WARD-A", "version": 3, "address": "1 High Street"}
    Set s = ##class(Shutter.Store.Snapshot).Begin(c)
    Do s.AddItem("message", "message_store", "2026-10-15T08:21:00Z", summary.message)
    Do s.AddItem("ward_state", "ward_api", "2026-10-15T08:21:00Z", summary."ward_state")
    Set sc = s.Seal(summary)
    Quit:$$$ISERR(sc) sc
    Set plan = {"disposition": "resend", "summary": "Resend for Lewis on ENC-9103", "why": "MRN9103 was refused", "action": {"type": "resend", "operation_key": (..#KEY), "expected_version": 3, "payload_digest": "sha256:ab"}, "preconditions": ["encounter ENC-9103 is at version 3"], "evidence_refs": ["ward_state"]}
    Set sc = ##class(Shutter.Store.Plan).Create(c, s, plan, "system", .p)
    Quit:$$$ISERR(sc) sc
    Set checks = [{"check": "identity", "result": "pass", "reason_code": "IDENTITY_MATCHES", "detail": "The receiver's encounter ENC-9103 belongs to MRN9103 (HOSP)"}]
    Set sc = ##class(Shutter.Store.GateDecision).Create(c, p, "proposal", "1", "pass", checks, "Passed for ENC-9103", .d)
    Quit:$$$ISERR(sc) sc
    Set sc = ##class(Shutter.Store.Approval).Create(c, p, s, "1", "", 3, "approver", "approved", "Spoke to her daughter on 07700 900123", "", 3600, .a)
    Quit:$$$ISERR(sc) sc
    Set sc = ##class(Shutter.Store.ExecutionAttempt).Create(c, p, a, "", 200, "applied", {"receipt": {"operation_key": (..#KEY), "encounter_id": "ENC-9103", "event": "transfer", "applied_at": "2026-10-15T08:22:00Z", "payload_digest": "sha256:ab", "version_after": 4}, "patient_name": "LEWIS^ANNE"}, "", .e)
    Quit:$$$ISERR(sc) sc
    Set sc = ##class(Shutter.Store.Verification).Create(c, e, "verified", "Committed and current for ENC-9103", {"encounter": {"encounter_id": "ENC-9103", "patient_id": "MRN9103", "state": "admitted", "ward": "WARD-B", "version": 4}}, .v)
    Quit:$$$ISERR(sc) sc
    Set c.CurrentSnapshot = s, c.CurrentPlan = p, c.CurrentApproval = a
    Quit c.%Save()
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set id = ..CaseRowId
    If id '= "" {
        &sql(UPDATE Shutter_Store."Case" SET CurrentSnapshot = NULL, CurrentPlan = NULL, CurrentApproval = NULL WHERE ID = :id)
        &sql(DELETE FROM Shutter_Store.Verification WHERE "Case" = :id)
        &sql(DELETE FROM Shutter_Store.ExecutionAttempt WHERE "Case" = :id)
        &sql(DELETE FROM Shutter_Store.Approval WHERE "Case" = :id)
        &sql(DELETE FROM Shutter_Store.GateDecision WHERE "Case" = :id)
        &sql(DELETE FROM Shutter_Store.Plan WHERE "Case" = :id)
        &sql(DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE "Case" = :id))
        &sql(DELETE FROM Shutter_Store.Snapshot WHERE "Case" = :id)
        &sql(DELETE FROM Shutter_Store.CaseToken WHERE "Case" = :id)
        &sql(DELETE FROM Shutter_Store.CaseEvent WHERE "Case" = :id)
        Kill ^Shutter.Counter("event", id), ^Shutter.Counter("snapshot", id), ^Shutter.Counter("plan", id)
        Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
    Do ##class(Ens.MessageHeader).%DeleteId(..HeaderId)
    Quit ##class(EnsLib.HL7.Message).%DeleteId(..BodyId)
}

Method Case() As Shutter.Store.Case
{
    Quit ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
}

Method Events() As %Integer
{
    Set id = ..CaseRowId, n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND Text LIKE 'Case bundle%')
    Quit +n
}

/// The file says what it is before anything else, and is still one JSON document with every part.
Method TestFirstLineSaysItIsRedacted()
{
    Set text = ##class(Shutter.API.CaseBundle).Text(..Case(), "operator", .why)
    Do $$$AssertTrue(text '= "", "a bundle is built: " _ $GET(why))
    Set first = $PIECE(text, $CHAR(10), 1)
    Do $$$AssertTrue(first [ "REDACTED", "the first line says it is redacted: " _ first)
    Do $$$AssertTrue(first [ "tokens", "and how")
    Do $$$AssertTrue(first [ "Ward", "and what stays")
    Set o = ##class(%DynamicObject).%FromJSON(text)
    For part = "evidence", "plans", "gateDecisions", "approvals", "attempts", "verifications" {
        Do $$$AssertEquals(o.%GetTypeOf(part), "array", part _ " is there")
        Do $$$AssertEquals(o.%Get(part).%Size(), 1, part _ " has its row")
    }
    Do $$$AssertTrue(o.%IsDefined("receipt"), "the receipt's place is there")
    Do $$$AssertEquals(o.case.caseId, "UT-BUNDLE", "the case is named")
    Do $$$AssertEquals(o.evidence.%Get(0).items.%Size(), 2, "with the evidence's items")
    Set action = o.plans.%Get(0).plan.action
    Do $$$AssertEquals(action.type, "resend", "a plan's action keeps its type")
    Do $$$AssertEquals(action."expected_version", 3, "and its expected version")
    Do $$$AssertEquals(action."operation_key", "PAS^HOSP^MRN-T1^ENC-T1^transfer^2026-10-15T08:20:00Z", "and its key, in tokens")
}

/// Nothing the model view removes is anywhere in the file: identifiers, name parts, birth date, demographics, the
/// note's text. The tokens stand in their place, and the map that undoes them is not there.
Method TestNoIdentifierLeaves()
{
    Set c = ..Case()
    Set c.State = "resolved", c.Disposition = "resend", c.Outcome = "Committed and current for ENC-9103 (MRN9103)"
    Do c.%Save()
    Set text = ##class(Shutter.API.CaseBundle).Text(c, "operator", .why)
    Do $$$AssertTrue(text '= "", "a bundle is built: " _ $GET(why))
    Set upper = $ZCONVERT(text, "U")
    For gone = "MRN9103", "ENC-9103", "9991001018", "LEWIS", "ANNE", "19800101", "1980-01-01", "1 HIGH STREET", "FELL AT HOME", "LI,", "07700" {
        Do $$$AssertNotTrue(upper [ gone, gone _ " is not in the file")
    }
    Do $$$AssertTrue(text [ "MRN-T1", "the patient's token stands in")
    Do $$$AssertTrue(text [ "ENC-T1", "and the encounter's")
    Do $$$AssertTrue(text [ "free_text_present", "the note is a flag")
    Do $$$AssertNotTrue(text [ """value""", "the token map is not in the file")
}

/// A site that lets its model read notes has not said they may leave in a file: the text stays out either way.
Method TestNoteTextStaysOutWhateverTheModelSwitch()
{
    Set node = {"message": {"notes": [{"segment": "NTE", "free_text_present": true, "instruction_like": false, "text": "Mrs NAME-T1 fell"}]}}
    Do ##class(Shutter.API.CaseBundle).DropNoteText(node)
    Set note = node.message.notes.%Get(0)
    Do $$$AssertNotTrue(note.%IsDefined("text"), "the text is gone")
    Do $$$AssertTrue(note.note [ "stays in IRIS", "and the flag says where it is")
}

/// What a person typed was never in the model view's map: an approver's comment and a hand closure's reason stay in
/// IRIS. That there was one, and who decided, go.
Method TestWhatPeopleTypedStaysIn()
{
    Set c = ..Case()
    Do c.Note("note", "for the record", "operator")
    Set c.State = "resolved", c.Disposition = "handled_by_hand"
    Set c.Outcome = "Handled by hand, recorded by operator: rang Mrs Jones at home, she confirmed the bay"
    Do c.%Save()
    Set text = ##class(Shutter.API.CaseBundle).Text(c, "operator", .why)
    Do $$$AssertTrue(text '= "", "a bundle is built: " _ $GET(why))
    Do $$$AssertNotTrue(text [ "daughter", "the approver's comment stays")
    Do $$$AssertNotTrue(text [ "Jones", "the reason stays")
    Set o = ##class(%DynamicObject).%FromJSON(text)
    Do $$$AssertEquals(o.approvals.%Get(0).commentPresent, 1, "the file says there was a comment")
    Do $$$AssertEquals(o.approvals.%Get(0).approver, "approver", "and who decided")
    Do $$$AssertTrue(o.receipt.outcome [ "recorded by operator", "and who closed it: " _ o.receipt.outcome)
    Do $$$AssertTrue(o.receipt.outcome [ "stays in IRIS", "and where the reason is")
}

/// The receipt is the closure record, whole, once the case is closed; before then it is null, not an error.
Method TestReceiptOnceClosed()
{
    Set c = ..Case()
    Set c.State = "awaiting_approval"
    Do c.%Save()
    Set o = ##class(%DynamicObject).%FromJSON(##class(Shutter.API.CaseBundle).Text(c, "operator", .why))
    Do $$$AssertEquals(o.%GetTypeOf("receipt"), "null", "an open case has no receipt yet")
    Set c.State = "resolved", c.Disposition = "resend", c.Outcome = "Committed for ENC-9103", c.ClosedAt = "2026-10-15T08:23:00Z"
    Do c.%Save()
    Set o = ##class(%DynamicObject).%FromJSON(##class(Shutter.API.CaseBundle).Text(c, "operator", .why))
    Set r = o.receipt
    Do $$$AssertEquals(r.caseId, "UT-BUNDLE", "the receipt keeps its case")
    Do $$$AssertEquals(r.state, "resolved", "its state")
    Do $$$AssertEquals(r.disposition, "resend", "its disposition")
    Do $$$AssertEquals(r.closedAt, "2026-10-15T08:23:00Z", "its time")
    Do $$$AssertEquals(r.outcome, "Committed for ENC-T1", "its outcome, with the token")
    Do $$$AssertEquals(r.verification.outcome, "verified", "its verification")
    Do $$$AssertTrue(r.%IsDefined("actors"), "who took part")
    Do $$$AssertTrue(r.unverified.%Size() > 0, "and what it did not verify")
    Do $$$AssertTrue(r.%IsDefined("policyVersion"), "and the gate policy")
}

/// A case whose message cannot be read has names no map holds: no file, and the reason, as the model view refuses.
Method TestRefusesWhatItCannotRedact()
{
    Set c = ..Case()
    Set c.SourceHeaderId = "999999999"
    Set before = ..Events()
    Set text = ##class(Shutter.API.CaseBundle).Download(c, "operator", .why)
    Do $$$AssertEquals(text, "", "no file")
    Do $$$AssertTrue(why [ "redact", "the reason says so: " _ why)
    Do $$$AssertNotTrue(why [ "MRN9103", "and names no identifier")
    Do $$$AssertEquals(..Events(), before, "and nothing is recorded as downloaded")
}

/// The last check before a file leaves: a value of the map in a string, or as a key, which the view does not rewrite.
Method TestSweepFindsWhatIsLeft()
{
    Set c = ..Case()
    Do $$$AssertStatusOK(##class(Shutter.Util.ModelView).Learn(c, {}), "the map is learnt")
    Set cb = "Shutter.API.CaseBundle"
    Do $$$AssertEquals($CLASSMETHOD(cb, "Sweep", c, {"a": ["MRN-T1", {"b": "ENC-T1", "ward": "WARD-B"}]}), "", "tokens pass")
    Do $$$AssertEquals($CLASSMETHOD(cb, "Sweep", c, {"a": [{"b": "see mrn9103 here"}]}), "MRN", "a value in a string, by its kind and never its value")
    Do $$$AssertEquals($CLASSMETHOD(cb, "Sweep", c, {"ENC-9103": 1}), "ENC", "a value as a key")
    Do $$$AssertEquals($CLASSMETHOD(cb, "Sweep", c, {"visits": [19800101]}), "DOB", "a value as a number")
}

/// Each download leaves a record on the case with who took it and the file's digest; the case's version does not
/// move, so a file taken while an approver decides stales nothing.
Method TestDownloadLeavesARecord()
{
    Set c = ..Case()
    Set version = c.Version
    Set text = ##class(Shutter.API.CaseBundle).Download(c, "operator", .why)
    Do $$$AssertTrue(text '= "", "a file: " _ $GET(why))
    Do $$$AssertEquals(..Events(), 1, "one record")
    Set id = ..CaseRowId, line = "", actor = ""
    &sql(SELECT TOP 1 Text, Actor INTO :line, :actor FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND Text LIKE 'Case bundle%')
    Do $$$AssertEquals(actor, "operator", "by who took it")
    Do $$$AssertTrue(line [ ##class(Shutter.Util.Digest).SHA256Hex(text), "with the digest of what left: " _ line)
    Do $$$AssertEquals(..Case().Version, version, "the version does not move")
}

/// An approver's file says on its first line that it holds identifiable data, and it does: the identifiers, the name, the
/// note's text and what people typed, with no token in their place.
Method TestUnredactedSaysSoOnItsFirstLine()
{
    Set text = ##class(Shutter.API.CaseBundle).UnredactedText(..Case(), "approver", "The supplier needs the record", .why)
    Do $$$AssertTrue(text '= "", "a file: " _ $GET(why))
    Set first = $PIECE(text, $CHAR(10), 1)
    Do $$$AssertTrue($EXTRACT(first, 1, 25) = "{""redaction"":""UNREDACTED:", "the first line opens with the statement: " _ first)
    Do $$$AssertTrue(first [ "identifiable", "and says it holds identifiable data")
    Set o = ##class(%DynamicObject).%FromJSON(text)
    Do $$$AssertEquals(o.format, "shutter-case-bundle-unredacted/1", "its own format")
    Do $$$AssertEquals(o.reason, "The supplier needs the record", "the reason it was taken for")
    For part = "evidence", "plans", "gateDecisions", "approvals", "attempts", "verifications" {
        Do $$$AssertEquals(o.%Get(part).%Size(), 1, part _ " has its row")
    }
    For seen = "MRN9103", "ENC-9103", "LEWIS^ANNE", "Mrs Lewis fell at home", "Spoke to her daughter" {
        Do $$$AssertTrue(text [ seen, seen _ " is in the file")
    }
    Do $$$AssertNotTrue(text [ "MRN-T1", "and no token stands in")
}

/// No reason, no file and no record, whatever else is right.
Method TestUnredactedNeedsAReason()
{
    For reason = "", "   " {
        Set text = ##class(Shutter.API.CaseBundle).DownloadUnredacted(..Case(), "approver", reason, .why)
        Do $$$AssertEquals(text, "", "no file for the reason '" _ reason _ "'")
        Do $$$AssertTrue(why [ "reason", "the refusal says what is missing: " _ $GET(why))
    }
    Do $$$AssertEquals(..Events(), 0, "and nothing is recorded")
}

/// The reason, who, and the file's digest go on the case, and the version does not move. Taking it learns no token.
Method TestUnredactedLeavesTheReasonOnTheCase()
{
    Set c = ..Case(), version = c.Version, id = ..CaseRowId
    Set text = ##class(Shutter.API.CaseBundle).DownloadUnredacted(c, "approver", "  The supplier needs the record  ", .why)
    Do $$$AssertTrue(text '= "", "a file: " _ $GET(why))
    Set line = "", actor = "", ref = "", tokens = 0
    &sql(SELECT TOP 1 Text, Actor, Ref INTO :line, :actor, :ref FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND Text LIKE 'Unredacted case bundle%')
    Do $$$AssertEquals(actor, "approver", "by who took it")
    Do $$$AssertTrue(line [ "reason: The supplier needs the record", "with the reason: " _ line)
    Do $$$AssertTrue(line [ ##class(Shutter.Util.Digest).SHA256Hex(text), "and the digest of what left")
    Do $$$AssertEquals(ref, "bundle:unredacted", "marked as a download")
    Do $$$AssertEquals(..Case().Version, version, "the version does not move")
    &sql(SELECT COUNT(*) INTO :tokens FROM Shutter_Store.CaseToken WHERE "Case" = :id)
    Do $$$AssertEquals(+tokens, 0, "and no token was learnt, since nothing here goes to a model")
}

/// The ordinary route is what it was, with an unredacted file taken before it.
Method TestTheRedactedRouteStaysRedacted()
{
    Do ##class(Shutter.API.CaseBundle).DownloadUnredacted(..Case(), "approver", "The supplier needs the record", .why)
    Set text = ##class(Shutter.API.CaseBundle).Download(..Case(), "operator", .why)
    Do $$$AssertTrue($EXTRACT(text, 1, 23) = "{""redaction"":""REDACTED:", "the first line is the redacted one")
    Do $$$AssertEquals(##class(%DynamicObject).%FromJSON(text).format, "shutter-case-bundle/1", "with its format")
    Set upper = $ZCONVERT(text, "U")
    For gone = "MRN9103", "ENC-9103", "LEWIS", "FELL AT HOME", "DAUGHTER", "THE SUPPLIER" {
        Do $$$AssertNotTrue(upper [ gone, gone _ " is not in the file")
    }
    Set id = ..CaseRowId, ref = ""
    &sql(SELECT TOP 1 Ref INTO :ref FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND Text LIKE 'Case bundle%')
    Do $$$AssertEquals(ref, "bundle:redacted", "and its record is marked as a download")
}

/// A closed case's receipt names who took part in the case. Taking a file is not taking part: neither route moves it, and
/// a note from anyone else still counts.
Method TestADownloadLeavesTheReceiptAlone()
{
    Set c = ..Case()
    Set c.State = "resolved", c.Disposition = "resend", c.Outcome = "Committed", c.ClosedAt = "2026-10-15T08:23:00Z"
    Do c.%Save()
    Set before = ##class(Shutter.API.Dispatch).ClosureObject(..Case()).%ToJSON()
    Do $$$AssertTrue(##class(Shutter.API.CaseBundle).Download(..Case(), "ut-auditor", .why) '= "", "a redacted file: " _ $GET(why))
    Do $$$AssertTrue(##class(Shutter.API.CaseBundle).DownloadUnredacted(..Case(), "ut-records", "A subject access request", .why) '= "", "an unredacted file: " _ $GET(why))
    Set after = ##class(Shutter.API.Dispatch).ClosureObject(..Case()).%ToJSON()
    Do $$$AssertEquals(after, before, "the receipt is the same to the byte")
    Do ..Case().Note("note", "for the record", "ut-reader")
    Do $$$AssertTrue(##class(Shutter.API.Dispatch).ClosureObject(..Case()).actors.%ToJSON() [ "ut-reader", "and anyone else's note still counts")
}

}
