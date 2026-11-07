/// Shadow mode and the recovery stop (CONTRACTS 17): the admission at the connector's last line, counted at its adapter; the
/// race with a stop; a stop and an unanswered call across a lost job; what a clear does not release; the ordinary feed; the
/// email; the seed; the report. Each test puts back the profile and the control row as it found them.
Class Shutter.Test.RecoveryControl Extends %UnitTest.TestCase
{

Property SavedProfile As %String(MAXLEN = "");

Property HadProfile As %Boolean;

Property SavedDemo As %String;

/// The control row's fields, and the newest permit before the test.
Property SavedControl As %String(MAXLEN = "");

Property PermitsFrom As %Integer;

/// The stored profile's version, and the newest row of its history, before the test.
Property SavedVersion As %Integer;

Property HistoryFrom As %Integer;

Property SavedSource As %String(MAXLEN = 500);

Parameter CASEA = "C-TEST-RECCTL-A";

Parameter FEEDITEM = "UT Recovery Feed";

Method OnBeforeOneTest() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadProfile = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..SavedVersion = $SELECT($ISOBJECT(row): row.Version, 1: 0), ..SavedSource = $SELECT($ISOBJECT(row): row.Source, 1: "")
    Set newest = ""
    &sql(SELECT MAX(ID) INTO :newest FROM Shutter_Store.SiteProfileVersion)
    Set ..HistoryFrom = +$GET(newest)
    Set ..SavedDemo = $GET(^Shutter.Config("demo"), "unset")
    Do ##class(Shutter.Util.RecoveryControl).Ensure()
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set ..SavedControl = $LISTBUILD(c.StopLatched, c.StoppedAt, c.StoppedBy, c.StopReason)
    Set c.StopLatched = 0, c.StoppedAt = "", c.StoppedBy = "", c.StopReason = ""
    Do c.%Save()
    Set last = ""
    &sql(SELECT MAX(ID) INTO :last FROM Shutter_Store.DispatchPermit)
    Set ..PermitsFrom = +$GET(last)
    Do ##class(Shutter.Test.CountingAdapter).Clear()
    Do ##class(Shutter.Test.CountingAdapter).Answer()
    Set ^Ens.Runtime("ConfigItem", ..#FEEDITEM, "ClassName") = "Shutter.Process.ADTToWard"
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Kill ^Ens.Runtime("ConfigItem", ..#FEEDITEM)
    Do ##class(Shutter.Test.NoAnswer).Drop(..#CASEA)
    Do ##class(Shutter.Test.CountingAdapter).Clear()
    Set from = ..PermitsFrom
    &sql(DELETE FROM Shutter_Store.DispatchPermit WHERE ID > :from)
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set c.StopLatched = $LIST(..SavedControl, 1), c.StoppedAt = $LIST(..SavedControl, 2), c.StoppedBy = $LIST(..SavedControl, 3), c.StopReason = $LIST(..SavedControl, 4)
    Do c.%Save()
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set history = ..HistoryFrom
    &sql(DELETE FROM Shutter_Store.SiteProfileVersion WHERE ID > :history)
    If ..HadProfile { Set row.Json = ..SavedProfile, row.Version = ..SavedVersion, row.Source = ..SavedSource Do row.%Save() } ElseIf $ISOBJECT(row) { Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id()) }
    If ..SavedDemo = "unset" { Kill ^Shutter.Config("demo") } Else { Set ^Shutter.Config("demo") = ..SavedDemo }
    Quit $$$OK
}

// ---- helpers ----

/// The profile's mode, stored through the store, as a person's save would: "" takes the field away.
Method SetMode(mode As %String)
{
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Do p.%Remove("version")
    If mode = "" { Do p.%Remove("recovery") } Else { Do p.%Set("recovery", {"mode": (mode)}) }
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "unit test", "unit test"), "the profile is stored, mode [" _ mode _ "]")
}

/// A saved case with a current resend plan, made now.
Method PlannedCase(Output plan As Shutter.Store.Plan) As Shutter.Store.Case
{
    Do ##class(Shutter.Test.NoAnswer).Drop(..#CASEA)
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEA, c.Receiver = "Downstream Out", c.OperationKey = "PAS^HOSP^MRN9005^ENC-9005^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.Ward = "WARD-B", c.EventTime = "2026-10-15T08:20:00Z", c.EncounterId = "ENC-9005", c.PatientId = "MRN9005"
    Set c.FailureKind = "delivery_failed", c.FailureText = "x", c.State = "executing", c.Headline = "The transfer was not delivered"
    Set c.OpenedAt = ##class(Shutter.Util.Time).NowUTC(), c.UpdatedAt = c.OpenedAt
    Do $$$AssertStatusOK(c.%Save(), "the case is saved")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Do $$$AssertStatusOK(snap.%Save(), "its snapshot")
    Set action = {"type": "resend", "operation_key": (c.OperationKey), "expected_version": 1}
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(c, snap, {"disposition": "resend", "summary": "resend", "action": (action)}, "rules", .plan), "its plan")
    Set c = ##class(Shutter.Store.Case).ByCaseId(..#CASEA)
    Set c.CurrentPlan = plan
    Do $$$AssertStatusOK(c.%Save(), "the plan is current")
    Quit c
}

/// A write of the planned case, as the workflow builds it.
ClassMethod Write(caseId As %String = "") As Shutter.Msg.WardOperation
{
    Set w = ##class(Shutter.Test.ShadowWire).Operation("recovery")
    Set w.CaseId = caseId
    Quit w
}

/// One call through the connector with the counting adapter, the sender's item named.
Method Send(request As Shutter.Msg.WardOperation, Output result As Shutter.Msg.WardResult, source As %String = "")
{
    Set op = ##class(Shutter.Test.ShadowWire).Connector()
    If source '= "" {
        Set header = ##class(Ens.MessageHeader).%New()
        Set header.SourceConfigName = source
        Set op.%RequestHeader = header
    }
    Do $$$AssertStatusOK(op.OnWardOperation(request, .result), "the connector ran")
}

ClassMethod Posts() As %Integer
{
    Quit ##class(Shutter.Test.CountingAdapter).Count("POST")
}

/// The permits this test made, newest first in the array.
Method Permits(state As %String = "") As %DynamicArray
{
    Set out = [], from = ..PermitsFrom
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, State, Orphaned, Generation FROM Shutter_Store.DispatchPermit WHERE ID > ? ORDER BY ID DESC", from)
    While rs.%Next() {
        Continue:(state'="")&&(rs.%Get("State")'=state)
        Do out.%Push({"id": (rs.%Get("ID")), "state": (rs.%Get("State")), "orphaned": (rs.%Get("Orphaned")), "generation": (rs.%Get("Generation"))})
    }
    Quit out
}

/// The control row's stored data damaged, as RepairControl puts it back.
ClassMethod DamageControl()
{
    Do ##class(Shutter.Store.RecoveryControl).NameIdxExists("current", .id)
    Set location = ##class(%Dictionary.CompiledStorage).%OpenId("Shutter.Store.RecoveryControl||Default").DataLocation
    Set ^Shutter.TestWire("control") = @location@(id)
    Set @location@(id) = $LISTBUILD("", "current")
}

ClassMethod RepairControl()
{
    Do ##class(Shutter.Store.RecoveryControl).NameIdxExists("current", .id)
    Set location = ##class(%Dictionary.CompiledStorage).%OpenId("Shutter.Store.RecoveryControl||Default").DataLocation
    Set @location@(id) = ^Shutter.TestWire("control")
}

// ---- jobs: a process of its own, for a lock that really is someone else's ----

/// Admit a call and end, with no answer: what a restart does to a call in progress.
ClassMethod JobAdmitAndEnd(caseId As %String, flag As %String)
{
    Do ##class(Shutter.Util.RecoveryControl).Admit("rehearsal", caseId, "Downstream Out", "K", "D", .permit, .code, .text)
    Set ^Shutter.TestWire("job", flag) = $SELECT($ISOBJECT(permit): permit.%Id(), 1: "refused:" _ code)
}

/// Ask for an admission and report what it said: it waits on the lock if someone holds it.
ClassMethod JobAdmit(flag As %String)
{
    Set ^Shutter.TestWire("job", flag, "started") = 1
    Set ok = ##class(Shutter.Util.RecoveryControl).Admit("rehearsal", "", "Downstream Out", "K", "D", .permit, .code, .text)
    Set ^Shutter.TestWire("job", flag) = $SELECT(ok: "admitted", 1: "refused:" _ code)
    If ok Do ##class(Shutter.Util.RecoveryControl).Finish(permit, ##class(Shutter.Msg.WardResult).%New())
}

/// Admit and finish until the flag falls, counting.
ClassMethod JobHammer(flag As %String)
{
    Set result = ##class(Shutter.Msg.WardResult).%New()
    Set result.Outcome = "would_apply"
    While '$GET(^Shutter.TestWire("stop", flag)) {
        If ##class(Shutter.Util.RecoveryControl).Admit("rehearsal", "", "Downstream Out", "K", "D", .permit, .code, .text) {
            Do ##class(Shutter.Util.RecoveryControl).Finish(permit, result)
            If $INCREMENT(^Shutter.TestWire("hammer", "admitted"))
        } Else {
            If $INCREMENT(^Shutter.TestWire("hammer", "refused"))
        }
    }
    If $INCREMENT(^Shutter.TestWire("hammer", "done"))
}

/// Hold the control's lock for a moment, as a stop in progress would.
ClassMethod JobHoldLock(flag As %String, seconds As %Integer)
{
    LOCK +^Shutter.RecoveryControl
    Set ^Shutter.TestWire("job", flag) = "held"
    Hang seconds
    LOCK -^Shutter.RecoveryControl
}

Method WaitFor(ref As %String, seconds As %Integer = 20) As %Boolean
{
    For i = 1:1:(seconds * 10) {
        If $DATA(@ref) Quit
        Hang 0.1
    }
    Quit ''$DATA(@ref)
}

// ---- modes ----

/// Anything but an explicit enabled is shadow, and the validator refuses what isn't one of the two.
Method TestTheModeIsShadowUnlessEnabled()
{
    Set rc = "Shutter.Util.RecoveryControl", sp = "Shutter.Store.SiteProfile"
    Do $$$AssertEquals($CLASSMETHOD(rc, "ModeOfProfile", $CLASSMETHOD(sp, "Default")), "shadow", "the shipped defaults")
    Do $$$AssertEquals($CLASSMETHOD(rc, "ModeOfJson", ""), "shadow", "no profile")
    Do $$$AssertEquals($CLASSMETHOD(rc, "ModeOfJson", "not json"), "shadow", "an unreadable profile")
    Do $$$AssertEquals($CLASSMETHOD(rc, "ModeOfJson", "{""recovery"":{}}"), "shadow", "no mode")
    Do $$$AssertEquals($CLASSMETHOD(rc, "ModeOfJson", "{""recovery"":{""mode"":""ENABLED""}}"), "shadow", "an invalid mode")
    Do $$$AssertEquals($CLASSMETHOD(rc, "ModeOfJson", "{""recovery"":""enabled""}"), "shadow", "a mode in the wrong place")
    Do $$$AssertEquals($CLASSMETHOD(rc, "ModeOfJson", "{""recovery"":{""mode"":""enabled""}}"), "enabled", "enabled, explicitly")
    Set p = $CLASSMETHOD(sp, "Default")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "", "a profile with no recovery field is valid")
    Do p.%Set("recovery", {"mode": "enabled"})
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "", "enabled is valid")
    Do p.%Set("recovery", {"mode": "on"})
    Do $$$AssertTrue($CLASSMETHOD(sp, "Validate", p) [ "recovery.mode", "another word is refused, named")
    Do p.%Set("recovery", {"mood": "enabled"})
    Do $$$AssertTrue($CLASSMETHOD(sp, "Validate", p) [ "recovery.mood", "a misspelt key is refused, named")
}

/// A site's install reads the shipped file as shadow; the demo adds enabled, and a restart's reseed keeps it.
Method TestTheSeed()
{
    Set path = ##class(%File).TempFilename("json")
    Set f = ##class(%Stream.FileCharacter).%New()
    Do f.LinkToFile(path)
    Set seed = ##class(Shutter.Store.SiteProfile).Default()
    Do seed.%Remove("version")
    Do f.Write(seed.%ToJSON())
    Do $$$AssertStatusOK(f.%Save(), "a seed file with no recovery field")
    // A row the seed follows, standing in for an empty store: a stored profile's history keeps its version numbers.
    Do ..SetMode("enabled")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set row.Source = path
    Do row.%Save()
    Set ^Shutter.Config("demo") = 0
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(path), "seeded on a site")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Mode(), "shadow", "a new site's install is in shadow")
    Set ^Shutter.Config("demo") = 1
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(path), "seeded on the demo")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Mode(), "enabled", "the demo is enabled, explicitly")
    Set version = ##class(Shutter.Store.SiteProfile).Row().Version
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(path), "a restart's reseed")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, version, "finds nothing to change")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Mode(), "enabled", "and it stays enabled")
    Set live = ##class(Shutter.Store.SiteProfile).Row()
    Set live.Source = path _ " (live hospital)", live.Json = seed.%ToJSON()
    Do live.%Save()
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(path), "the live hospital's stored form from before")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Mode(), "enabled", "is brought to enabled too")
    Do ##class(%File).Delete(path)
}

// ---- the wire ----

/// The negative control: enabled, one authorised write is exactly one POST, so the counter counts.
Method TestEnabledSendsExactlyOne()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase()
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(..Posts(), 1, "one POST")
    Do $$$AssertNotEquals(result.Outcome, "refused", "and it wasn't refused: " _ result.Error)
    Set p = ..Permits()
    Do $$$AssertEquals(p.%Size(), 1, "one permit")
    Do $$$AssertEquals(p.%Get(0).state, "answered", "answered")
}

Method TestShadowSendsNoWriteRehearsalOrPreview()
{
    Do ..SetMode("shadow")
    Set c = ..PlannedCase()
    Set dry = ##class(Shutter.Test.ShadowWire).Operation("rehearsal")
    Set dry.CaseId = c.CaseId
    Do ..Send(dry, .result)
    Do $$$AssertEquals(result.ReasonCode, "recovery_shadow", "a dry run, which a preview also is, is refused")
    Do $$$AssertTrue(result.Error [ "Not sent", "and says so: " _ result.Error)
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(result.ReasonCode, "recovery_shadow", "a write is refused")
    Do $$$AssertEquals(..Posts(), 0, "no POST")
    Do $$$AssertEquals(..Permits().%Size(), 0, "and no permit")
    Do $$$AssertTrue(##class(Shutter.Util.RecoveryControl).Refusal(.code) '= "", "the route and the workflow get the same refusal")
    Do $$$AssertEquals(code, "recovery_shadow", "with its code")
}

Method TestStopBeforeADispatch()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase()
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester"), "stopped")
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(result.ReasonCode, "recovery_stopped", "the approved write is refused")
    Do $$$AssertEquals(..Posts(), 0, "no POST")
    Do $$$AssertNotTrue($$$ISOK(##class(Shutter.Util.RecoveryControl).Stop("", "tester")), "a stop needs a reason")
}

/// The call that was on its way to admission when the stop committed: the job waits on the lock, the stop commits, and
/// the job is refused.
Method TestAdmissionPausedWhileAStopCommits()
{
    Do ..SetMode("enabled")
    LOCK +^Shutter.RecoveryControl
    Job ##class(Shutter.Test.RecoveryControl).JobAdmit("paused")
    Do $$$AssertTrue(..WaitFor("^Shutter.TestWire(""job"",""paused"",""started"")"), "the admission has started")
    Hang 0.5
    Do $$$AssertEquals($GET(^Shutter.TestWire("job", "paused")), "", "and waits for the lock")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester"), "the stop commits")
    LOCK -^Shutter.RecoveryControl
    Do $$$AssertTrue(..WaitFor("^Shutter.TestWire(""job"",""paused"")"), "the admission resumes")
    Hang 0.5
    Do $$$AssertEquals($GET(^Shutter.TestWire("job", "paused")), "refused:recovery_stopped", "and is refused")
    Do $$$AssertEquals(..Permits().%Size(), 0, "with no permit")
}

/// Four jobs admitting flat out and a stop in the middle: nothing is admitted at or after the stop's generation.
Method TestAStopRacingManyAdmissions()
{
    Do ..SetMode("enabled")
    For i = 1:1:4 { Job ##class(Shutter.Test.RecoveryControl).JobHammer("race") }
    For i = 1:1:50 { Quit:$GET(^Shutter.TestWire("hammer", "admitted"))>=40  Hang 0.1 }
    Do $$$AssertTrue($GET(^Shutter.TestWire("hammer", "admitted")) > 0, "the jobs are admitting")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester", .control), "the stop commits in the middle")
    Set generation = control.Generation
    Set admittedAtStop = ..Permits().%Size()
    For i = 1:1:20 { Quit:$GET(^Shutter.TestWire("hammer", "refused"))>=20  Hang 0.1 }
    Set ^Shutter.TestWire("stop", "race") = 1
    For i = 1:1:50 { Quit:$GET(^Shutter.TestWire("hammer", "done"))=4  Hang 0.1 }
    Do $$$AssertEquals(+$GET(^Shutter.TestWire("hammer", "done")), 4, "the jobs ended")
    Do $$$AssertTrue($GET(^Shutter.TestWire("hammer", "refused")) > 0, "and were refused after the stop")
    Set late = 0, it = ..Permits().%GetIterator()
    While it.%GetNext(, .p) { If p.generation >= generation Set late = late + 1 }
    Do $$$AssertEquals(late, 0, "no permit carries the stop's generation or a later one")
    Do $$$AssertEquals(..Permits().%Size(), admittedAtStop, "and none was added after the stop committed, of " _ admittedAtStop)
}

/// A call admitted before the stop may still complete: it is listed, and a read of the receiver still goes.
Method TestAdmittedThenStoppedIsOutstanding()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase()
    Do $$$AssertTrue(##class(Shutter.Util.RecoveryControl).Admit("recovery", c.CaseId, "Downstream Out", "K", "D", .permit, .code, .text), "admitted: " _ text)
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester"), "stopped")
    Set view = ##class(Shutter.Util.RecoveryControl).Read()
    Do $$$AssertEquals(view.outstandingCount, 1, "the call is outstanding")
    Do $$$AssertEquals(view.outstanding.%Get(0).id, permit.%Id(), "by id")
    Do $$$AssertEquals(view.stopped, 1, "while stopped")
    Set id = "", from = ..PermitsFrom
    &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store.RecoveryControlEvent WHERE Action = 'stop' ORDER BY ID DESC)
    Set event = ##class(Shutter.Store.RecoveryControlEvent).%OpenId(id)
    Do $$$AssertEquals(event.OutstandingIds, permit.%Id(), "and the stop's event names it")
    Do $$$AssertEquals(event.Actor, "tester", "with who stopped")
    Do ##class(Shutter.Test.CountingAdapter).Answer(200, "{""version"":3,""state"":""admitted""}")
    Set read = ##class(Shutter.Test.ShadowWire).Operation("read")
    Do ..Send(read, .result)
    Do $$$AssertEquals(result.Outcome, "read", "read-back goes on")
    Do $$$AssertEquals(##class(Shutter.Test.CountingAdapter).Count("GET"), 1, "one GET")
    Set result = ##class(Shutter.Msg.WardResult).%New()
    Set result.Outcome = "applied"
    Do ##class(Shutter.Util.RecoveryControl).Finish(permit, result)
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Read().outstandingCount, 0, "and once answered it's no longer outstanding")
}

/// Another process reads the stop from the database, and an install's and a start's refresh leave it alone.
Method TestAStopIsStoredNotHeld()
{
    Do ..SetMode("enabled")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester"), "stopped")
    Do ##class(Shutter.Util.RecoveryControl).Ensure()
    Do ##class(Shutter.Setup).RefreshKnowledge()
    Job ##class(Shutter.Test.RecoveryControl).JobAdmit("other")
    Do $$$AssertTrue(..WaitFor("^Shutter.TestWire(""job"",""other"")"), "another process asks")
    Hang 0.2
    Do $$$AssertEquals($GET(^Shutter.TestWire("job", "other")), "refused:recovery_stopped", "and it is stopped there too")
}

/// A call whose job ended with no answer reads as uncertain, stops recovery until a person has seen it, and isn't sent again.
Method TestACallCutOffIsUncertainAndNotRetried()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase()
    Job ##class(Shutter.Test.RecoveryControl).JobAdmitAndEnd(c.CaseId, "cut")
    Do $$$AssertTrue(..WaitFor("^Shutter.TestWire(""job"",""cut"")"), "the job admitted a call")
    Set id = ^Shutter.TestWire("job", "cut")
    Do $$$AssertTrue(id = +id, "with a permit: " _ id)
    For i = 1:1:50 { Quit:'$DATA(^$JOB($ZCHILD))  Hang 0.1 }
    Do $$$AssertEquals(##class(Shutter.Store.DispatchPermit).%OpenId(id).State, "admitted", "the record still says admitted")
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(result.ReasonCode, "recovery_stopped", "the next call finds it, and is refused")
    Do $$$AssertEquals(..Posts(), 0, "no retry on the wire")
    Set permit = ##class(Shutter.Store.DispatchPermit).%OpenId(id)
    Do $$$AssertEquals(permit.State, "uncertain", "the call is uncertain, not not-sent")
    Do $$$AssertEquals(permit.Orphaned, 1, "and marked cut off")
    Set view = ##class(Shutter.Util.RecoveryControl).Read()
    Do $$$AssertEquals(view.stopped, 1, "recovery is stopped")
    Do $$$AssertEquals(view.stoppedBy, "system", "by the control itself")
    Do $$$AssertEquals(view.outstandingCount, 1, "and the call is listed")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).ClearStop("seen it", view.generation, "a person"), "a person clears it")
    Set permit = "", permit = ##class(Shutter.Store.DispatchPermit).%OpenId(id)
    Do $$$AssertEquals(permit.State, "uncertain", "and the call stays uncertain: clearing says nothing of the receiver")
    Do $$$AssertEquals(permit.ReviewedBy, "a person", "with who saw it")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Read().outstandingCount, 0, "and it's off the list")
}

/// A call nobody answered, with the job alive: uncertain, as the connector says. The case reads it back, so it stops nothing.
Method TestAnUnansweredCallReadsUncertain()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase()
    Do ##class(Shutter.Test.CountingAdapter).Answer(0)
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(..Posts(), 1, "it was sent")
    Do $$$AssertEquals(result.Outcome, "uncertain", "the connector says uncertain")
    Set p = ..Permits()
    Do $$$AssertEquals(p.%Get(0).state, "uncertain", "and so does its record")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Read().stopped, 0, "the case's own read-back settles it, so recovery isn't stopped")
}

/// Clearing enables nothing and releases nothing; a plan made since goes.
Method TestAClearReleasesNoOldPlan()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase(.oldPlan)
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester", .control), "stopped")
    Set generation = control.Generation
    Do $$$AssertNotTrue($$$ISOK(##class(Shutter.Util.RecoveryControl).ClearStop("x", generation - 1, "a person")), "a stale generation is refused")
    Do $$$AssertNotTrue($$$ISOK(##class(Shutter.Util.RecoveryControl).ClearStop("", generation, "a person")), "and no reason")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).ClearStop("over", generation, "a person", .control), "cleared")
    Do $$$AssertTrue(control.Generation > generation, "the generation moved on")
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(result.ReasonCode, "plan_predates_control", "the old plan is refused")
    Do $$$AssertEquals(..Posts(), 0, "no POST")
    Set c = ..PlannedCase(.newPlan)
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(..Posts(), 1, "a new plan goes: " _ result.Error)
    Do ..SetMode("shadow")
    Do ..SetMode("enabled")
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(result.ReasonCode, "plan_predates_control", "going to shadow and back releases nothing either")
    Do $$$AssertEquals(..Posts(), 1, "still one POST")
    Do ..SetMode("shadow")
    Set c = ..PlannedCase()
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester", .control), "stopped in shadow")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).ClearStop("over", control.Generation, "a person"), "and cleared")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Mode(), "shadow", "a clear stays in shadow mode")
}

/// A kind of call the control doesn't know, a control that can't be read and one it can't lock all send nothing.
Method TestUnknownAndUnreadableSendNothing()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase()
    Set w = ..Write(c.CaseId)
    Set w.Purpose = "bulk"
    Do ..Send(w, .result)
    Do $$$AssertEquals(result.ReasonCode, "unknown_action", "an unknown kind")
    Set w.Purpose = ""
    Do ..Send(w, .result)
    Do $$$AssertEquals(result.ReasonCode, "unknown_action", "no kind")
    Do $$$AssertEquals(..Posts(), 0, "no POST")
    // Busy: another process holds the lock past the wait.
    Job ##class(Shutter.Test.RecoveryControl).JobHoldLock("busy", 8)
    Do $$$AssertTrue(..WaitFor("^Shutter.TestWire(""job"",""busy"")"), "the lock is held")
    Do ..Send(..Write(c.CaseId), .result)
    Do $$$AssertEquals(result.ReasonCode, "control_unavailable", "a control it can't lock")
    Do $$$AssertEquals(..Posts(), 0, "no POST")
    For i = 1:1:50 { Quit:'$DATA(^$JOB($ZCHILD))  Hang 0.2 }
    // Unreadable: the row's stored data damaged.
    Do ..DamageControl()
    Try {
        Do ..Send(..Write(c.CaseId), .result)
        Set reason = result.ReasonCode
        Set view = ##class(Shutter.Util.RecoveryControl).Read()
    } Catch ex {
        Set reason = ex.DisplayString(), view = {}
    }
    Do ..RepairControl()
    Do $$$AssertEquals(reason, "control_unreadable", "a control it can't read")
    Do $$$AssertEquals(..Posts(), 0, "no POST")
    Do $$$AssertEquals(view.stopped, 1, "and the screen reads stopped")
    Do $$$AssertEquals(view.readable, 0, "and says it can't read it")
}

/// The ordinary feed goes on through all of it, and only the feed: the purpose alone isn't a pass.
Method TestTheOrdinaryFeedGoesOn()
{
    Set feed = ##class(Shutter.Test.ShadowWire).Operation("normal")
    Set feed.SourceHeaderId = "1"
    Do ##class(Shutter.Test.CountingAdapter).Answer(201, "{""applied"":true}")
    Do ..SetMode("shadow")
    Do ..Send(feed, .result, ..#FEEDITEM)
    Do $$$AssertEquals(result.Outcome _ "|" _ ..Posts(), "applied|1", "delivered in shadow mode")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester"), "stopped")
    Do ..Send(feed, .result, ..#FEEDITEM)
    Do $$$AssertEquals(result.Outcome _ "|" _ ..Posts(), "applied|2", "delivered while stopped")
    Do ..DamageControl()
    Try {
        Do ..Send(feed, .result, ..#FEEDITEM)
    } Catch ex {
        Do $$$AssertEquals(ex.DisplayString(), "", "the feed throws nothing")
    }
    Do ..RepairControl()
    Do $$$AssertEquals(result.Outcome _ "|" _ ..Posts(), "applied|3", "delivered with the control unreadable")
    Do $$$AssertEquals(..Permits().%Size(), 0, "with no permit")
    Do ..Send(feed, .result)
    Do $$$AssertEquals(result.ReasonCode, "not_original_feed", "from no known item it's refused")
    Do ..Send(feed, .result, "Shutter API")
    Do $$$AssertEquals(result.ReasonCode, "not_original_feed", "from another item too")
    Set withCase = ##class(Shutter.Test.ShadowWire).Operation("normal")
    Set withCase.SourceHeaderId = "1", withCase.CaseId = "C-1"
    Do ..Send(withCase, .result, ..#FEEDITEM)
    Do $$$AssertEquals(result.ReasonCode, "not_original_feed", "and with a case")
    Do $$$AssertEquals(..Posts(), 3, "none of those was sent")
}

/// In shadow mode an email a person sends goes nowhere, file included, and stays unsent once recovery is enabled.
Method TestShadowSendsNoEmail()
{
    Set c = ..PlannedCase()
    Do ..SetMode("enabled")
    // The profile's own allowed domain when it has one, as the demo's teams need theirs.
    Set domains = ##class(Shutter.Store.SiteProfile).AllowedDomains()
    If $LISTLENGTH(domains) {
        Set domain = $LIST(domains, 1)
    } Else {
        Set domain = "example.org"
        Set p = ##class(Shutter.Store.SiteProfile).Current()
        Do p.%Remove("version")
        Do p.%Set("mail", {"allowed_domains": [(domain)]})
        Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "unit test", "unit test"), "a domain is allowed")
    }
    Set dir = ##class(%File).NormalizeDirectory(##class(%File).TempFilename("d"))
    Do ##class(%File).CreateDirectoryChain(dir)
    Set op = ##class(Shutter.Operation.EscalationMail).%New("UT Mail")
    Set op.Adapter = ##class(EnsLib.EMail.OutboundAdapter).%New()
    Set op.OutputFolder = dir
    For mode = "shadow", "enabled" {
        Do ..SetMode(mode)
        // SetMode reads the profile, so the domain stays.
        Set e = ##class(Shutter.Store.Escalation).%New()
        Set e.Case = c, e.Seq = $SELECT(mode = "shadow": 1, 1: 2), e.State = "queued", e.ToAddr = "team@" _ domain, e.Subject = "s", e.Body = "b"
        Do $$$AssertStatusOK(e.%Save(), "an escalation")
        Set m = ##class(Shutter.Msg.EscalationSend).%New()
        Set m.EscalationId = e.%Id()
        Do $$$AssertStatusOK(op.OnEscalationSend(m, .resp), "sent to the operation, " _ mode)
        Set e = ##class(Shutter.Store.Escalation).%OpenId(e.%Id(), 0)
        Set written = 0, rs = ##class(%SQL.Statement).%ExecDirect(, "CALL %Library.File_FileSet(?, '*.eml')", dir)
        Set files = rs.%NextResult()
        While $ISOBJECT(files) && files.%Next() { Set written = written + 1 }
        If mode = "shadow" {
            Do $$$AssertEquals(e.State, "failed", "shadow: not sent")
            Do $$$AssertTrue(e.Result [ "shadow", "and says why: " _ e.Result)
            Do $$$AssertEquals(written, 0, "and no file")
        } Else {
            Do $$$AssertEquals(e.State, "sent", "enabled: the negative control sends: " _ e.Result)
            Do $$$AssertEquals(written, 1, "and the file is written: " _ e.Result)
        }
    }
    Do ##class(%File).RemoveDirectoryTree(dir)
}

/// The report's denominator is cases reaching Shutter, a case with no observation stays in it, and it authorises nothing.
Method TestTheReport()
{
    Do ..SetMode("shadow")
    Set c = ..PlannedCase(.plan)
    Set before = ##class(Shutter.Util.RecoveryControl).Control().Generation
    Set result = ##class(Shutter.Msg.GateResult).%New()
    Set result.Outcome = "pass", result.ChecksJSON = "[{""result"":""pass"",""reason_code"":""A""},{""result"":""block"",""reason_code"":""B""}]"
    Set from = c.OpenedAt, to = "9"
    Do ##class(Shutter.Store.ShadowObservation).Capture(c, plan, result)
    Set rows = ##class(Shutter.Util.ShadowReport).Rows(from, to, "Downstream Out", .truncated)
    Set row = "", it = rows.%GetIterator()
    While it.%GetNext(, .r) { If r."case_id" = c.CaseId Set row = r }
    Do $$$AssertTrue($ISOBJECT(row), "the case has a row")
    Do $$$AssertEquals(row."proposed_disposition", "resend", "what was proposed")
    Do $$$AssertEquals(row."candidate_for_rehearsal", "true", "a resend past the gate is a candidate for rehearsal")
    Do $$$AssertEquals(row."blocking_reason_codes", "B", "the failing check's code")
    Do $$$AssertEquals(row."rehearsal_performed" _ row."final_dispatch_tested", "falsefalse", "nothing was tested")
    Do $$$AssertEquals(row."recovery_calls_sent", 0, "no calls")
    Set csv = ##class(Shutter.Util.ShadowReport).Csv(rows)
    Do $$$AssertTrue($PIECE(csv, $CHAR(13, 10), 1) = ##class(Shutter.Util.ShadowReport).#COLUMNS, "the header is the columns")
    Do $$$AssertNotTrue(csv [ "MRN9005", "no patient identifier leaves in the CSV")
    Do $$$AssertTrue(csv [ row."patient_reference", "a local reference instead")
    Do $$$AssertEquals(##class(Shutter.Util.ShadowReport).Cell("=2+2"), "'=2+2", "a formula stays text")
    Do $$$AssertEquals(##class(Shutter.Util.ShadowReport).Cell("a,""b"), """a,""""b""", "a comma and a quote are quoted")
    Set summary = ##class(Shutter.Util.ShadowReport).Summary(rows, truncated)
    Do $$$AssertEquals(summary.denominator, "cases reaching Shutter", "the denominator")
    Do $$$AssertEquals(summary.casesReachingShutter, rows.%Size(), "counted")
    Do $$$AssertEquals(summary.withObservation + summary.unobserved, summary.casesReachingShutter, "observed and not add up")
    Do $$$AssertTrue(summary.candidatesForRehearsal >= 1, "the candidate is counted")
    Do $$$AssertNotTrue($ZCONVERT(summary.%ToJSON() _ csv, "L") [ "would have recovered", "never what it can't say")
    Do $$$AssertTrue(summary.limits [ "authorises nothing", "and it says it authorises nothing")
    // Nothing the report does moves anything.
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Mode(), "shadow", "the mode stands")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Control().Generation, before, "and the generation")
    // A second case with no observation still counts.
    Do ##class(Shutter.Test.NoAnswer).Drop("C-TEST-RECCTL-B")
    Set b = ##class(Shutter.Store.Case).%New()
    Set b.CaseId = "C-TEST-RECCTL-B", b.OperationKey = "K", b.Receiver = "Downstream Out", b.FailureKind = "delivery_failed", b.FailureText = "x", b.State = "detected"
    Set b.OpenedAt = c.OpenedAt, b.UpdatedAt = c.OpenedAt, b.Headline = "h"
    Do $$$AssertStatusOK(b.%Save(), "a case not yet investigated")
    Set again = ##class(Shutter.Util.ShadowReport).Summary(##class(Shutter.Util.ShadowReport).Rows(from, to, "Downstream Out"))
    Do $$$AssertEquals(again.casesReachingShutter, summary.casesReachingShutter + 1, "is in the denominator")
    Do $$$AssertEquals(again.unobserved, summary.unobserved + 1, "as unobserved")
    Do ##class(Shutter.Test.NoAnswer).Drop("C-TEST-RECCTL-B")
    Set id = "", caseId = c.CaseId
    &sql(DELETE FROM Shutter_Store.ShadowObservation WHERE CaseId = :caseId)
}

/// The demo's purge restarts the plan ids and the case ids: the floor comes down with them, or every new plan would be refused,
/// and the permits go, or a new C-000001 would count an old one's calls.
Method TestAPurgeBringsTheFloorDown()
{
    Do ..SetMode("enabled")
    Set c = ..PlannedCase()
    Do $$$AssertTrue(##class(Shutter.Util.RecoveryControl).Admit("rehearsal", c.CaseId, "Downstream Out", "K", "D", .permit, .code, .text), "a call")
    Do ##class(Shutter.Util.RecoveryControl).Finish(permit, ##class(Shutter.Msg.WardResult).%New())
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester", .control), "stopped")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).ClearStop("over", control.Generation, "a person", .control), "cleared")
    Do $$$AssertTrue(control.PlanFloor > 0, "the floor is up")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).StoreEmptied(), "the store is emptied")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Control().PlanFloor, 0, "the floor is down")
    Do $$$AssertEquals(..Permits().%Size(), 0, "and the permits are gone")
}

/// A demo reset takes a stop with it; on a site it does nothing.
Method TestADemoResetClearsOnlyOnTheDemo()
{
    Do ..SetMode("enabled")
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).Stop("a test", "tester"), "stopped")
    Set ^Shutter.Config("demo") = 0
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).DemoReset("tester"), "a site")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Read().stopped, 1, "stays stopped")
    Set ^Shutter.Config("demo") = 1
    Do $$$AssertStatusOK(##class(Shutter.Util.RecoveryControl).DemoReset("tester"), "the demo")
    Do $$$AssertEquals(##class(Shutter.Util.RecoveryControl).Read().stopped, 0, "starts afresh")
}

}
