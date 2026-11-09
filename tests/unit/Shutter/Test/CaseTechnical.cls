/// The facts the cases list and the case page show in Technical (Shutter.API.Dispatch.Technical): read only, from what the
/// production already holds, and never a patient field. The source message, the case intake and the plan are made here
/// in this namespace, under sessions and public ids of their own, and removed afterwards.
Class Shutter.Test.CaseTechnical Extends %UnitTest.TestCase
{

/// The headers, the case and the plan this test made.
Property Headers As %List;

Property Cases As %List;

Property Plans As %List;

Property Intakes As %List;

Method OnAfterOneTest(testname As %String) As %Status
{
    Set ptr = 0
    While $LISTNEXT(..Plans, ptr, id) { Do ##class(Shutter.Store.Plan).%DeleteId(id) }
    Set ptr = 0
    While $LISTNEXT(..Cases, ptr, id) { Do ##class(Shutter.Store.Case).%DeleteId(id) }
    Set ptr = 0
    While $LISTNEXT(..Intakes, ptr, id) { Do ##class(Shutter.Msg.CaseIntake).%DeleteId(id) }
    Set ptr = 0
    While $LISTNEXT(..Headers, ptr, id) {
        Set h = ##class(Ens.MessageHeader).%OpenId(id)
        If $ISOBJECT(h) && (h.MessageBodyClassName = "EnsLib.HL7.Message") Do ##class(EnsLib.HL7.Message).%DeleteId(h.MessageBodyId)
        Do ##class(Ens.MessageHeader).%DeleteId(id)
    }
    Set (..Headers, ..Cases, ..Plans, ..Intakes) = ""
    Quit $$$OK
}

/// A made-up ADT^A02 with a made-up patient, so the test can show the patient's fields never come out.
ClassMethod Text() As %String
{
    Quit "MSH|^~\&|PAS|HOSP|BED|HOSP|20261108190000||ADT^A02^ADT_A02|UTTECH1|P|2.5.1" _ $CHAR(13) _ "EVN|A02|20261108190000" _ $CHAR(13) _ "PID|1||MRN-UT-TECH^^^HOSP^MR||UNITTEST^MADEUP" _ $CHAR(13) _ "PV1|1|I|WARD-B^BAY1^02^HOSP||||||||||||||||ENC-UT-TECH" _ $CHAR(13)
}

/// The header that carried the HL7 message into the feed.
Method Source(session As %Integer, from As %String) As Ens.MessageHeader
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(..Text())
    Do msg.%Save()
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SessionId = session, h.SourceConfigName = from, h.TargetConfigName = "ADT to Downstream"
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = msg.%Id()
    Do h.%Save()
    Set ..Headers = ..Headers _ $LISTBUILD(h.%Id())
    Quit h
}

/// The feed's case intake for a receiver, in the session, with its header's time.
Method Intake(session As %Integer, receiver As %String, time As %String)
{
    Set i = ##class(Shutter.Msg.CaseIntake).%New()
    Set i.Receiver = receiver, i.FailureKind = "delivery_failed"
    Do i.%Save()
    Set ..Intakes = ..Intakes _ $LISTBUILD(i.%Id())
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SessionId = session, h.SourceConfigName = "ADT to Downstream", h.TargetConfigName = "Case Workflow"
    Set h.MessageBodyClassName = "Shutter.Msg.CaseIntake", h.MessageBodyId = i.%Id(), h.TimeCreated = time
    Do h.%Save()
    Set ..Headers = ..Headers _ $LISTBUILD(h.%Id())
}

/// A case of the feed's own, saved, with its source header and session, and a current plan.
Method Case(session As %Integer, receiver As %String, header As Ens.MessageHeader, withPlan As %Boolean = 1) As Shutter.Store.Case
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "UT-TECH-" _ $RANDOM(1000000), c.OperationKey = "PAS^HOSP^MRN-UT-TECH^ENC-UT-TECH^transfer^2026-11-08T19:00:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-UT-TECH", c.PatientId = "MRN-UT-TECH", c.PatientIdAuthority = "HOSP"
    Set c.FailureKind = "delivery_failed", c.Receiver = receiver, c.EnsSessionId = session, c.SourceHeaderId = header.%Id()
    Set c.SourceMessageId = "UTTECH1"
    Do $$$AssertStatusOK(c.%Save(), "the case is saved")
    Set ..Cases = ..Cases _ $LISTBUILD(c.%Id())
    If withPlan {
        Set p = ##class(Shutter.Store.Plan).%New()
        Do p.CaseSetObjectId(c.%Id())
        Set p.Version = 2, p.Digest = "sha256:c32d519e968bb1ceca8b4666aed317c64f58f197b9771e8b4958b464b241793e", p.CatalogueEntry = "E2"
        Do $$$AssertStatusOK(p.%Save(), "the plan is saved")
        Set ..Plans = ..Plans _ $LISTBUILD(p.%Id())
        Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE Shutter_Store.""Case"" SET CurrentPlan = ? WHERE ID = ?", p.%Id(), c.%Id())
        Do c.%Reload()
    }
    Quit c
}

/// What the method adds, beside the projection, for one case.
ClassMethod Added(c As Shutter.Store.Case) As %DynamicObject
{
    Set o = {}
    Do ##class(Shutter.API.Dispatch).Technical(c, o)
    Quit o
}

/// What the cases list adds for one case: its own row of the list's query, then Technical with that row.
ClassMethod ListAdded(c As Shutter.Store.Case) As %DynamicObject
{
    Set o = {}, args = 1, args(1) = c.CaseId
    Set rs = ##class(Shutter.API.Dispatch).CaseRows(1, " AND c.CaseId = ?", .args)
    If rs.%Next() Do ##class(Shutter.API.Dispatch).Technical(c, o, .seen, ##class(Shutter.API.Dispatch).RowOf(rs))
    Quit o
}

/// The list reads in its own query what the case page reads one by one, to the same facts: for the feed's own receiver,
/// another receiver of the same session and a receiver with no intake, each with and without a plan, and for a case
/// whose source header is gone.
Method TestTheListReadsTheSame()
{
    Set session = 999990000 + $RANDOM(9000)
    Set src = ..Source(session, "ADT In")
    Do ..Intake(session, "Records Out", "2026-11-08 19:00:01.250")
    Do ..Intake(session, "Downstream Out", "2026-11-08 19:00:02.500")
    For receiver = "Downstream Out", "Records Out", "Nobody Out" {
        For withPlan = 1, 0 {
            Set c = ..Case(session, receiver, src, withPlan)
            Set page = ..Added(c), list = ..ListAdded(c)
            Do $$$AssertEquals(list.%ToJSON(), page.%ToJSON(), receiver _ $SELECT(withPlan: " with", 1: " without") _ " a plan: the list's row says what the case page says")
        }
    }
    Do $$$AssertEquals(..ListAdded(c).failedAt, "", "a receiver with no intake has no time")
    Set c = ..Case(session, "Downstream Out", src, 1)
    Do $$$AssertEquals(..ListAdded(c).failedAt, "2026-11-08T19:00:02.500Z", "the list finds the intake for the case's own receiver")
    Do $$$AssertEquals(..ListAdded(c).messageType, "ADT^A02", "and MSH-9 from the source message")
    Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE Shutter_Store.""Case"" SET SourceHeaderId = ? WHERE ID = ?", 999999999, c.%Id())
    Do c.%Reload()
    Do $$$AssertEquals(..ListAdded(c).%ToJSON(), ..Added(c).%ToJSON(), "a source header that is gone: the same, with no type and no item")
}

Method TestTheFeedsOwnCase()
{
    Set session = 999990000 + $RANDOM(9000)
    Set src = ..Source(session, "ADT In")
    // Two receivers fed from one session: each case takes its own receiver's intake
    Do ..Intake(session, "Records Out", "2026-11-08 19:00:01.250")
    Do ..Intake(session, "Downstream Out", "2026-11-08 19:00:02.500")
    Set c = ..Case(session, "Downstream Out", src)
    Set o = ..Added(c)
    Do $$$AssertEquals(o.messageType, "ADT^A02", "MSH-9's type and trigger, without the structure")
    Do $$$AssertEquals(o.production, ##class(Shutter.Setup).ProductionName(), "the production the feed runs in")
    Do $$$AssertEquals(o.sourceItem, "ADT In", "the item the message came in by")
    Do $$$AssertEquals(o.failedAt, "2026-11-08T19:00:02.500Z", "the time of the intake for this case's receiver, as ISO UTC")
    Do $$$AssertEquals(o.planVersion, 2, "the plan's version")
    Do $$$AssertEquals(o.%GetTypeOf("planVersion"), "number", "as a number")
    Do $$$AssertEquals(o.planDigest, "sha256:c32d519e968bb1ceca8b4666aed317c64f58f197b9771e8b4958b464b241793e", "the plan's digest")
    Do $$$AssertEquals(o.catalogueEntry, "E2", "the plan's catalogue entry")
    Do $$$AssertTrue(o.links.visualTrace [ ("EnsPortal.VisualTrace.zen?SESSIONID=" _ session), "the Visual Trace of the case's session")
    // Shutter.Production's receiver is Shutter.Operation.Ward; a site's own production names its own class
    Set prod = ##class(Ens.Config.Production).%OpenId(##class(Shutter.Setup).ProductionName())
    Set expected = ""
    If $ISOBJECT(prod) { For i = 1:1:prod.Items.Count() { If prod.Items.GetAt(i).Name = "Downstream Out" Set expected = prod.Items.GetAt(i).ClassName } }
    If expected = "" {
        Do $$$AssertNotTrue(o.%IsDefined("receiverClass"), "no class for a receiver the production does not have")
    } Else {
        Do $$$AssertEquals(o.receiverClass, expected, "the class of the receiver's item")
    }
}

Method TestNoPatientField()
{
    Set session = 999990000 + $RANDOM(9000)
    Set src = ..Source(session, "ADT In")
    Do ..Intake(session, "Downstream Out", "2026-11-08 19:00:02.500")
    Set json = ..Added(..Case(session, "Downstream Out", src)).%ToJSON()
    For word = "MRN-UT-TECH", "UNITTEST", "MADEUP", "ENC-UT-TECH", "WARD-B" {
        Do $$$AssertNotTrue(json [ word, "nothing of the patient or the visit in what is added: " _ word)
    }
}

Method TestAForwardedCase()
{
    Set session = 999990000 + $RANDOM(9000)
    Set src = ..Source(session, "Case Intake")
    Set c = ..Case(session, "Downstream Out", src, 0)
    Set c.SourceNamespace = "HOSPITAL", c.SourceProduction = "Hospital.Production", c.SourceRoute = "PAS In"
    Set o = ..Added(c)
    Do $$$AssertEquals(o.production, "Hospital.Production", "the forwarding production")
    Do $$$AssertEquals(o.sourceItem, "PAS In", "its route, not Shutter's intake item")
    Do $$$AssertNotTrue(o.%IsDefined("receiverClass"), "the receiver is in another production: no class is guessed")
    Do $$$AssertNotTrue(o.%IsDefined("failedAt"), "no intake in the session: no time")
    Do $$$AssertNotTrue(o.%IsDefined("planVersion"), "no plan: no version")
    Do $$$AssertEquals(o.messageType, "ADT^A02", "Shutter's copy of the message gives the type")
}

Method TestNothingToRead()
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "UT-TECH-EMPTY", c.OperationKey = "x", c.Receiver = "Downstream Out"
    Set o = ..Added(c)
    Do $$$AssertNotTrue(o.%IsDefined("messageType"), "no header: no type")
    Do $$$AssertNotTrue(o.%IsDefined("sourceItem"), "no header: no item")
    Do $$$AssertNotTrue(o.%IsDefined("failedAt"), "no session: no time")
}

}
