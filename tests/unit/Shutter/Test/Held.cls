/// "Prevent failures" (v1.34; CONTRACTS 6.4, 11 and 12): the profile setting and its validator, the schema category a message
/// is read under, the canonical 2.5.1 reading for a held case's identity, the forward a refused message gets, a held case's
/// headline and its place in the held report, the matcher's word for it before and after the schema is loaded, and the
/// release once the schema is there, which clears the field.
Class Shutter.Test.Held Extends %UnitTest.TestCase
{

Parameter KEY = "PAS^HOSP^MRN-UT9^ENC-UT9^admit^2026-11-01T10:00:00Z";

Parameter RELEASEDKEY = "PAS^HOSP^MRN-UT9^ENC-UT9^transfer^2026-11-01T11:00:00Z";

Property CaseRowId As %String;

Property ReleasedRowId As %String;

Method OnAfterAllTests() As %Status
{
    If ..CaseRowId '= "" Do ..Purge(..CaseRowId)
    If ..ReleasedRowId '= "" Do ..Purge(..ReleasedRowId)
    Quit $$$OK
}

ClassMethod Purge(id As %String)
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
    Kill ^Shutter.Counter("event", id)
    If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
}

/// The S1 admission's text with MSH-12 set to the version given; "" when the fixtures are not on this instance.
ClassMethod Fixture(version As %String = "2.5.1") As %String
{
    Set path = $GET(^Shutter.Config("root")) _ "fixtures/S1/S1-01-A01.hl7"
    Set stream = ##class(%Stream.FileCharacter).%New()
    If $$$ISERR(stream.LinkToFile(path)) Quit ""
    Set text = ""
    While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    Set text = $REPLACE(text, $CHAR(13, 10), $CHAR(13))
    If '(text [ $CHAR(13)) Set text = $TRANSLATE(text, $CHAR(10), $CHAR(13))
    Set msh = $PIECE(text, $CHAR(13), 1)
    // MSH-1 is the field separator itself, so MSH-12 is the twelfth piece after "MSH".
    Set $PIECE(msh, "|", 12) = version
    Quit msh _ $CHAR(13) _ $PIECE(text, $CHAR(13), 2, *)
}

ClassMethod Message(version As %String = "2.5.1") As EnsLib.HL7.Message
{
    Set text = ..Fixture(version)
    If text = "" Quit ""
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    If $$$ISERR(sc) Quit ""
    Quit msg
}

Method TestProfileSetting()
{
    Set sp = "Shutter.Store.SiteProfile"
    Set p = $CLASSMETHOD(sp, "Default")
    Do $$$AssertEquals(p.feed.%Get("prevent_failures"), 0, "the shipped default is off")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "", "and validates")
    Do p.feed.%Set("prevent_failures", 1, "boolean")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "", "true validates")
    Set p.feed."prevent_failures" = "yes"
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "feed.prevent_failures: must be true or false", "a word is refused")
    Do p.feed.%Remove("prevent_failures")
    Set p.feed."hold_invalid" = 1
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "feed.hold_invalid: unknown setting", "an unknown feed setting is refused")
    // The cached read agrees with the stored profile.
    Kill ^Shutter.Config("preventFailures")
    Set feed = $CLASSMETHOD(sp, "Current").%Get("feed")
    Set expected = $ISOBJECT(feed) && (feed.%GetTypeOf("prevent_failures") = "boolean") && feed.%Get("prevent_failures")
    Do $$$AssertEquals($CLASSMETHOD(sp, "PreventFailures"), ''expected, "PreventFailures reads the stored profile")
    Do $$$AssertEquals($GET(^Shutter.Config("preventFailures")), ''expected, "and caches it")
}

Method TestCategoryAndCanonical()
{
    Set msg = ..Message("2.5.1")
    If '$ISOBJECT(msg) { Do $$$AssertTrue(1, "the fixtures are not on this instance (no root); nothing to read") Quit }
    Set schemas = "Shutter.Util.Schemas"
    Do $$$AssertEquals(msg.DocType, "", "a message imported from text has no document type")
    Do $$$AssertEquals($CLASSMETHOD(schemas, "CategoryOf", msg), "2.5.1", "its category is MSH-12 then")
    Do $$$AssertTrue($CLASSMETHOD(schemas, "Known", "2.5.1"), "2.5.1 is loaded here")
    Do $$$AssertTrue($CLASSMETHOD(schemas, "KnownIn", "", "2.5.1") && $CLASSMETHOD(schemas, "KnownIn", $NAMESPACE, "2.5.1"), "and in this namespace by name")
    Do $$$AssertNotTrue($CLASSMETHOD(schemas, "KnownIn", "NO_SUCH_NAMESPACE_UT", "2.5.1"), "a namespace that is not there knows nothing")
    Set site = ..Message("MYSITE_2.5.1")
    Do $$$AssertEquals($CLASSMETHOD(schemas, "CategoryOf", site), "MYSITE_2.5.1", "a site's category from MSH-12")
    Do $$$AssertNotTrue($CLASSMETHOD(schemas, "Known", "MYSITE_2.5.1"), "which is not loaded")
    Do $$$AssertEquals($CLASSMETHOD(schemas, "CategoryOf", site, "ADT In"), "2.5.1", "the receiving item's own category outranks MSH-12 when the message is untyped")
    Do $$$AssertEquals($CLASSMETHOD(schemas, "CategoryOf", site, "No Such Item UT"), "MYSITE_2.5.1", "an item that is not there leaves MSH-12 to say")
    Set copy = $CLASSMETHOD(schemas, "Canonical", site)
    Do $$$AssertTrue($ISOBJECT(copy) && (copy.DocType = "2.5.1:ADT_A01"), "the canonical reading is the 2.5.1 admission: " _ $SELECT($ISOBJECT(copy): copy.DocType, 1: "none"))
    Do $$$AssertEquals(copy.%Id(), "", "and is never saved")
    Set op = ##class(Shutter.Util.OperationKey).FromCanonical(site, "0", .sc)
    Do $$$AssertStatusOK(sc, "the held message maps through the canonical reading")
    Do $$$AssertEquals($PIECE(op."operation_key", "^", 1, 5), "PAS^HOSP^MRN1001^ENC-1001^admit", "to the fixture's operation: " _ op."operation_key")
    Do $$$AssertEquals(op."patient_id", "MRN1001", "with its patient")
    // The cache of known categories follows an epoch that a change moves, so other jobs see an import.
    Do $CLASSMETHOD(schemas, "Changed")
    Do $$$AssertEquals($DATA(^||Shutter.SchemaKnown), 0, "a change empties the process's cache")
    Do $$$AssertTrue($CLASSMETHOD(schemas, "Known", "2.5.1"), "known again")
    Do $$$AssertEquals($GET(^||Shutter.SchemaKnown), $GET(^Shutter.Config("schemaEpoch")), "and the cache carries the epoch")
}

Method TestForwardForARefusedMessage()
{
    Set site = ..Message("MYSITE_2.5.1")
    If '$ISOBJECT(site) { Do $$$AssertTrue(1, "the fixtures are not on this instance; nothing to forward") Quit }
    Set header = ##class(Ens.MessageHeader).%New()
    Set header.SourceConfigName = "PAS In"
    Set f = ##class(Shutter.Intake.Forwarder).ForwardFor(site, header, "Downstream Out")
    Do $$$AssertEquals(f.FailureKind _ "|" _ f.FailureReasonCode _ "|" _ f.Route _ "|" _ f.Receiver, "unreadable|schema_unknown|PAS In|Downstream Out", "a message of a schema not loaded here is held: " _ f.FailureText)
    Do $$$AssertTrue(($EXTRACT(f.FailureText, 1, 5) = "Held:") && (f.FailureText [ "MYSITE_2.5.1") && (f.FailureText [ $NAMESPACE), "the text names the hold, the category and the namespace")
    Set f = ##class(Shutter.Intake.Forwarder).ForwardFor(..Message("2.5.1"), header)
    Do $$$AssertEquals(f.FailureKind _ "|" _ f.FailureReasonCode _ "|" _ f.Receiver, "unreadable|invalid_message|", "a message of a loaded schema that the service refused is invalid, bound for the default receiver: " _ f.FailureText)
}

Method TestHeldCaseAndMatcher()
{
    Set op = {"operation_key": (..#KEY), "encounter_id": "ENC-UT9", "patient_id": "MRN-UT9", "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "bed": null, "event_time": "2026-11-01T10:00:00Z", "source_system": "PAS", "source_message_id": "UT9", "payload_digest": "sha256:ut9"}
    Set text = "Held: the schema MYSITE_2.5.1 is not loaded here; import it and set the inbound item's category, and the case is released"
    Set sc = ##class(Shutter.Store.Case).Open(op, "unreadable", text, "", "", "policy", .case, .opened, "", "MYSITE_2.5.1")
    Do $$$AssertStatusOK(sc, "a held case opens")
    Set ..CaseRowId = case.%Id()
    Do $$$AssertTrue(opened && (case.FailureKind = "unreadable") && (case.HeldSchema = "MYSITE_2.5.1"), "with its kind and the schema it waits for")
    Do $$$AssertEquals(case.Headline, text, "its headline is the hold")
    Set held = ##class(Shutter.Util.Schemas).Held()
    Set found = 0, hi = held.categories.%GetIterator()
    While hi.%GetNext(, .c) { If (c.category = "MYSITE_2.5.1") && (c.namespace = $NAMESPACE) && (c.count >= 1) Set found = 1 }
    Do $$$AssertTrue((held.count >= 1) && found, "the held report counts it under its category: " _ held.%ToJSON())
    // The matcher: unreadable, with no answer from a receiver, before and after the schema is loaded (the catalogue decides).
    Set summary = {"failure": {"kind": "unreadable", "reason_code": "schema_unknown"}, "validation": {"schema_known": false}}
    Set c = ##class(Shutter.Catalogue.Matcher).Conditions(case, summary)
    Do $$$AssertEquals(c.delivery _ "|" _ c."receiver_answer", "unreadable|none", "unreadable, with no answer from a receiver: the reason code is the feed's, not a refusal")
    Set case.HeldSchema = "2.5.1"
    Set c = ##class(Shutter.Catalogue.Matcher).Conditions(case, {"failure": {"kind": "unreadable"}, "validation": {"schema_known": true}})
    Do $$$AssertEquals(c.delivery, "unreadable", "the word stays once the schema is loaded; the entry for a held message proposes the resend")
    // The release check leaves a case alone while its schema is still missing.
    Set case.HeldSchema = "MYSITE_2.5.1", case.State = "blocked"
    Do $$$AssertStatusOK(case.%Save(), "saved as blocked")
    Do $$$AssertEquals(##class(Shutter.Util.Schemas).ReleaseHeld(), 0, "nothing is released while the schema is still missing")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ReleaseHeld("", "x", "y"), 0, "no case id, nothing released")
}

/// The release of a held case (what the sweep does once the schema is known): one reinvestigation goes from the host to
/// the Case Workflow, and the case's HeldSchema is an empty property afterwards, not SQL's empty string ($CHAR(0)), so the
/// case read again, its JSON and every reader testing HeldSchema '= "" see it released.
Method TestReleaseClearsTheHeldSchema()
{
    Set op = {"operation_key": (..#RELEASEDKEY), "encounter_id": "ENC-UT9", "patient_id": "MRN-UT9", "patient_id_authority": "HOSP", "event": "transfer", "ward": "WARD-B", "bed": null, "event_time": "2026-11-01T11:00:00Z", "source_system": "PAS", "source_message_id": "UT9T", "payload_digest": "sha256:ut9t"}
    Set sc = ##class(Shutter.Store.Case).Open(op, "unreadable", "Held: the schema MYSITE_2.5.1 is not loaded here", "", "", "policy", .case, .opened, "", "MYSITE_2.5.1")
    Do $$$AssertStatusOK(sc, "a held case opens")
    Set ..ReleasedRowId = case.%Id()
    Set case.State = "blocked"
    Do $$$AssertStatusOK(case.%Save(), "saved as blocked")
    Set host = ##class(Shutter.Test.FakeReleaser).%New("Case Releaser (unit test)")
    Do $$$AssertTrue($ISOBJECT(host), "a stand-in for the Case Releaser")
    Set n = ##class(Shutter.Store.Case).ReleaseHeld(case.CaseId, "MYSITE_2.5.1", $NAMESPACE, host)
    Do $$$AssertEquals(n, 1, "the one blocked case held for the schema is released")
    Do $$$AssertEquals(host.Sent.Count(), 1, "one reinvestigation went from the host")
    Set sent = host.Sent.GetAt(1)
    Do $$$AssertTrue(($PIECE(sent, "|", 1) = "Case Workflow") && ($PIECE(sent, "|", 2) = case.CaseId) && (sent [ "MYSITE_2.5.1") && (sent [ $NAMESPACE), "to the Case Workflow, for this case, with the reason: " _ sent)
    Do $$$AssertStatusOK(case.%Reload(), "the case read again")
    Do $$$AssertTrue((case.HeldSchema = "") && ($LENGTH(case.HeldSchema) = 0), "holds no schema any more (" _ $LENGTH(case.HeldSchema) _ " characters)")
    Do $$$AssertStatusOK(case.%JSONExportToString(.json), "and exports")
    Do $$$AssertNotTrue(json [ "\u0000", "with no control character for the schema")
    Do $$$AssertTrue(('(json [ """heldSchema""")) || (json [ """heldSchema"":"""""), "heldSchema absent or empty")
    // Released once: the sweep's candidates (Shutter.Operation.Releaser.Candidates and Schemas.ReleaseHeld read the same
    // predicate) no longer count the case, which stays blocked until the Case Workflow takes the reinvestigation.
    Set caseId = case.CaseId, held = -1
    &sql(SELECT COUNT(*) INTO :held FROM Shutter_Store."Case" WHERE CaseId = :caseId AND FailureKind = 'unreadable' AND HeldSchema <> '' AND State IN ('blocked', 'escalated'))
    Do $$$AssertEquals(held, 0, "and the sweep no longer counts it as held (SQLCODE " _ SQLCODE _ ")")
}

}
