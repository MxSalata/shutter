/// Shutter.Util.EngineCheck: what the gate's engine blocks do to a case, through the workflow's own method, and which cases a
/// Completed header can close. The answers themselves are rows of Shutter.Test.Gate's table.
Class Shutter.Test.EngineCheck Extends %UnitTest.TestCase
{

Property Made As %String [ MultiDimensional ];

Method OnAfterOneTest() As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Quit $$$OK
}

Method NewCase(kind As %String = "delivery_failed") As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-ENGINE-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.EngineCheck)
    Set case.Event = "transfer", case.FailureKind = kind, case.FailureText = "made up", case.EncounterId = "ENC-UT1"
    Set case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP", case.Receiver = "LIMS Out", case.State = "gated", case.Mode = "rules"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^" _ case.CaseId, case.Disposition = "resend"
    Set case.SourceNamespace = "RIG", case.OriginHeaderId = "16"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// The workflow's own handling of a gate result holding these rows, and whether it took the case.
Method Outcome(case As Shutter.Store.Case, rows As %DynamicArray) As %Boolean
{
    Set result = ##class(Shutter.Msg.GateResult).%New()
    Set result.ChecksJSON = rows.%ToJSON(), result.DecisionId = "1"
    Set wf = ##class(Shutter.Process.CaseWorkflow).%New("Case Workflow")
    Do $$$AssertStatusOK(wf.BedWaitOutcome(case, result, .waited), "the outcome is taken")
    Quit waited
}

Method Facts(custody As %String, ack As %String = "connection", reason As %String = "") As %DynamicObject
{
    Quit {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": (custody), "status": "Delivered", "itemStatus": "Retry", "completedAt": "2026-11-07 03:12:01.123", "why": "", "attempts": ""}], "effectiveAck": (ack), "ackReason": (reason)}
}

Method TestStillTryingWaitsOnTheEngine()
{
    Set case = ..NewCase()
    Set row = ##class(Shutter.Util.EngineCheck).Judge(..Facts("engine"))
    Do $$$AssertTrue(..Outcome(case, [(row)]), "the workflow takes it")
    Set after = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(after.State, "blocked", "blocked")
    Do $$$AssertEquals(after.WaitsOnEngine, "RIG:17", "waiting on that header in that namespace")
    Do $$$AssertTrue($EXTRACT(after.Headline, 1, 23) = "Waiting for the engine:", "headline: " _ after.Headline)
    Do $$$AssertEquals(after.Outcome, "", "no outcome yet")
}

Method TestDeliveredResolvesWithTheWords()
{
    Set case = ..NewCase()
    Set row = ##class(Shutter.Util.EngineCheck).Judge(..Facts("delivered"))
    Do $$$AssertTrue(..Outcome(case, [(row)]), "the workflow takes it")
    Set after = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(after.State, "resolved", "resolved")
    Do $$$AssertTrue(after.Outcome [ "(header 17); accepted on the connection; nothing was resent by Shutter", "Outcome: " _ after.Outcome)
    Do $$$AssertEquals(after.Disposition, "resend", "the plan's disposition kept")
    Do $$$AssertEquals(after.WaitsOnEngine, "", "no wait")
}

Method TestNotEstablishedIsAPersons()
{
    Set case = ..NewCase()
    Set row = ##class(Shutter.Util.EngineCheck).Judge(..Facts("delivered", "not_established", ":?E=C"))
    Do $$$AssertTrue(..Outcome(case, [(row)]), "the workflow takes it")
    Set after = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(after.State, "blocked", "blocked, not resolved")
    Do $$$AssertTrue(after.Outcome [ "IRIS marked this delivery Completed. Receiver acceptance has not been established.", "Outcome: " _ after.Outcome)
    Do $$$AssertTrue(after.Outcome [ ":?E=C", "with the pattern printed")
}

Method TestWhatACompletedHeaderCantClose()
{
    Set row = ##class(Shutter.Util.EngineCheck).Judge(..Facts("delivered"))
    For kind = "rejected", "unmappable", "withheld", "unreadable" {
        Set case = ..NewCase(kind)
        Do ..Outcome(case, [(row)])
        Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).State, "blocked", kind _ " stays with a person")
    }
    Set case = ..NewCase("uncertain_outcome")
    Do ..Outcome(case, [{"check": "identity", "result": "block", "reason_code": "PATIENT_MISMATCH", "detail": "made up"}, (row)])
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).State, "blocked", "an identity conflict stays with a person")
    Set case = ..NewCase("uncertain_outcome")
    Do ..Outcome(case, [(row)])
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).State, "resolved", "an uncertain delivery the engine completed closes")
}

Method TestMayHoldAndUnreadableStopForAPerson()
{
    Set f = ..Facts("settled")
    Do f.headers.%Get(0).%Set("attempts", "reached_receiver")
    Set case = ..NewCase()
    Do $$$AssertTrue(..Outcome(case, [(##class(Shutter.Util.EngineCheck).Judge(f))]), "the workflow takes the first")
    Set after = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(after.State, "blocked", "blocked")
    Do $$$AssertTrue(after.Headline [ "own screen", "the headline names the receiver's screen: " _ after.Headline)
    Set case = ..NewCase()
    Do $$$AssertTrue(..Outcome(case, [(##class(Shutter.Util.EngineCheck).Judge(..Facts("unreadable")))]), "and the second")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).State, "blocked", "blocked once the refreshes have run out")
}

Method TestUnreadableIsRefreshable()
{
    Set result = ##class(Shutter.Msg.GateResult).%New()
    Set result.ChecksJSON = [(##class(Shutter.Util.EngineCheck).Judge(..Facts("unreadable")))].%ToJSON()
    Set wf = ##class(Shutter.Process.CaseWorkflow).%New("Case Workflow")
    Do $$$AssertTrue(wf.OnlyRefreshable(result), "a failed read is refreshed as a receiver that couldn't be read is")
    Set result.ChecksJSON = [(##class(Shutter.Util.EngineCheck).Judge(..Facts("engine")))].%ToJSON()
    Do $$$AssertNotTrue(wf.OnlyRefreshable(result), "a wait isn't")
}

/// Scope read live, in a namespace that exists with no production running: nothing can be read, and the words say so.
Method TestLiveReadWithNoProductionIsUnreadable()
{
    Set case = ..NewCase()
    Set case.SourceNamespace = $NAMESPACE, case.OriginHeaderId = "1", case.Receiver = "UT No Such Item"
    Set row = ##class(Shutter.Util.EngineCheck).Row(case)
    Do $$$AssertEquals(row."reason_code", "ENGINE_UNREADABLE", "unreadable: " _ row.%ToJSON())
    Do $$$AssertEquals(row.result, "unknown", "which blocks a write")
}

/// A person's reopening clears the wait: the line in the workflow, by reading it, since the reopening needs a production.
Method TestReopenClearsTheMarker()
{
    Set m = ##class(%Dictionary.MethodDefinition).%OpenId("Shutter.Process.CaseWorkflow||OnReinvestigate")
    Do $$$AssertTrue(m.Implementation.Read(32000) [ "case.WaitsOnEngine = """"", "the marker is cleared beside the other two")
}

Method TestReleaseFindsItsCases()
{
    Do $$$AssertEquals(##class(Shutter.Store.Case).ReleaseWaitingOnEngine(""), 0, "no header, nothing released")
}

}
