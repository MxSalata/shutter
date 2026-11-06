/// A host with no message and no session that raises an alert when told to, as a site's own housekeeping job does. Set
/// ^OraSite.Say to the number of alerts wanted.
Class OraSite.Say Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    If $GET(^OraSite.Say) > 0 {
        Set ^OraSite.Say = ^OraSite.Say - 1
        Do ..SendAlert(##class(Ens.AlertRequest).%New($LISTBUILD(..%ConfigName, "Rig housekeeping alert, about no message")))
    }
    Quit $$$OK
}

}
