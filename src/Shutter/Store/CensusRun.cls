/// One run of the failure coverage census (docs/CONTRACTS.md, section 15): its scope, window, what could be read and what it found.
/// Its rows are Shutter.Store.CensusItem. Written only by the census, and it holds no message content.
Class Shutter.Store.CensusRun Extends %Persistent
{

/// Public identifier, FC-000001.
Property RunId As %String(MAXLEN = 32) [ Required ];

Index RunIdIdx On RunId [ Unique ];

/// The receiver as the site profile names it.
Property Receiver As %String(MAXLEN = 128);

/// The watched namespace, and the item there that delivers to the receiver.
Property Namespace As %String(MAXLEN = 64);

Property Item As %String(MAXLEN = 128);

/// The period, ISO UTC, from inclusive and to exclusive.
Property FromUTC As %String(MAXLEN = 30);

Property ToUTC As %String(MAXLEN = 30);

/// When the source was read: a header's status is as it stood then.
Property CutoffUTC As %String(MAXLEN = 30);

Property RequestedBy As %String(MAXLEN = 160);

Property StartedAt As %String(MAXLEN = 30);

Index StartedIdx On StartedAt;

Property FinishedAt As %String(MAXLEN = 30);

/// ok or unavailable.
Property SourceRead As %String(MAXLEN = 16);

Property SourceError As %String(MAXLEN = 400);

/// complete, incomplete (a cap, a purge or something still settling) or unknown (the source could not be read).
Property Completeness As %String(MAXLEN = 16);

/// The reason codes, a JSON array.
Property ReasonsJson As %String(MAXLEN = 2000);

/// Headers read, and whether the cap stopped the read; "" when the source could not be read.
Property Scanned As %Integer;

Property Truncated As %Boolean [ InitialExpression = 0 ];

Property MaxHeaders As %Integer;

/// The site profile's version and Shutter's, for the record.
Property ConfigVersion As %String(MAXLEN = 16);

Property ProductVersion As %String(MAXLEN = 16);

/// The totals, a JSON object; "" when the source could not be read.
Property TotalsJson As %String(MAXLEN = 4000);

/// A new run, saved, with its next public id.
ClassMethod Begin(receiver As %String, ns As %String, item As %String, from As %String, to As %String, user As %String, maxHeaders As %Integer, Output sc As %Status) As Shutter.Store.CensusRun
{
    Set run = ..%New()
    Set run.RunId = "FC-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Shutter.Census("seq")), 6), " ", "0")
    Set run.Receiver = receiver, run.Namespace = ns, run.Item = item, run.FromUTC = from, run.ToUTC = to, run.RequestedBy = user
    Set run.MaxHeaders = maxHeaders, run.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    Set run.Completeness = "unknown", run.SourceRead = "unavailable"
    Set sc = run.%Save()
    Quit run
}

ClassMethod ByRunId(runId As %String) As Shutter.Store.CensusRun
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Store.CensusRun WHERE RunId = :runId)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// A run and its rows.
ClassMethod Remove(runId As %String) As %Status
{
    Set run = ..ByRunId(runId)
    If '$ISOBJECT(run) Quit $$$OK
    Set id = run.%Id()
    &sql(DELETE FROM Shutter_Store.CensusItem WHERE Run = :id)
    Quit ..%DeleteId(id)
}

/// Takes away the runs started more than this many days ago; how many went.
ClassMethod PurgeOlder(days As %Integer) As %Integer
{
    Set cutoff = ##class(Shutter.Util.Time).FromNow(-86400 * days), n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT RunId FROM Shutter_Store.CensusRun WHERE StartedAt < ?", cutoff)
    While rs.%Next() {
        If $$$ISOK(..Remove(rs.%Get("RunId"))) Set n = n + 1
    }
    Quit n
}

Storage Default
{
<Data name="CensusRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RunId</Value>
</Value>
<Value name="3">
<Value>Receiver</Value>
</Value>
<Value name="4">
<Value>Namespace</Value>
</Value>
<Value name="5">
<Value>Item</Value>
</Value>
<Value name="6">
<Value>FromUTC</Value>
</Value>
<Value name="7">
<Value>ToUTC</Value>
</Value>
<Value name="8">
<Value>CutoffUTC</Value>
</Value>
<Value name="9">
<Value>RequestedBy</Value>
</Value>
<Value name="10">
<Value>StartedAt</Value>
</Value>
<Value name="11">
<Value>FinishedAt</Value>
</Value>
<Value name="12">
<Value>SourceRead</Value>
</Value>
<Value name="13">
<Value>SourceError</Value>
</Value>
<Value name="14">
<Value>Completeness</Value>
</Value>
<Value name="15">
<Value>ReasonsJson</Value>
</Value>
<Value name="16">
<Value>Scanned</Value>
</Value>
<Value name="17">
<Value>Truncated</Value>
</Value>
<Value name="18">
<Value>MaxHeaders</Value>
</Value>
<Value name="19">
<Value>ConfigVersion</Value>
</Value>
<Value name="20">
<Value>ProductVersion</Value>
</Value>
<Value name="21">
<Value>TotalsJson</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.CensusRunD</DataLocation>
<DefaultData>CensusRunDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CensusRunD</IdLocation>
<IndexLocation>^Shutter.Store.CensusRunI</IndexLocation>
<StreamLocation>^Shutter.Store.CensusRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
