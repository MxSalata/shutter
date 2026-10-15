/// Replies to idempotent API requests, kept for a day: the same key with the same body gets the
/// first reply again; the same key with another body is refused.
Class Interlock.Store.Idempotency Extends %Persistent
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
    &sql(SELECT ID INTO :id FROM Interlock_Store.Idempotency WHERE "Key" = :key)
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
    Set r.CreatedAt = ##class(Interlock.Util.Time).NowUTC()
    Quit r.%Save()
}

/// Remove entries older than a day.
ClassMethod Purge() As %Integer
{
    Set cutoff = ##class(Interlock.Util.Time).FromNow(-86400)
    &sql(DELETE FROM Interlock_Store.Idempotency WHERE CreatedAt < :cutoff)
    Quit $SELECT(SQLCODE = 0: %ROWCOUNT, 1: 0)
}

}
