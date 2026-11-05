/// Onboarding a namespace (Shutter.Util.Onboard; CONTRACTS 11.1, v1.42): the plan changes nothing and says what it would do,
/// a receiver keeps apart from another namespace's of the same name, a site's unnamed receiver has no API, the schema's
/// local name, a forward naming a category not loaded here, a test forward's advice, and the guard on a live namespace.
/// tests/e2e/onboard_check.py plays the whole of it on real productions.
Class Shutter.Test.Onboard Extends %UnitTest.TestCase
{

Parameter NS = "ONBTESTNS";

Method OnAfterAllTests() As %Status
{
    Kill ^Shutter.Config("onboard", ..#NS), ^Shutter.Config("schemaAlias", ..#NS), ^Shutter.Config("schemaNamed", "ONBNOSUCH")
    Quit $$$OK
}

Method TestReadOfANamespaceThatIsNotThere()
{
    Set r = ##class(Shutter.Util.Onboard).Read(..#NS)
    Do $$$AssertEquals(r.exists, 0, "a namespace that is not there")
    Do $$$AssertTrue(r.error [ "No namespace", "says so: " _ r.error)
    Set p = ##class(Shutter.Util.Onboard).Plan(..#NS)
    Do $$$AssertTrue(p.error [ "No namespace", "the plan carries it: " _ p.error)
    Do $$$AssertEquals(p.actions.%Size(), 0, "and proposes nothing")
    Set e = ##class(Shutter.Util.Onboard).Read("")
    Do $$$AssertTrue(e.error [ "No namespace", "an empty name too")
}

/// Shutter's own namespace has nothing to onboard, and a plan there changes nothing.
Method TestPlanRefusesShuttersOwnNamespaceAndChangesNothing()
{
    Set before = $GET(^Shutter.Config("schemaEpoch")) _ "|" _ $DATA(^Shutter.Config("onboard", $NAMESPACE))
    Set p = ##class(Shutter.Util.Onboard).Plan($NAMESPACE)
    Do $$$AssertTrue(p.error [ "own namespace", "the plan says so: " _ p.error)
    Do $$$AssertEquals(p.actions.%Size(), 0, "and proposes nothing")
    Do $$$AssertEquals($GET(^Shutter.Config("schemaEpoch")) _ "|" _ $DATA(^Shutter.Config("onboard", $NAMESPACE)), before, "and nothing moved")
}

Method TestSqlFormsAnswerJson()
{
    Set p = ##class(%DynamicObject).%FromJSON(##class(Shutter.Setup).OnboardPlan(..#NS, $CHAR(0)))
    Do $$$AssertEquals(p.namespace, ..#NS, "SQL's empty argument is no option")
    Set o = ##class(Shutter.Util.Onboard).Options("not json")
    Do $$$AssertEquals(o.%Size(), 0, "options that do not parse are none")
    Do $$$AssertEquals(##class(Shutter.Util.Onboard).NS(" pathology "_$CHAR(0)), "PATHOLOGY", "a namespace's name is trimmed and upper case")
}

/// The plan's line on what a completed message proves, from the settings that apply (measured in the e2e).
Method TestCompletedProves()
{
    Set o = "Shutter.Util.Onboard", stock = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C"
    Do $$$AssertTrue($CLASSMETHOD(o, "CompletedProves", 1, stock) [ "any positive code counts as complete", "the stock codes: CA reads as AA")
    Do $$$AssertTrue($CLASSMETHOD(o, "CompletedProves", 0, stock) [ "Nothing is awaited", "GetReply off, whatever the codes")
    Do $$$AssertTrue($CLASSMETHOD(o, "CompletedProves", "", stock) [ "GetReply does not apply", "an adapter without the setting")
    Do $$$AssertTrue($CLASSMETHOD(o, "CompletedProves", 1, ":AA=C,:CA=S,:?R=RF,:?E=S,:*=S") [ "only AA completes (CA=S)", "CA set not to complete")
    Set lenient = $CLASSMETHOD(o, "CompletedProves", 1, ":?A=C,:?E=C,:?R=S")
    Do $$$AssertTrue((lenient [ "negative code") && (lenient [ "AE=C") && (lenient [ "CE=C"), "a NACK that completes is named: " _ lenient)
    Do $$$AssertTrue($CLASSMETHOD(o, "CompletedProves", 1, ":*=S") [ "neither AA nor CA completes", "nothing positive completes")
}

/// A name another namespace holds is taken, and so is one a person gave an API with no namespace.
Method TestReceiverNameTakenElsewhere()
{
    Set onb = "Shutter.Util.Onboard"
    Do $$$AssertEquals($CLASSMETHOD(onb, "TakenElsewhere", "OTHERNS", "Onboard Unit Out"), 0, "a free name")
    Set ^Shutter.Config("onboard", ..#NS, "receivers", "Onboard Unit Out") = "Onboard Unit Out"
    Do $$$AssertEquals($CLASSMETHOD(onb, "TakenElsewhere", "OTHERNS", "Onboard Unit Out"), 1, "taken by another namespace")
    Do $$$AssertEquals($CLASSMETHOD(onb, "TakenElsewhere", ..#NS, "Onboard Unit Out"), 0, "not by its own")
    Kill ^Shutter.Config("onboard", ..#NS)
    Set shipped = $PARAMETER("Shutter.Production", "RECEIVER")
    Do $$$AssertEquals($CLASSMETHOD(onb, "TakenElsewhere", "OTHERNS", shipped), 1, "an entry with an API and no namespace is nobody's to share")
}

Method TestReportedReceiver()
{
    Set f = "Shutter.Intake.Forwarder"
    Do $$$AssertEquals($CLASSMETHOD(f, "ReportedReceiver", "Results Out", ""), "Results Out", "no prefix: the item's name")
    Do $$$AssertEquals($CLASSMETHOD(f, "ReportedReceiver", "Results Out", "DOCUMENTS"), "DOCUMENTS Results Out", "with the namespace in front")
    Do $$$AssertEquals($CLASSMETHOD(f, "ReportedReceiver", "", "DOCUMENTS"), "", "an empty receiver stays empty: Shutter's connector item")
}

/// A site's receiver its profile does not name reads nothing, and claims nothing: the defaults are the demo's. A demo's keeps them.
Method TestAnUnnamedReceiverOnASiteHasNoApi()
{
    Set sp = "Shutter.Store.SiteProfile", keep = $GET(^Shutter.Config("demo"))
    Try {
        Set ^Shutter.Config("demo") = 0
        Do $$$AssertEquals($CLASSMETHOD(sp, "ReceiverPath", "Nobody Out", "state", "E1"), "", "a site: no path")
        Set f = $CLASSMETHOD(sp, "ReceiverFeatures", "Nobody Out")
        Do $$$AssertEquals(f."conditional_writes" _ f.receipts _ f.history _ f."dry_run", "0000", "a site: no feature")
        Set ^Shutter.Config("demo") = 1
        Do $$$AssertTrue($CLASSMETHOD(sp, "ReceiverPath", "Nobody Out", "state", "E1") [ "/downstream/api", "the demo keeps its defaults")
        Set f = $CLASSMETHOD(sp, "ReceiverFeatures", "Nobody Out")
        Do $$$AssertEquals(f."conditional_writes", 1, "and its features")
    } Catch ex {
        Do $$$AssertTrue(0, ex.DisplayString())
    }
    If keep = "" { Kill ^Shutter.Config("demo") } Else { Set ^Shutter.Config("demo") = keep }
}

Method TestSchemaLocalName()
{
    Set s = "Shutter.Util.Schemas"
    Do $$$AssertEquals($CLASSMETHOD(s, "LocalName", ..#NS, "TRUSTLAB"), "TRUSTLAB", "no alias: its own name")
    Set ^Shutter.Config("schemaAlias", ..#NS, "TRUSTLAB") = "ONBTESTNS_TRUSTLAB"
    Do $$$AssertEquals($CLASSMETHOD(s, "LocalName", ..#NS, "TRUSTLAB"), "ONBTESTNS_TRUSTLAB", "the alias")
    Do $$$AssertEquals($CLASSMETHOD(s, "LocalName", "OTHERNS", "TRUSTLAB"), "TRUSTLAB", "only for that namespace")
    Do $$$AssertEquals($CLASSMETHOD(s, "LocalName", "", "TRUSTLAB"), "TRUSTLAB", "no namespace: its own name")
    Do $$$AssertEquals($CLASSMETHOD(s, "ImportNeeded", ..#NS, "TRUSTLAB", .as), "import_as", "an alias not loaded yet is still to import")
    Kill ^Shutter.Config("schemaAlias", ..#NS)
    Do $$$AssertEquals($CLASSMETHOD(s, "ImportNeeded", "", "2.5.1", .as), "none", "the same category here: nothing to do")
    Do $$$AssertEquals($CLASSMETHOD(s, "ImportNeeded", "", "ONBNOSUCH", .as), "import", "a free name is imported under itself")
    Do $$$AssertEquals(as, "ONBNOSUCH", "with that name")
}

/// An order, a result or a document that failed says what the receiver did, and never blames the message or a mapping; an
/// ADT message that really could not be mapped keeps those words.
Method TestAFailedOrderSaysWhatTheReceiverDid()
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.FailureKind = "unmappable", c.Event = "R01", c.EventTime = "2026-11-05T10:00:00Z", c.EncounterId = "ENC-1", c.Receiver = "Results Out"
    Set c.FailureText = "This message is ORU, not ADT: Shutter resends only ADT, so it sends nothing and a person decides. The source reported: Alert"
    Do $$$AssertTrue(c.NotModelled(), "the words mark it")
    Set d = "Shutter.Store.Case"
    Do $$$AssertTrue($CLASSMETHOD(d, "DescribeFailure", c) [ "failed at Results Out", "before the outcome is known it claims only that it failed")
    Set c.FailureOutcome = "error"
    Do $$$AssertTrue($CLASSMETHOD(d, "DescribeFailure", c) [ "was not delivered to Results Out", "a connection that never opened")
    Set c.FailureOutcome = "uncertain"
    Do $$$AssertTrue($CLASSMETHOD(d, "DescribeFailure", c) [ "may have reached Results Out", "a receiver that did not answer may hold it")
    Set c.FailureOutcome = "rejected"
    Do $$$AssertTrue($CLASSMETHOD(d, "DescribeFailure", c) [ "was refused by Results Out", "a refusal")
    Do $$$AssertTrue('($CLASSMETHOD(d, "DescribeFailure", c) [ "mapped"), "and no talk of a mapping")
    // A result with no PV1 has no encounter: no empty clause, in these words or in the others.
    Set c.EncounterId = ""
    Do $$$AssertNotTrue($CLASSMETHOD(d, "DescribeFailure", c) [ "for encounter", "no encounter, no clause: " _ $CLASSMETHOD(d, "DescribeFailure", c))
    Set c.FailureText = "x", c.Event = "transfer"
    Do $$$AssertNotTrue($CLASSMETHOD(d, "DescribeFailure", c) [ "for encounter", "nor here: " _ $CLASSMETHOD(d, "DescribeFailure", c))
    Set c.EncounterId = "ENC-1", c.Event = "R01"
    Set c.FailureText = "The message could not be mapped to an operation for the downstream system: no visit number"
    Do $$$AssertTrue('c.NotModelled(), "an ADT that could not be mapped is not this")
    Do $$$AssertTrue($CLASSMETHOD(d, "DescribeFailure", c) [ "could not be mapped", "and keeps its words")
}

/// A forward naming a category not loaded here says so on the stored copy, and the evidence reads that word; a loaded one
/// leaves no note.
Method TestAForwardNamingAnUnloadedCategory()
{
    Set s = "Shutter.Util.Schemas"
    Set text = "MSH|^~\&|LIMS|HOSP|ICE|HOSP|20261105010000||ORU^R01^ORU_R01|C1|P|2.5.1" _ $CHAR(13) _ "PID|1||M1^^^HOSP^MR||A^B" _ $CHAR(13)
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Do $$$AssertStatusOK(sc, "the message parses")
    Do $$$AssertEquals($CLASSMETHOD(s, "NamedUnloaded", msg, "2.5.1", ..#NS), 0, "a loaded category leaves no note")
    Do $$$AssertEquals($CLASSMETHOD(s, "NamedCategory", msg), "", "and none reads back")
    Do $$$AssertEquals($CLASSMETHOD(s, "NamedUnloaded", msg, "ONBNOSUCH", ..#NS), 1, "an unloaded one does")
    Do $$$AssertEquals($CLASSMETHOD(s, "NamedCategory", msg), "ONBNOSUCH", "under its name")
    Set ^Shutter.Config("schemaAlias", ..#NS, "ONBNOSUCH") = "ONBTESTNS_ONBNOSUCH"
    Do $$$AssertEquals($CLASSMETHOD(s, "NamedCategory", msg), "ONBTESTNS_ONBNOSUCH", "and an alias made since is followed")
    Kill ^Shutter.Config("schemaAlias", ..#NS)
    Do $$$AssertEquals(msg.DocType, "", "the note types nothing")
}

Method TestTestAdviceNamesWhatToCheck()
{
    Set onb = "Shutter.Util.Onboard"
    Do $$$AssertEquals($CLASSMETHOD(onb, "TestAdvice", 202), "", "taken: no advice")
    Do $$$AssertTrue($CLASSMETHOD(onb, "TestAdvice", 404, "ShutterIntake", "shutter-fwd") [ "password", "404 is a refused sign-in on a REST application")
    Do $$$AssertTrue($CLASSMETHOD(onb, "TestAdvice", 403, "ShutterIntake", "shutter-fwd") [ "Shutter_Forwarder", "403 is the role")
    Do $$$AssertTrue($CLASSMETHOD(onb, "TestAdvice", 503) [ "not running", "503 is the production")
    Do $$$AssertTrue($CLASSMETHOD(onb, "TestAdvice", "") [ "HTTPServer", "no answer is the address")
}

/// A running production of the site's refuses the install; Shutter's own, or a stopped one, does not.
Method TestLiveNamespaceGuard()
{
    Set st = "Shutter.Setup"
    Do $$$AssertTrue($CLASSMETHOD(st, "LiveNamespaceProblem", "Trust.Production", 1) [ "would stop it", "a site's running production")
    Do $$$AssertEquals($CLASSMETHOD(st, "LiveNamespaceProblem", "Shutter.Production", 1), "", "Shutter's own: an upgrade")
    Do $$$AssertEquals($CLASSMETHOD(st, "LiveNamespaceProblem", "Trust.Production", 2), "", "a stopped one stops nothing")
}

/// A connect that timed out sent nothing: a failed delivery, not an uncertain outcome. A response that timed out stays uncertain.
Method TestClassifyAConnectTimeout()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7201"), "delivery_failed", "a dead MLLP port")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Response timeout after 15 seconds"), "uncertain_outcome", "a response that never came")
}

/// The Doctor names the watched namespaces and the receivers with no connector, whatever the instance holds.
Method TestDoctorListsWatchedNamespaces()
{
    Set r = ##class(%DynamicObject).%FromJSON(##class(Shutter.Setup).Doctor())
    Do $$$AssertTrue(r.%IsDefined("watched_namespaces") && r."watched_namespaces".%IsA("%DynamicArray"), "the namespaces")
    Do $$$AssertTrue(r.%IsDefined("receivers_without_item"), "and the receivers")
    Set it = r."watched_namespaces".%GetIterator()
    While it.%GetNext(, .w) { Do $$$AssertTrue(w.%IsDefined("schemas_missing") && w.%IsDefined("ok"), "each says how it stands: " _ w.namespace) }
}

/// ReceiverItem refuses a receiver with no API: no connector, nothing recorded.
Method TestAReceiverItemNeedsAnApi()
{
    Set r = ##class(Shutter.Util.Onboard).ReceiverItem("Nobody Out")
    Do $$$AssertEquals(r.ok, 0, "refused")
    Do $$$AssertTrue(r.error [ "no API", "says why: " _ r.error)
    Do $$$AssertEquals($DATA(^Shutter.Config("receiverItems", "Nobody Out")), 0, "and nothing was recorded")
}

}
