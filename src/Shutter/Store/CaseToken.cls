/// The per-case tokens that stand in for a patient's and an encounter's identifiers in everything that leaves IRIS
/// for a model (T27): MRN, NHS number, other patient identifiers, encounter ids and visit numbers. A token is
/// <KIND>-T<n>, numbered per kind in the order the values were first seen for the case, so the same fixture gives the
/// same tokens in every run and a recorded answer maps back in a later run. The map never leaves IRIS.
Class Shutter.Store.CaseToken Extends %Persistent
{

Property Case As Shutter.Store.Case [ Required ];

/// MRN, NHS, PID (another patient identifier), ENC (an encounter id), VISIT (a visit number), NAME (a name part from
/// PID-5) or DOB (the date of birth, as written and as ISO), so a name or a birth date in free text or an error echo is
/// replaced as well.
Property Kind As %String(MAXLEN = 8) [ Required ];

Property Seq As %Integer [ Required ];

Property Token As %String(MAXLEN = 24) [ Required ];

Property Value As %String(MAXLEN = 200) [ Required ];

Index CaseValue On (Case, Value) [ Unique ];

Index CaseToken On (Case, Token) [ Unique ];

/// The token for a value of the case, made on first sight. A value already mapped keeps its token whatever kind is
/// asked now (an encounter id that is also the visit number is one token). "" for a value Accepts refuses, or when
/// the token could not be stored.
ClassMethod Assign(case As Shutter.Store.Case, kind As %String, value As %String) As %String
{
    Set value = $ZSTRIP(value, "<>W")
    If '..Accepts(kind, value) || '$ISOBJECT(case) Quit ""
    Set cid = case.%Id(), token = ""
    &sql(SELECT Token INTO :token FROM Shutter_Store.CaseToken WHERE "Case" = :cid AND Value = :value)
    If (SQLCODE = 0) && (token '= "") Quit token
    // One writer at a time per case: the count and the save are one step.
    LOCK +^Shutter.CaseToken(cid):10
    If '$TEST Quit ""
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.CaseToken WHERE "Case" = :cid AND Kind = :kind)
    &sql(SELECT Token INTO :token FROM Shutter_Store.CaseToken WHERE "Case" = :cid AND Value = :value)
    If (SQLCODE = 0) && (token '= "") { LOCK -^Shutter.CaseToken(cid) Quit token }
    Set t = ..%New()
    // By id, not the caller's copy, as Snapshot.Begin does: a save of the token never writes the case whole.
    Do t.CaseSetObjectId(cid)
    Set t.Kind = kind, t.Seq = +n + 1, t.Token = kind _ "-T" _ (+n + 1), t.Value = value
    Set sc = t.%Save()
    LOCK -^Shutter.CaseToken(cid)
    If $$$ISERR(sc) Quit ""
    Quit t.Token
}

/// Whether a value takes a token: three characters or more, two for a name part (a surname such as Li or Ng), and not
/// a value that itself looks like a token, which could not be told from one on the way back.
ClassMethod Accepts(kind As %String, value As %String) As %Boolean
{
    Set value = $ZSTRIP(value, "<>W")
    If $LENGTH(value) < $SELECT(kind = "NAME": 2, 1: 3) Quit 0
    If $MATCH(value, "^(MRN|NHS|PID|ENC|VISIT|NAME|DOB)-T[0-9]+$") Quit 0
    Quit 1
}

/// Every token of the case, as a list of $LISTBUILD(token, value, kind), longest value first (so a value that is a
/// prefix of another is replaced after it).
ClassMethod Map(case As Shutter.Store.Case) As %List
{
    Set out = "", cid = case.%Id()
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Token, Value, Kind FROM Shutter_Store.CaseToken WHERE ""Case"" = ? ORDER BY LENGTH(Value) DESC, Token", cid)
    While rs.%Next() { Set out = out _ $LISTBUILD($LISTBUILD(rs.%Get("Token"), rs.%Get("Value"), rs.%Get("Kind"))) }
    Quit out
}

/// The map as the app shows it to a person (inside IRIS): token, kind and value.
ClassMethod ForCase(case As Shutter.Store.Case) As %DynamicArray
{
    Set out = [], map = ..Map(case)
    For i = 1:1:$LISTLENGTH(map) {
        Set e = $LIST(map, i)
        Do out.%Push({"token": ($LIST(e, 1)), "kind": ($LIST(e, 3)), "value": ($LIST(e, 2))})
    }
    Quit out
}

Storage Default
{
<Data name="CaseTokenDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Kind</Value>
</Value>
<Value name="4">
<Value>Seq</Value>
</Value>
<Value name="5">
<Value>Token</Value>
</Value>
<Value name="6">
<Value>Value</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.CaseTokenD</DataLocation>
<DefaultData>CaseTokenDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CaseTokenD</IdLocation>
<IndexLocation>^Shutter.Store.CaseTokenI</IndexLocation>
<StreamLocation>^Shutter.Store.CaseTokenS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
