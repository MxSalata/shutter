/// The rig's stand-in for a hospital's own alert consumer: it counts what it is given, so a check can see that an alert really
/// fired and still reaches it once Shutter's alert intake holds the name Ens.Alert.
Class V11Rig.AlertLog Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnAlert(request As Ens.AlertRequest, Output response As Ens.Response) As %Status
{
    Set ^V11Rig.Alerts = $GET(^V11Rig.Alerts) + 1
    Set ^V11Rig.Alerts(^V11Rig.Alerts) = request.SourceConfigName _ " | " _ $EXTRACT(request.AlertText, 1, 160)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.AlertRequest"><Method>OnAlert</Method></MapItem>
</MapItems>
}

}
