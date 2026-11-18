/// The case workflow with every send kept instead of made, for the inbox approval tests (Shutter.Test.InboxApproval): an
/// instance outside the production, where a send would be a runtime error. <property>Requests</property> holds each
/// request sent and <property>Keys</property> each completion key, in order. Not a test case: the runner leaves it alone.
Class Shutter.Test.InboxWorkflow Extends Shutter.Test.QuietWorkflow
{

Property Requests As list Of %Library.RegisteredObject [ Transient ];

Property Keys As list Of %String(MAXLEN = 200) [ Transient ];

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As %Library.Persistent, pResponseRequired As %Boolean = 1, pCompletionKey As %String = "", pDescription As %String = "") As %Status
{
    Do ..Requests.Insert(pRequest)
    Do ..Keys.Insert(pCompletionKey)
    Quit $$$OK
}

/// The request sent under this completion key, the last one when there were several; "" when none was.
Method Sent(key As %String) As %Library.RegisteredObject
{
    For i = ..Keys.Count():-1:1 { If ..Keys.GetAt(i) = key Return ..Requests.GetAt(i) }
    Quit ""
}

}
