/// The rig's stand-in for a hospital's own alert consumer: it counts what it is given, so the check can see that every
/// alert still reaches it once Shutter's alert intake holds the name Ens.Alert.
Class OnbSite.AlertLog Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnAlert(request As Ens.AlertRequest, Output response As Ens.Response) As %Status
{
    Set ^OnbSite.Alerts = $GET(^OnbSite.Alerts) + 1
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.AlertRequest"><Method>OnAlert</Method></MapItem>
</MapItems>
}

}
