/// Whether a case's source is proved (Shutter.Operation.Origin; CONTRACTS 11): an automatic release needs it, since the intake takes
/// whatever a holder of the forwarder's sign-in posts. The namespace is this one, so the "source" here is a pair of real headers.
Class Shutter.Test.Origin Extends %UnitTest.TestCase
{

Property Made As %List;

Method OnAfterAllTests() As %Status
{
    For i = 1:1:$LISTLENGTH(..Made) {
        Set h = ##class(Ens.MessageHeader).%OpenId($LIST(..Made, i))
        If $ISOBJECT(h) {
            Do ##class(EnsLib.HL7.Message).%DeleteId(h.MessageBodyId)
            Do ##class(Ens.MessageHeader).%DeleteId($LIST(..Made, i))
        }
    }
    Quit $$$OK
}

Method Header(text As %String, source As %String, target As %String, session As %String) As Ens.MessageHeader
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text)
    Do msg.%Save()
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SessionId = session, h.SourceConfigName = source, h.TargetConfigName = target
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = msg.%Id()
    Do h.%Save()
    Set ..Made = ..Made _ $LISTBUILD(h.%Id())
    Quit h
}

/// A case as the intake leaves it, unsaved: its source header is Shutter's stored copy, sent by the intake item.
Method Case(text As %String, namespace As %String, origin As %String, receiver As %String, kind As %String = "delivery_failed") As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.SourceHeaderId = ..Header(text, "Case Intake", "Case Intake Store", 999996000 + $RANDOM(900)).%Id()
    Set case.SourceNamespace = namespace, case.OriginHeaderId = origin, case.Receiver = receiver, case.FailureKind = kind
    Quit case
}

Method Text(control As %String = "UTO1", ward As %String = "WARD-A") As %String
{
    Quit "MSH|^~\&|PAS|HOSP|BED|HOSP|20261105000000||ADT^A02|" _ control _ "|P|2.5.1" _ $CHAR(13) _ "PID|1||MRN-UT-1^^^HOSP^MR" _ $CHAR(13) _ "PV1|1|I|" _ ward _ $CHAR(13)
}

Method TestWhatIsProved()
{
    Set o = "Shutter.Operation.Origin", session = 999995000 + $RANDOM(900)
    Set origin = ..Header(..Text(), "UT In", "UT Out", session).%Id()
    // A real forward: the header is there, its session went to the receiver, its message is the text received.
    Do $$$AssertEquals($CLASSMETHOD(o, "Problem", ..Case(..Text(), $NAMESPACE, origin, "UT Out")), "", "a real forward is proved")
    Do $$$AssertEquals($CLASSMETHOD(o, "Problem", ..Case(..Text(), $NAMESPACE, origin, "SITE UT Out")), "", "with the forwarder's prefix on the receiver's name too")
    // A header of a session that reached the receiver further on: a transform, a process that sends a ward operation.
    Set via = ..Header(..Text("UTO2"), "UT In", "UT Router", session + 1).%Id()
    Do ..Header(..Text("UTO3"), "UT Router", "UT Out", session + 1)
    Do $$$AssertEquals($CLASSMETHOD(o, "Problem", ..Case(..Text("UTO2"), $NAMESPACE, via, "UT Out")), "", "a session that reached the receiver from another header")
    Set why = $CLASSMETHOD(o, "Problem", ..Case(..Text(), $NAMESPACE, origin, "UT Other Out"))
    Do $$$AssertTrue(why [ "UT Other Out", "a session that sent nothing to that receiver: " _ why)
    Set why = $CLASSMETHOD(o, "Problem", ..Case(..Text(, "WARD-B"), $NAMESPACE, origin, "UT Out"))
    Do $$$AssertTrue(why [ "not the message", "a text that is not the header's message: " _ why)
    Set why = $CLASSMETHOD(o, "Problem", ..Case(..Text(), $NAMESPACE, "999999999", "UT Out"))
    Do $$$AssertTrue(why [ "999999999", "a header that is not there: " _ why)
    Set why = $CLASSMETHOD(o, "Problem", ..Case(..Text(), $NAMESPACE, "", "UT Out"))
    Do $$$AssertTrue(why '= "", "no header named: " _ why)
    Set why = $CLASSMETHOD(o, "Problem", ..Case(..Text(), "UTNOSUCHNAMESPACE", origin, "UT Out"))
    Do $$$AssertTrue(why [ "UTNOSUCHNAMESPACE", "a namespace that cannot be read: " _ why)
    Set why = $CLASSMETHOD(o, "Problem", ..Case(..Text(), "", "", "UT Out"))
    Do $$$AssertTrue(why '= "", "the intake with no source named: " _ why)
    // A message the service held never went to its receiver: the header and the text prove it.
    Set held = ..Header(..Text("UTO4"), "UT In", "UT Forwarder", session + 2).%Id()
    Do $$$AssertEquals($CLASSMETHOD(o, "Problem", ..Case(..Text("UTO4"), $NAMESPACE, held, "UT Out", "unreadable")), "", "a held message goes to its forwarder")
}

Method TestTheFeedsOwnCasesNeedNoProof()
{
    Set o = "Shutter.Operation.Origin"
    Set case = ##class(Shutter.Store.Case).%New()
    Do $$$AssertEquals($CLASSMETHOD(o, "Problem", case), "", "no intake header: the feed's own, or nothing to prove")
    Set case.SourceHeaderId = ..Header(..Text("UTO5"), "PAS In", "PAS Router", 999994000 + $RANDOM(900)).%Id()
    Do $$$AssertEquals($CLASSMETHOD(o, "Problem", case), "", "a header the intake did not send")
    Set case.SourceHeaderId = "999999998"
    Do $$$AssertTrue($CLASSMETHOD(o, "Problem", case) '= "", "a header that is gone is not proof")
}

/// A site whose forwarder is on another instance can say so: the profile's feed.prove_origin false, true by default.
Method TestASiteCanTurnItOff()
{
    Set o = "Shutter.Operation.Origin", sp = "Shutter.Store.SiteProfile"
    Set case = ..Case(..Text(), "UTNOSUCHNAMESPACE", "1", "UT Out")
    Do $$$AssertEquals($CLASSMETHOD(sp, "ProveOrigin", {"feed": {}}), 1, "on by default")
    Do $$$AssertEquals($CLASSMETHOD(sp, "ProveOrigin", {}), 1, "and with no feed section")
    Set off = {"feed": {}}
    Do off.feed.%Set("prove_origin", 0, "boolean")
    Do $$$AssertEquals($CLASSMETHOD(sp, "ProveOrigin", off), 0, "off when the profile says so")
    Do $$$AssertEquals($CLASSMETHOD(o, "Problem", case, off), "", "and nothing is asked")
    Do $$$AssertTrue($CLASSMETHOD(o, "Problem", case, {"feed": {}}) '= "", "on, the same case is not proved")
    Set p = $CLASSMETHOD(sp, "Default")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "", "the default is valid")
    Do p.feed.%Set("prove_origin", 0, "boolean")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "", "and so is the setting")
    Set p.feed."prove_origin" = "yes"
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "feed.prove_origin: must be true or false", "a word is refused")
}

}
