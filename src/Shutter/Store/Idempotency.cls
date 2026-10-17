/// Replies to idempotent API requests, kept for a day: the same key with the same body gets the
/// first reply again; the same key with another body is refused.
Class Shutter.Store.Idempotency Extends %Persistent
{

Property Key As %String(MAXLEN = 200) [ Required ];

Index KeyIdx On Key [ Unique ];

Property BodyDigest As %String(MAXLEN = 80);

Property Status As %String(MAXLEN = 20);

Property Response As %String(MAXLEN = "");

Property CreatedAt As %String(MAXLEN = 30);

/// Look up a key. Returns 1 with the stored reply when it matches, 0 when it is new, and -1 when
/// the key was used with another body.
ClassMethod Lookup(key As %String, bodyDigest As %String, Output status As %String, Output response As %String) As %Integer
{
    Set status = "", response = ""
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Store.Idempotency WHERE "Key" = :key)
    If (SQLCODE '= 0) || (id = "") Quit 0
    Set r = ..%OpenId(id)
    If '$ISOBJECT(r) Quit 0
    If r.BodyDigest '= bodyDigest Quit -1
    Set status = r.Status, response = r.Response
    Quit 1
}

ClassMethod Store(key As %String, bodyDigest As %String, status As %String, response As %String) As %Status
{
    Set r = ..%New()
    Set r.Key = key, r.BodyDigest = bodyDigest, r.Status = status, r.Response = response
    Set r.CreatedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit r.%Save()
}

/// Remove entries older than a day.
ClassMethod Purge() As %Integer
{
    Set cutoff = ##class(Shutter.Util.Time).FromNow(-86400)
    &sql(DELETE FROM Shutter_Store.Idempotency WHERE CreatedAt < :cutoff)
    Quit $SELECT(SQLCODE = 0: %ROWCOUNT, 1: 0)
}

Storage Default
{
<Data name="IdempotencyDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Key</Value>
</Value>
<Value name="3">
<Value>BodyDigest</Value>
</Value>
<Value name="4">
<Value>Status</Value>
</Value>
<Value name="5">
<Value>Response</Value>
</Value>
<Value name="6">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.IdempotencyD</DataLocation>
<DefaultData>IdempotencyDefaultData</DefaultData>
<IdLocation>^Shutter.Store.IdempotencyD</IdLocation>
<IndexLocation>^Shutter.Store.IdempotencyI</IndexLocation>
<StreamLocation>^Shutter.Store.IdempotencyS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
