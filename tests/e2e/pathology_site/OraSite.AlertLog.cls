/// The rig's stand-in for a hospital's own alert consumer: it counts what it is given, so the check can see that an alert
/// really fired and still reaches it once Shutter's alert intake holds the name Ens.Alert. With ^OraSite.AlertFail set its
/// work fails, as a site's does when its mail server is down.
Class OraSite.AlertLog Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnAlert(request As Ens.AlertRequest, Output response As Ens.Response) As %Status
{
    Set ^OraSite.Alerts = $GET(^OraSite.Alerts) + 1
    Set ^OraSite.Alerts(^OraSite.Alerts) = request.SourceConfigName _ " | " _ $EXTRACT(request.AlertText, 1, 160)
    Quit $SELECT($GET(^OraSite.AlertFail): $$$ERROR($$$GeneralError, "SMTP is down"), 1: $$$OK)
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.AlertRequest"><Method>OnAlert</Method></MapItem>
</MapItems>
}

}
