/// The case page's routes for warehouse history (docs/warehouse-history.md), named by Shutter.API.Dispatch's URL map. They
/// take nothing from the caller but the case: the patient is the case's own, and the dataset is the administrator's.
Class Shutter.API.WarehouseHistory Extends Shutter.API.Dispatch
{

/// GET /cases/{id}/warehouse-history: {enabled, read}, the newest stored read or null. Off, it says only that.
ClassMethod HistoryGet(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set o = {"read": null}
    Do o.%Set("enabled", ##class(Shutter.Warehouse.Client).Enabled(), "boolean")
    If 'o.enabled Quit ..Json(o)
    Set read = ##class(Shutter.Store.WarehouseRead).Latest(case)
    If $ISOBJECT(read) Set o.read = read.View()
    Quit ..Json(o)
}

/// POST /cases/{id}/warehouse-history: read now, store it, and answer as the GET does. It changes nothing on the case.
ClassMethod HistoryRead(caseId As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    If '##class(Shutter.Warehouse.Client).Enabled() Quit ..Fail("409 Conflict", "warehouse_off", "Warehouse history is not switched on")
    Set read = ##class(Shutter.Warehouse.Client).ReadForCase(case, ..User())
    If '$ISOBJECT(read) Quit ..Fail("500 Internal Server Error", "not_stored", "The read could not be stored")
    Set o = {"read": (read.View())}
    Do o.%Set("enabled", 1, "boolean")
    Quit ..Json(o)
}

}
