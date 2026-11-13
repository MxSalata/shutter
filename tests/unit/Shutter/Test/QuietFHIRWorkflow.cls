/// The case workflow with every send taken away, for tests that drive a FHIR case's flow on an instance outside the
/// production, where a send would be a runtime error in the Event Log. The flow (Shutter.FHIR.Flow) sends only
/// through FHIRSend, which here keeps what it was given instead:
/// <ul>
/// <li><property>Sent</property>: <code>Sent(n) = $LISTBUILD(target, class of the request, key, description)</code>
/// for the n-th send, <code>Sent</code> itself the count; <property>Requests</property> holds the request objects in
/// the same order.</li>
/// <li><property>FailSend</property>, when set, is the error every send ends with.</li>
/// </ul>
/// The sends of the workflow's own path are counted and not made, so a test can say that a FHIR case never reached
/// them: <property>MainGates</property> (the gate), <property>MainVerifies</property> (the verifier),
/// <property>MainPreflights</property> (the read before a dispatch), <property>WardOperations</property> (a ward
/// operation built for a rehearsal or a write), <property>Boards</property> (a board convened) and
/// <property>Evidence</property> (a collection started, which still opens the next round).
Class Shutter.Test.QuietFHIRWorkflow Extends Shutter.Process.CaseWorkflow
{

Property Sent As %String [ MultiDimensional, Transient ];

Property Requests As list Of %Library.RegisteredObject [ Transient ];

Property FailSend As %String(MAXLEN = 400) [ Transient ];

Property MainGates As %Integer [ InitialExpression = 0, Transient ];

Property MainVerifies As %Integer [ InitialExpression = 0, Transient ];

Property MainPreflights As %Integer [ InitialExpression = 0, Transient ];

Property WardOperations As %Integer [ InitialExpression = 0, Transient ];

Property Boards As %Integer [ InitialExpression = 0, Transient ];

Property Evidence As %Integer [ InitialExpression = 0, Transient ];

Method FHIRSend(target As %String, request As %Library.Persistent, key As %String, description As %String = "") As %Status
{
    If ..FailSend '= "" Quit $$$ERROR($$$GeneralError, ..FailSend)
    Set n = $INCREMENT(i%Sent)
    Set i%Sent(n) = $LISTBUILD(target, $CLASSNAME(request), key, description)
    Do ..Requests.Insert(request)
    Quit $$$OK
}

/// The last send as "target|class|key", or "" when nothing was sent.
Method Last() As %String
{
    Set n = +$GET(i%Sent)
    If n = 0 Quit ""
    Quit $LISTTOSTRING($LIST(i%Sent(n), 1, 3), "|")
}

/// The request of the last send, or "".
Method LastRequest() As %Library.RegisteredObject
{
    Quit $SELECT(..Requests.Count() = 0: "", 1: ..Requests.GetAt(..Requests.Count()))
}

/// The keys of every send so far, in order, separated by spaces.
Method Keys() As %String
{
    Set out = ""
    For n = 1:1:+$GET(i%Sent) { Set out = out _ $SELECT(out = "": "", 1: " ") _ $LIST(i%Sent(n), 3) }
    Quit out
}

/// The classes of every request sent so far, each once, separated by spaces.
Method Classes() As %String
{
    Set out = ""
    For n = 1:1:+$GET(i%Sent) {
        Set class = $LIST(i%Sent(n), 2)
        If (" " _ out _ " ") '[ (" " _ class _ " ") Set out = out _ $SELECT(out = "": "", 1: " ") _ class
    }
    Quit out
}

Method SendGate(case As Shutter.Store.Case, stage As %String, key As %String) As %Status
{
    Set ..MainGates = ..MainGates + 1
    Quit $$$OK
}

Method SendVerify(case As Shutter.Store.Case) As %Status
{
    Set ..MainVerifies = ..MainVerifies + 1
    Quit $$$OK
}

Method SendPreflight(case As Shutter.Store.Case) As %Status
{
    Set ..MainPreflights = ..MainPreflights + 1
    Quit $$$OK
}

Method WardOperationFor(case As Shutter.Store.Case, plan As Shutter.Store.Plan, dryRun As %Boolean) As Shutter.Msg.WardOperation
{
    Set ..WardOperations = ..WardOperations + 1
    Quit ##super(case, plan, dryRun)
}

Method ConveneBoard(case As Shutter.Store.Case, summaryJSON As %String, byWhom As %String = "", mode As %String = "", Output convened As %Boolean) As %Status
{
    Set ..Boards = ..Boards + 1, convened = 0
    Quit $$$OK
}

Method StartEvidence(case As Shutter.Store.Case) As %Status
{
    Set ..Round = ..Round + 1, ..Evidence = ..Evidence + 1
    Quit case.Transition("collecting", "Collecting evidence", "system")
}

}
