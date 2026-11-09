/// Shutter.Util.ResendSet: the item gate as a table, and the four lists on real headers, log rows, copies and ledger rows
/// made in this namespace under an item name of the test's own and removed after each test. The log rows copy the words
/// the engine wrote on 2026.2 and 2027.1.0AI; every patient is made up.
Class Shutter.Test.ResendSet Extends %UnitTest.TestCase
{

Parameter NEVER = "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7202";

Parameter READTIMEOUT = "ERROR <Ens>ErrTCPTerminatedReadTimeoutExpired: TCP Read timeout (30) expired waiting for response message on 127.0.0.1:7202";

Parameter SUSPENDING = "ERROR <Ens>ErrGeneral: Suspending HL7 Message body 1@EnsLib.HL7.Message / 1 because response 2@EnsLib.HL7.Message MSA code 'AE' matched ReplyCodeActions";

Property Item As %String;

Property Made As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..Item = "ResendSet Test Out " _ $JOB _ "-" _ $INCREMENT(^||ResendSetTest)
    // The event log reaches back past every header made here (rule 4): one old row, removed after.
    Set row = ##class(Ens.Util.Log).%New()
    Set row.Type = 4, row.Text = "ResendSet test: the oldest row", row.ConfigName = ..Item, row.TimeLogged = "2000-01-01 00:00:00.000", row.SourceClass = "Shutter.Test.ResendSet", row.SourceMethod = "OnBeforeOneTest"
    Do row.%Save()
    Set ..Made("Ens.Util.Log", row.%Id()) = ""
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set class = ""
    For {
        Set class = $ORDER(..Made(class)) Quit:class=""
        Set id = "" For { Set id = $ORDER(..Made(class, id)) Quit:id=""  Do $CLASSMETHOD(class, "%DeleteId", id) }
    }
    Kill ..Made
    Quit $$$OK
}

/// Rules 2 and 7: each condition of the item stops the set, with its reason.
Method TestItemGate()
{
    Set ok = {"answer": "ok", "productionState": "running", "enabled": 1, "queue": 0, "status": "OK", "headHeaderId": ""}, ft = {"source": "item", "value": "0"}
    Do $$$AssertEquals(##class(Shutter.Util.ResendSet).ItemGate(ok, ft), "", "every condition met")
    Do $$$AssertEquals(##class(Shutter.Util.ResendSet).ItemGate(ok, {"source": "class_default", "value": "15"}), "", "a bounded FailureTimeout")
    For pair = $LISTBUILD("productionState", "not running", "not running"), $LISTBUILD("enabled", 0, "disabled"), $LISTBUILD("queue", 3, "the queue holds 3 messages"), $LISTBUILD("status", "Retry", "retrying"), $LISTBUILD("headHeaderId", "77", "trying header 77"), $LISTBUILD("answer", "unknown", "could not be read") {
        Set s = {}.%FromJSON(ok.%ToJSON())
        Do s.%Set($LIST(pair, 1), $LIST(pair, 2))
        Set why = ##class(Shutter.Util.ResendSet).ItemGate(s, ft)
        Do $$$AssertTrue(why [ $LIST(pair, 3), $LIST(pair, 1) _ ": " _ why)
    }
    Do $$$AssertTrue(##class(Shutter.Util.ResendSet).ItemGate(ok, {"source": "item", "value": "-1"}) [ "FailureTimeout is -1", "-1 refuses")
    Do $$$AssertTrue(##class(Shutter.Util.ResendSet).ItemGate(ok, {"source": "unknown", "value": "", "why": "no setting"}) [ "unknown is treated as -1", "unknown refuses")
    Set out = ##class(Shutter.Util.ResendSet).NotComputed("the production is not running")
    Do $$$AssertEquals(out.set.status _ "/" _ out.set.reason, "not_computed/the production is not running", "not_computed with the reason")
    Do $$$AssertEquals(out.lists.offered.%Size(), 0, "and no list")
    Do $$$AssertEquals(out.words.first, "Shutter will not send these messages. Review them in the Message Viewer using the site's recovery procedure.", "the words")
}

/// O4.c and O5.b as a list: the never-opened messages offered in order; a read timeout reached; a Suspended AE and a
/// header with no rows refused; a Queued one waits; a Completed one in none.
Method TestFourLists()
{
    Set a = ..Failed("9990000301^^^NHS^NH", 8, ..#NEVER, "CA")
    Set b = ..Failed("9990000302^^^NHS^NH", 8, ..#READTIMEOUT, "CB")
    Set c = ..Failed("9990000303^^^NHS^NH", 5, ..#SUSPENDING, "CC")
    Set d = ..Failed("9990000304^^^NHS^NH", 8, "", "CD")
    Set e = ..Failed("9990000305^^^NHS^NH", 2, "", "CE")
    Set f = ..Failed("9990000306^^^NHS^NH", 8, ..#NEVER, "CF")
    Set out = ..Run()
    Do $$$AssertEquals(out.set.status, "computed", "computed")
    Do $$$AssertEquals(..Controls(out.lists.offered), "CA,CF", "offered: the never-opened, in order")
    Do $$$AssertEquals(..Controls(out.lists.reached), "CB", "reached: the read timeout")
    Do $$$AssertEquals(..Controls(out.lists.refused), "CC,CD", "refused: the Suspended AE and the one with no rows")
    Do $$$AssertEquals(..Controls(out.lists.queued), "CE", "queued: the one the engine still has")
    Do $$$AssertTrue(out.lists.refused.%Get(0).reason [ "Suspended", "Suspended set aside")
    Do $$$AssertEquals(out.lists.offered.%Get(0).patient.id _ "/" _ out.lists.offered.%Get(0).patient.authority, "9990000301/NHS", "the row's patient")
    Do $$$AssertEquals(out.lists.offered.%Get(0).attempts, "never_opened", "the row's attempts")
    Do $$$AssertEquals($LENGTH(out.set.digest), 64, "a SHA-256 digest")
    Do ..Failed("9990000307^^^NHS^NH", 9, "", "CG")
    Do $$$AssertNotTrue(..Controls(..Run().lists.refused) [ "CG", "a Completed header is in no list")
}

/// A copy resent by hand before the list: refused as resent by hand; a copy still being tried: wait.
Method TestResentByHand()
{
    Set a = ..Failed("9990000311^^^NHS^NH", 8, ..#NEVER, "HA")
    Do ..Copy(a, 9, 0)
    Set b = ..Failed("9990000312^^^NHS^NH", 8, ..#NEVER, "HB")
    Do ..Copy(b, 2, 0)
    Set out = ..Run()
    Do $$$AssertEquals(..Controls(out.lists.offered), "", "neither offered")
    Do $$$AssertTrue(out.lists.refused.%Get(0).reason [ "resent by hand at ", out.lists.refused.%Get(0).reason)
    Do $$$AssertTrue(out.lists.queued.%Get(0).reason [ "being tried: wait", "a copy being tried waits")
}

/// Shutter's own clone in Error with never-opened rows stands in the origin's place; one that reads otherwise refuses.
Method TestOwnClone()
{
    Set a = ..Failed("9990000321^^^NHS^NH", 8, ..#NEVER, "OA")
    Set clone = ..Copy(a, 8, 1, ..#NEVER)
    Set out = ..Run()
    Do $$$AssertEquals(out.lists.offered.%Size(), 1, "offered")
    Do $$$AssertEquals(out.lists.offered.%Get(0).headerId, clone, "the clone in the origin's place")
    Do $$$AssertTrue(out.lists.offered.%Get(0).reason [ "Shutter tried at", "says Shutter tried")
    Set b = ..Failed("9990000322^^^NHS^NH", 8, ..#NEVER, "OB")
    Do ..Copy(b, 9, 1)
    Set out = ..Run()
    Do $$$AssertTrue(..Controls(out.lists.refused) [ "OB", "a completed clone of Shutter's refuses")
}

/// Two failed messages for one patient: both offered, no self-hit; a blank PID-3.4 holds that patient.
Method TestPatientCheck()
{
    Do ..Failed("9990000331^^^NHS^NH", 8, ..#NEVER, "PA")
    Do ..Failed("9990000331^^^NHS^NH", 8, ..#NEVER, "PB")
    Do ..Failed("9990000332^^^^NH", 8, ..#NEVER, "PC")
    Set out = ..Run()
    Do $$$AssertEquals(..Controls(out.lists.offered), "PA,PB", "one patient's two messages both offered")
    Do $$$AssertEquals(..Controls(out.lists.refused), "PC", "a blank authority held")
    Do $$$AssertTrue(out.lists.refused.%Get(0).reason [ "held by the patient check", out.lists.refused.%Get(0).reason)
}

/// A case from another production names its header there by SourceNamespace and OriginHeaderId; its SourceHeaderId is
/// Shutter's own copy, whose id can equal a header id of the watched namespace, and must never match one (found on the
/// Pathology rig, O7.b: the run took another receiver's case for a message's own, so the patient check held the message).
Method TestCaseRowsByNamespace()
{
    Set rs = "Shutter.Util.ResendSet", here = $NAMESPACE
    Set own = ..Case("RS-T-OWN", "LABSITE-T", 990000156, 990000223)
    Set other = ..Case("RS-T-OTHER", "OTHERNS-T", 990000107, 990000156)
    Set local = ..Case("RS-T-LOCAL", "", "", 990000156)
    Set got = $CLASSMETHOD(rs, "CaseRows", "LABSITE-T", 990000156)
    Do $$$AssertEquals(got.%Size(), 1, "one case on LABSITE-T's header 990000156: " _ got.%ToJSON())
    Do $$$AssertEquals(got.%Get(0).caseId, "RS-T-OWN", "the case whose origin is that header, not the one whose stored copy has that id")
    Do $$$AssertEquals($LISTTOSTRING($CLASSMETHOD(rs, "CasesOf", "LABSITE-T", [{"headerId": 990000156}])), "RS-T-OWN", "CasesOf likewise")
    Set got = $CLASSMETHOD(rs, "CaseRows", here, 990000156)
    Do $$$AssertEquals(got.%Size(), 1, "in Shutter's own namespace, its own feed's case on header 990000156: " _ got.%ToJSON())
    Do $$$AssertEquals(got.%Get(0).caseId, "RS-T-LOCAL", "and only that one")
    Do $$$AssertEquals($CLASSMETHOD(rs, "CaseRows", "OTHERNS-T", 990000156).%Size(), 0, "OTHERNS-T's header 990000156 has no case")
}

Method Case(caseId As %String, ns As %String, origin As %String, source As %String) As %String
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = caseId, c.OperationKey = "LAB^NHS^999000^^result^2026-11-09T08:00:00Z", c.Receiver = "ResendSet Test Out"
    Set c.FailureKind = "delivery_failed", c.State = "escalated", c.OpenedAt = "2026-11-09T08:00:00Z"
    Set c.SourceNamespace = ns, c.OriginHeaderId = origin, c.SourceHeaderId = source
    Do c.%Save()
    Set ..Made("Shutter.Store.Case", c.%Id()) = ""
    Quit c.%Id()
}

/// The digest moves with the set and stands still without a change.
Method TestDigest()
{
    Do ..Failed("9990000341^^^NHS^NH", 8, ..#NEVER, "DA")
    Set one = ..Run().set.digest
    Do $$$AssertEquals(..Run().set.digest, one, "the same set, the same digest")
    Do ..Failed("9990000342^^^NHS^NH", 8, ..#NEVER, "DB")
    Do $$$AssertNotEquals(..Run().set.digest, one, "another member moves it")
}

/// The two message classes compile and keep their properties, with no sender.
Method TestMessages()
{
    Set rq = ##class(Shutter.Msg.EngineResendRequest).%New()
    Set rq.OriginHeaderId = "12", rq.Namespace = "PATHOLOGY", rq.ApprovalId = "AP-1", rq.CaseId = "C-000001"
    Do $$$AssertStatusOK(rq.%Save(), "the request saves")
    Set ..Made("Shutter.Msg.EngineResendRequest", rq.%Id()) = ""
    Set back = ##class(Shutter.Msg.EngineResendRequest).%OpenId(rq.%Id())
    Do $$$AssertEquals(back.OriginHeaderId _ "/" _ back.Namespace _ "/" _ back.ApprovalId _ "/" _ back.CaseId, "12/PATHOLOGY/AP-1/C-000001", "and reads back")
    Set rs = ##class(Shutter.Msg.EngineResendResult).%New()
    Set rs.NewHeaderId = "13", rs.Status = "Completed", rs.Words = "sent once"
    Do $$$AssertStatusOK(rs.%Save(), "the result saves")
    Set ..Made("Shutter.Msg.EngineResendResult", rs.%Id()) = ""
}

/// The lists for the test's item over every time.
Method Run() As %DynamicObject
{
    Quit ##class(Shutter.Util.ResendSet).Lists($NAMESPACE, ..Item, "2000-01-01 00:00:00", "2999-12-31 23:59:59", "Results Out")
}

/// A header to the test's item with status <var>status</var> (8 Error, 5 Suspended, 2 Queued, 9 Completed), its own
/// session, a body for PID-3 <var>pid</var> with control id <var>control</var>, and one log row of <var>words</var>.
Method Failed(pid As %String, status As %Integer, words As %String, control As %String) As %String
{
    Set cr = $CHAR(13)
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|FAKESEND|SITE|FAKELIMS|LAB|20261105100000||ORU^R01|" _ control _ "|P|2.5.1" _ cr _ "PID|1||" _ pid _ "||Testpatient^Alpha" _ cr _ "OBR|1|ORD1|FIL1|PANEL1" _ cr _ "OBX|1|ST|TST01||VAL10|||||F", .sc)
    Set msg.DocType = "2.5.1:ORU_R01"
    Do msg.%Save()
    Set ..Made("EnsLib.HL7.Message", msg.%Id()) = ""
    Set id = ..Header(msg.%Id(), status, "", 0, "")
    Do:words'="" ..Log(id, words)
    Quit id
}

/// A copy of header <var>of</var> in its session, as a stock resend makes it; with <var>own</var>, a ledger row names it.
Method Copy(of As %String, status As %Integer, own As %Boolean, words As %String = "") As %String
{
    Set o = ##class(Ens.MessageHeader).%OpenId(of)
    Set id = ..Header(o.MessageBodyId, status, o.SessionId, 1, "Resent " _ of)
    Do:words'="" ..Log(id, words)
    If own {
        Set r = ##class(Shutter.Store.ResendRecord).%New()
        Set r.RunId = "RUN-TEST", r.Namespace = $NAMESPACE, r.Item = ..Item, r.OriginHeaderId = of, r.NewHeaderId = id, r.State = $SELECT(status = 9: "completed", 1: "failed")
        Do r.%Save()
        Set ..Made("Shutter.Store.ResendRecord", r.%Id()) = ""
    }
    Quit id
}

Method Header(bodyId As %String, status As %Integer, session As %String, resent As %Integer, description As %String) As %String
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.TargetConfigName = ..Item, h.SourceConfigName = "ResendSet Test In", h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = bodyId
    Set h.Status = status, h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), h.Type = 1, h.Resent = resent, h.Description = description
    Do h.%Save()
    Set:session="" session = h.%Id()
    Set h.SessionId = session
    Do h.%Save()
    Set ..Made("Ens.MessageHeader", h.%Id()) = ""
    Quit h.%Id()
}

Method Log(headerId As %String, words As %String)
{
    Set h = ##class(Ens.MessageHeader).%OpenId(headerId)
    Set row = ##class(Ens.Util.Log).%New()
    Set row.Type = 2, row.Text = words, row.SessionId = h.SessionId, row.MessageId = headerId, row.ConfigName = ..Item, row.TimeLogged = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), row.SourceClass = "EnsLib.HL7.Operation.TCPOperation", row.SourceMethod = "OnMessage"
    Do row.%Save()
    Set ..Made("Ens.Util.Log", row.%Id()) = ""
}

/// A list's control ids, comma-separated.
ClassMethod Controls(list As %DynamicArray) As %String
{
    Set text = ""
    Set iter = list.%GetIterator()
    While iter.%GetNext(, .row) { Set text = text _ $SELECT(text = "": "", 1: ",") _ row.controlId }
    Quit text
}

}
