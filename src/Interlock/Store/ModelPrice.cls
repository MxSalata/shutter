/// Prices per million tokens, used to estimate the cost of each run. The seeded figures are the
/// provider's published list prices on the date in AsOf; check them against the provider's price
/// page when a model is chosen.
Class Interlock.Store.ModelPrice Extends (%Persistent, %JSON.Adaptor)
{

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100) [ Required ];

Index ModelIdx On Model [ Unique ];

Property InputPerMTok As %Numeric(%JSONFIELDNAME = "inputPerMTok", SCALE = 4);

Property OutputPerMTok As %Numeric(%JSONFIELDNAME = "outputPerMTok", SCALE = 4);

Property CacheReadPerMTok As %Numeric(%JSONFIELDNAME = "cacheReadPerMTok", SCALE = 4);

/// Blank means "billed as input".
Property CacheWritePerMTok As %Numeric(%JSONFIELDNAME = "cacheWritePerMTok", SCALE = 4);

Property Currency As %String(%JSONFIELDNAME = "currency", MAXLEN = 3) [ InitialExpression = "USD" ];

Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 200);

Property AsOf As %String(%JSONFIELDNAME = "asOf", MAXLEN = 30);

/// The estimated cost of a run in USD, or "" when the model has no price row.
ClassMethod Cost(model As %String, prompt As %Integer, completion As %Integer, cacheRead As %Integer = 0, cacheWrite As %Integer = 0) As %Numeric
{
    Set p = ..ByModel(model)
    If '$ISOBJECT(p) Quit ""
    Set prompt = +prompt, completion = +completion, cacheRead = +cacheRead, cacheWrite = +cacheWrite
    // Prompt tokens as reported include the cached ones on some providers and exclude them on
    // others; the bridge normalises them so that prompt excludes cache reads and writes.
    Set cost = (prompt * p.InputPerMTok) + (completion * p.OutputPerMTok) + (cacheRead * p.CacheReadPerMTok)
    Set cost = cost + (cacheWrite * $SELECT(p.CacheWritePerMTok = "": p.InputPerMTok, 1: p.CacheWritePerMTok))
    Quit $JUSTIFY(cost / 1000000, 0, 6)
}

ClassMethod ByModel(model As %String) As Interlock.Store.ModelPrice
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Interlock_Store.ModelPrice WHERE Model = :model)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// Seed the list prices known on 6 October 2026 (Anthropic's published rates). Cache-write
/// prices are left blank and billed as input until checked.
ClassMethod Seed() As %Status
{
    Set sc = $$$OK
    Set rows = [
        ["claude-opus-5-5", 4, 20, 0.2],
        ["claude-sonnet-5-5", 2, 10, 0.2],
        ["claude-haiku-5-5", 0.1, 0.5, ""],
        ["claude-sonnet-4-6", 3, 15, ""]
    ]
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .r) {
        Continue:$ISOBJECT(..ByModel(r.%Get(0)))
        Set p = ..%New()
        Set p.Model = r.%Get(0), p.InputPerMTok = r.%Get(1), p.OutputPerMTok = r.%Get(2)
        Set p.CacheReadPerMTok = r.%Get(3)
        Set p.Source = "Anthropic list prices, per million tokens, as published on 2026-10-06"
        Set p.AsOf = "2026-10-06"
        Set sc = p.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

}
