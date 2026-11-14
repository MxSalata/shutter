/// The pathology paths on the demo (1.4.6, Shutter.Scenarios.Runner): P1, a result the demo's results system refuses, and
/// P2, an outage of that receiver. They are kept out of scenarios.json; the runner knows their steps; their cases are
/// tagged and never recorded runs, so the gate's Rules only baseline cannot see them; P2's start is refused while the demo
/// results receiver's outage is open or the last run's results are still in the window, and never touches an outage; a
/// reset reads and writes nothing in the outage stores or the resend ledger; the demo results receiver's profile entry
/// passes the profile's checks and is written on a demo only; and the stand-in names the code it does not know. The test
/// puts every value it marks back, and removes only the rows it made.
Class Shutter.Test.PathologyPaths Extends %UnitTest.TestCase
{

/// The ^Shutter.Config and ^Shutter.Scenarios values the test sets, as they were: $LISTBUILD($DATA, value).
Property Saved As %String(MAXLEN = "") [ MultiDimensional ];

/// The outage rows the test made, by id.
Property Made As %String(MAXLEN = "");

/// The cases the test opened, by row id.
Property Opened As %String(MAXLEN = "");

Method OnBeforeOneTest() As %Status
{
    For key = "scenario", "scenarioRun", "scenarioBy" {
        Set ..Saved(key) = $LISTBUILD($DATA(^Shutter.Config(key)) # 10, $GET(^Shutter.Config(key)))
    }
    Set ..Saved("played") = $LISTBUILD($DATA(^Shutter.Scenarios("pathology", "played")) # 10, $GET(^Shutter.Scenarios("pathology", "played")))
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    For key = "scenario", "scenarioRun", "scenarioBy" {
        Set saved = $GET(..Saved(key))
        Continue:saved=""
        If $LIST(saved, 1) { Set ^Shutter.Config(key) = $LIST(saved, 2) } Else { Kill ^Shutter.Config(key) }
    }
    Set saved = $GET(..Saved("played"))
    If saved '= "" {
        If $LIST(saved, 1) { Set ^Shutter.Scenarios("pathology", "played") = $LIST(saved, 2) } Else { Kill ^Shutter.Scenarios("pathology", "played") }
    }
    // Only the rows this test made: an outage of a made-up receiver, or of the demo receiver while none was open
    For i = 1:1:$LENGTH(..Made, ",") {
        Set id = $PIECE(..Made, ",", i)
        Continue:id=""
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.OutageEvent WHERE OutageId = ?", id)
        If ##class(Shutter.Store.Outage).%ExistsId(id) Do ##class(Shutter.Store.Outage).%DeleteId(id)
    }
    Set ..Made = ""
    For i = 1:1:$LENGTH(..Opened, ",") {
        Set id = $PIECE(..Opened, ",", i)
        Continue:id=""
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
        Kill ^Shutter.Counter("event", id)
        If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
    Set ..Opened = ""
    Quit $$$OK
}

/// The two paths come from pathology.json, each marked as a pathology path with its files' paths filled in, and
/// scenarios.json, which the evaluation, the recordings, the fair test and the live hospital read, lists neither.
Method TestThePathsAreKeptApart()
{
    Set paths = ##class(Shutter.Scenarios.Runner).LoadPathology(.error)
    Do $$$AssertEquals(error, "", "pathology.json reads")
    Do $$$AssertEquals(paths.%Size(), 2, "two paths")
    Do $$$AssertEquals(paths.%Get(0).id _ "," _ paths.%Get(1).id, "P1,P2", "P1 and P2, in order")
    Do $$$AssertEquals(paths.%Get(0).kind, "pathology", "each is marked as a pathology path")
    Set step = paths.%Get(0).steps.%Get(0)
    Do $$$AssertEquals(step.route, "lab", "P1 plays through the results route")
    Do $$$AssertTrue(step.path [ "/P1/", "with its file's path filled in: " _ step.path)
    Set scenarios = ##class(Shutter.Scenarios.Runner).Load(.error)
    Set ids = "", iter = scenarios.%GetIterator()
    While iter.%GetNext(, .s) { Set ids = ids _ "," _ s.id }
    Do $$$AssertNotTrue((ids _ ",") [ ",P1,", "scenarios.json does not list P1")
    Do $$$AssertNotTrue((ids _ ",") [ ",P2,", "scenarios.json does not list P2")
    Do $$$AssertTrue(##class(Shutter.Scenarios.Runner).WaitsForOutage(paths.%Get(1)), "P2 waits for an outage")
    Do $$$AssertNotTrue(##class(Shutter.Scenarios.Runner).WaitsForOutage(paths.%Get(0)), "P1 does not")
}

/// The runner says each new step in words, and counts its time.
Method TestTheRunnerKnowsTheSteps()
{
    Set r = "Shutter.Scenarios.Runner"
    Do $$$AssertEquals($CLASSMETHOD(r, "Describe", {"file": "x.hl7", "route": "lab"}), "delivering x.hl7 to the demo results system")
    Do $$$AssertEquals($CLASSMETHOD(r, "Describe", {"lab_receiver": "down"}), "taking the demo results system down")
    Do $$$AssertEquals($CLASSMETHOD(r, "Describe", {"lab_receiver": "up"}), "bringing the demo results system back")
    Do $$$AssertEquals($CLASSMETHOD(r, "Describe", {"wait_for_outage": "offered", "receiver": "Lab Results Out"}), "waiting for the outage of Lab Results Out to reach offered")
    Set p2 = $CLASSMETHOD(r, "FindPathology", "P2")
    // three files at 2 s, a 20 s wait, two switches at 5 s and the outage's 240 s
    Do $$$AssertEquals($CLASSMETHOD(r, "Duration", p2), 6 + 20 + 10 + 240, "P2's longest time")
}

/// A pathology path's cases are tagged with it and are never recorded runs: the gate's Rules only baseline reads
/// ScenarioRecorded, so it cannot see them. A scenario's run is recorded, as before.
Method TestAPathsCaseIsNeverARecordedRun()
{
    Do ##class(Shutter.Scenarios.Runner).Tag("P1", 1)
    Do $$$AssertEquals($GET(^Shutter.Config("scenario")), "P1", "the case's tag")
    Do $$$AssertNotTrue($DATA(^Shutter.Config("scenarioRun")), "no recorded run")
    Do $$$AssertStatusOK(..OpenOne(1, .case), "a case while P1 plays")
    Do $$$AssertEquals(case.Scenario, "P1", "the case is tagged")
    Do $$$AssertNotTrue(case.ScenarioRecorded, "and is not a recorded run")
    Do ##class(Shutter.Scenarios.Runner).Tag("S8", 0)
    Do $$$AssertEquals($GET(^Shutter.Config("scenarioRun")), "S8", "a scenario's run is recorded")
}

/// P2's start is refused while the demo results receiver has an outage that is not closed (in words that say where to
/// finish it, and while it sends, to wait), and never because of another receiver's outage; P1 is never refused for it.
/// The refusal reads the outage and changes nothing on it. The receiver here is a made-up one the watch never polls, so no
/// poll can move the rows while the test reads them.
Method TestP2WaitsForTheLastOutage()
{
    Set r = "Shutter.Scenarios.Runner", receiver = "UT Pathology Lab " _ $JOB
    Kill ^Shutter.Scenarios("pathology", "played")
    Set p1 = $CLASSMETHOD(r, "FindPathology", "P1"), p2 = $CLASSMETHOD(r, "FindPathology", "P2")
    Do $$$AssertEquals($CLASSMETHOD(r, "PathologyRefusal", p2, receiver), "", "no outage open: P2 may start")
    Set other = ..MakeOutage("UT Pathology Other " _ $JOB, "offered")
    Do $$$AssertEquals($CLASSMETHOD(r, "PathologyRefusal", p2, receiver), "", "another receiver's outage does not hold P2")
    Set own = ..MakeOutage(receiver, "offered")
    Set before = ..Fingerprint(own)
    Set words = $CLASSMETHOD(r, "PathologyRefusal", p2, receiver)
    Do $$$AssertTrue(words [ "is still open on the Incidents page", "P2 is refused while the last run's outage is offered: " _ words)
    Do $$$AssertTrue(words [ "close it there with a reason", "and the words say where to finish it")
    Do $$$AssertEquals($CLASSMETHOD(r, "PathologyRefusal", p1, receiver), "", "P1 is not refused for it")
    Do $$$AssertEquals(..Fingerprint(own), before, "the refusal changed nothing on the outage")
    Set row = ##class(Shutter.Store.Outage).%OpenId(own), row.State = "sending"
    Do $$$AssertStatusOK(row.%Save())
    Set words = $CLASSMETHOD(r, "PathologyRefusal", p2, receiver)
    Do $$$AssertTrue(words [ "is still sending its approved resend", "while it sends, P2 waits: " _ words)
    Set row = ##class(Shutter.Store.Outage).%OpenId(own), row.State = "closed", row.ActiveReceiver = ""
    Do $$$AssertStatusOK(row.%Save())
    Do $$$AssertEquals($CLASSMETHOD(r, "PathologyRefusal", p2, receiver), "", "once closed, P2 may start again")
    Do $$$AssertEquals($PARAMETER(r, "LABRECEIVER"), "Lab Results Out", "the receiver P2 is held by on the demo is its results receiver")
}

/// P2's start is refused while the last P2 run's results are inside the next outage's window, with how long to wait.
Method TestP2WaitsForTheWindow()
{
    Set r = "Shutter.Scenarios.Runner", receiver = "UT Pathology Lab " _ $JOB
    Set p2 = $CLASSMETHOD(r, "FindPathology", "P2")
    Set ^Shutter.Scenarios("pathology", "played") = ##class(Shutter.Util.Time).NowUTC()
    Set words = $CLASSMETHOD(r, "PathologyRefusal", p2, receiver)
    Do $$$AssertTrue(words [ "still inside the outage window for", "refused inside the window: " _ words)
    Set ^Shutter.Scenarios("pathology", "played") = "2026-01-01T00:00:00Z"
    Do $$$AssertEquals($CLASSMETHOD(r, "PathologyRefusal", p2, receiver), "", "long after it, P2 may start")
}

/// A reset reads and writes nothing in the outage stores or the resend ledger: every row's count, and an open outage's
/// state, version and digest, are as they were.
Method TestAResetLeavesTheOutagesAlone()
{
    Set own = ..MakeOutage("UT Pathology Reset " _ $JOB, "offered")
    Set counts = ..Counts(), before = ..Fingerprint(own)
    Set answer = ""
    Try {
        Set answer = ##class(%DynamicObject).%FromJSON(##class(Shutter.Scenarios.Runner).Reset())
    } Catch ex {
        Do $$$AssertTrue(0, "Reset threw: " _ ex.DisplayString())
    }
    Do $$$AssertTrue($ISOBJECT(answer) && (answer.%Get("lab") '= ""), "the reset says what it did with the results system's stand-in: " _ $SELECT($ISOBJECT(answer): answer.%Get("lab"), 1: ""))
    Do $$$AssertEquals(..Counts(), counts, "no outage, event, reading or ledger row was added or removed")
    Do $$$AssertEquals(..Fingerprint(own), before, "the open outage's state, version and digest are as they were")
}

/// The demo results receiver's entry passes the profile's own checks beside the stored receivers, and a site install gets
/// nothing: DemoLabReceiver writes no version there. On a demo whose profile already has it, a second run writes none.
Method TestTheProfileEntry()
{
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set list = p.%Get("receivers"), kept = []
    Set iter = list.%GetIterator()
    While iter.%GetNext(, .one) { Do:##class(Shutter.Util.Json).Str(one, "name")'="Lab Results Out" kept.%Push(one) }
    Set entry = ##class(Shutter.Setup).DemoLabEntry("HOSPITAL")
    Do kept.%Push(entry)
    Do p.%Set("receivers", kept)
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "the entry passes the profile's checks")
    Do $$$AssertEquals(entry.category, "orders_results", "orders and results")
    Do $$$AssertEquals(entry."ack_level", "commit", "a Completed header proves no more than the stand-in's commit")
    Do $$$AssertEquals(entry.duplicates.behaviour, "unknown", "so the approval asks for the receiver check")
    Do $$$AssertTrue(entry."engine_resend", "an outage's messages may go again")
    Set row = ##class(Shutter.Store.SiteProfile).Row(), version = $SELECT($ISOBJECT(row): row.Version, 1: "")
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoLabReceiver("HOSPITAL", 0), "a site install")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Do $$$AssertEquals($SELECT($ISOBJECT(row): row.Version, 1: ""), version, "a site install gets no new version")
    Set names = ##class(Shutter.Store.SiteProfile).ReceiverNames().%ToJSON()
    If $GET(^Shutter.Config("demo")) && (names [ """Lab Results Out""") {
        Do $$$AssertStatusOK(##class(Shutter.Setup).DemoLabReceiver("HOSPITAL", 1), "a second run on the demo")
        Set row = ##class(Shutter.Store.SiteProfile).Row()
        Do $$$AssertEquals(row.Version, version, "an entry already there changes nothing")
    }
}

/// The stand-in answers AE naming the first code it does not know, and AA otherwise; the feed's stamp changes only the
/// control id, the time, the patient's first identifier and the order numbers.
Method TestTheStandInAndTheStamp()
{
    Set dir = ##class(Shutter.Scenarios.Runner).FixturesDir()
    Set refused = ..Doc(dir _ "P1/result-unknown-test-code.hl7"), known = ..Doc(dir _ "P2/result-1.hl7")
    Do $$$AssertEquals(##class(Hospital.Service.LabReceiver).UnknownCode(refused), "ZZUNK", "P1's result names a code the stand-in does not know")
    Do $$$AssertEquals(##class(Hospital.Service.LabReceiver).UnknownCode(known), "", "P2's results name only codes it knows")
    Set text = ..Text(dir _ "P2/result-1.hl7")
    Set out = ##class(Hospital.Service.LabFeed).Stamped(text, 7, .control)
    Set cr = $CHAR(13)
    Do $$$AssertEquals($LENGTH(out, cr), $LENGTH(text, cr), "the same segments")
    Do $$$AssertEquals($PIECE($PIECE(out, cr, 1), "|", 10), control, "MSH-10 is the fresh control id")
    Do $$$AssertNotEquals(control, $PIECE($PIECE(text, cr, 1), "|", 10), "which is not the fixture's")
    Set pid = $PIECE(out, cr, 2)
    Do $$$AssertEquals($EXTRACT($PIECE($PIECE(pid, "|", 4), "^", 1), 1, 3), "999", "a patient in the test range")
    Do $$$AssertEquals($PIECE($PIECE(pid, "|", 4), "^", 2, *), $PIECE($PIECE($PIECE(text, cr, 2), "|", 4), "^", 2, *), "with the same authority")
    For i = 5:1:$LENGTH(text, cr) {
        Do $$$AssertEquals($PIECE(out, cr, i), $PIECE(text, cr, i), "segment " _ i _ " unchanged")
    }
}

/// An outage row of this test's own, as the watch would open it, in <var>state</var>. Returns its id.
Method MakeOutage(receiver As %String, state As %String) As %String
{
    Set row = ##class(Shutter.Store.Outage).%New()
    Set row.Receiver = receiver, row.ActiveReceiver = receiver, row.State = state, row.Kind = "down"
    Set row.OpenedAt = ##class(Shutter.Util.Time).NowUTC(), row.SetDigest = "ut-" _ $JOB, row.SetStatus = "computed"
    Set sc = row.%Save()
    Do $$$AssertStatusOK(sc, "the test's own outage of " _ receiver)
    Set id = row.%Id(), ..Made = ..Made _ "," _ id
    Quit id
}

/// An outage's state, version, digest and event count, as one string.
ClassMethod Fingerprint(id As %String) As %String
{
    Set row = ##class(Shutter.Store.Outage).%OpenId(id)
    Quit:'$ISOBJECT(row) "gone"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Shutter_Store.OutageEvent WHERE OutageId = ?", id)
    Do rs.%Next()
    Quit row.State _ "|" _ row.Version _ "|" _ row.SetDigest _ "|" _ rs.%Get("N")
}

/// The four stores' row counts, as one string.
ClassMethod Counts() As %String
{
    Set out = ""
    For table = "Outage", "OutageEvent", "ReceiverReading", "ResendRecord" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Shutter_Store." _ table)
        Do rs.%Next()
        Set out = out _ table _ "=" _ rs.%Get("N") _ ";"
    }
    Quit out
}

/// Opens a case for an operation of this test's own, as the feed does.
Method OpenOne(n As %Integer, Output case As Shutter.Store.Case) As %Status
{
    Set enc = "ENC-UTPP" _ n _ "-" _ $JOB, mrn = "MRN-UTPP" _ n
    Set op = {"operation_key": ("PAS^HOSP^" _ mrn _ "^" _ enc _ "^admit^2026-11-14T01:00:0" _ n _ "Z"), "encounter_id": (enc), "patient_id": (mrn), "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "bed": null, "event_time": ("2026-11-14T01:00:0" _ n _ "Z"), "source_system": "PAS", "source_message_id": ("UTPP" _ n), "payload_digest": ("sha256:utpp" _ n)}
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "Delivery unavailable (test)", "", "", "board", .case, .opened)
    If $$$ISOK(sc) && $ISOBJECT(case) Set ..Opened = ..Opened _ "," _ case.%Id()
    Quit sc
}

ClassMethod Text(path As %String) As %String
{
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(path)
    Set text = ""
    While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    Quit text
}

ClassMethod Doc(path As %String) As EnsLib.HL7.Message
{
    Quit ##class(EnsLib.HL7.Message).ImportFromString(..Text(path))
}

}
