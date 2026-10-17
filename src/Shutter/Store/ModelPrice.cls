/// Prices per million tokens, used to estimate the cost of each run. The seeded figures are the
/// provider's published list prices on the date in AsOf; check them against the provider's price
/// page when a model is chosen.
Class Shutter.Store.ModelPrice Extends (%Persistent, %JSON.Adaptor)
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

ClassMethod ByModel(model As %String) As Shutter.Store.ModelPrice
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Store.ModelPrice WHERE Model = :model)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// Seed the list prices: Anthropic's pricing page, read on 16 October 2026, per million tokens. Cache reads are
/// a twentieth of the input rate on Opus 5.5 and Sonnet 5.5 (0.20 and 0.10) and a tenth on the others; five-minute
/// cache writes are a quarter more than input. A row from an earlier seed is brought up to date; a row edited by
/// hand (another Source) is left alone.
ClassMethod Seed() As %Status
{
    Set sc = $$$OK
    Set asOf = "2026-10-16", source = "Anthropic list prices per million tokens, from the pricing page read on " _ asOf _ " (seed 3)"
    // model, input, output, cache read, five-minute cache write
    Set rows = [
        ["claude-opus-5-5", 4, 20, 0.2, 5],
        ["claude-sonnet-5-5", 2, 10, 0.1, 2.5],
        ["claude-haiku-5-5", 0.1, 0.5, 0.01, 0.125],
        ["claude-sonnet-4-6", 3, 15, 0.3, 3.75]
    ]
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .r) {
        Set p = ..ByModel(r.%Get(0))
        If $ISOBJECT(p) {
            Continue:(p.Source '[ "Anthropic list prices")
            Continue:(p.Source = source)
        } Else {
            Set p = ..%New()
            Set p.Model = r.%Get(0)
        }
        Set p.InputPerMTok = r.%Get(1), p.OutputPerMTok = r.%Get(2)
        Set p.CacheReadPerMTok = r.%Get(3), p.CacheWritePerMTok = r.%Get(4)
        Set p.Source = source, p.AsOf = asOf
        Set sc = p.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

Storage Default
{
<Data name="ModelPriceDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Model</Value>
</Value>
<Value name="3">
<Value>InputPerMTok</Value>
</Value>
<Value name="4">
<Value>OutputPerMTok</Value>
</Value>
<Value name="5">
<Value>CacheReadPerMTok</Value>
</Value>
<Value name="6">
<Value>CacheWritePerMTok</Value>
</Value>
<Value name="7">
<Value>Currency</Value>
</Value>
<Value name="8">
<Value>Source</Value>
</Value>
<Value name="9">
<Value>AsOf</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ModelPriceD</DataLocation>
<DefaultData>ModelPriceDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ModelPriceD</IdLocation>
<IndexLocation>^Shutter.Store.ModelPriceI</IndexLocation>
<StreamLocation>^Shutter.Store.ModelPriceS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
