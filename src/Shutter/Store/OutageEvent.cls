/// One thing that happened to a receiver's outage: it opened, its kind changed, a person paused or closed it. Append only.
Class Shutter.Store.OutageEvent Extends %Persistent
{

Property OutageId As %String(MAXLEN = 20) [ Required ];

Index OutageIdx On OutageId;

Property EventAt As %String(MAXLEN = 30);

/// opened, kind, paused or closed; a later writer adds its own word.
Property Kind As %String(MAXLEN = 32);

Property Detail As %String(MAXLEN = 2000);

/// The person who acted, or the item that did.
Property Actor As %String(MAXLEN = 128);

/// Writes one event. A failure is the caller's to report.
ClassMethod Add(outageId As %String, kind As %String, detail As %String = "", by As %String = "") As %Status
{
    Set e = ..%New()
    Set e.OutageId = outageId, e.EventAt = ##class(Shutter.Util.Time).NowUTC(), e.Kind = kind
    Set e.Detail = $EXTRACT(detail, 1, 2000), e.Actor = by
    Quit e.%Save()
}

/// An outage's events, oldest first: [ { "at", "kind", "detail", "by" } ].
ClassMethod Of(outageId As %String) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT EventAt, Kind, Detail, Actor FROM Shutter_Store.OutageEvent WHERE OutageId = ? ORDER BY ID", outageId)
    While rs.%Next() {
        Do out.%Push({"at": (rs.%Get("EventAt")), "kind": (rs.%Get("Kind")), "detail": (rs.%Get("Detail")), "by": (rs.%Get("Actor"))})
    }
    Quit out
}

}
