/// One entry in a case's timeline: a state change, a note, an artefact reference or an error.
/// Append-only.
Class Shutter.Store.CaseEvent Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index CaseSeqIdx On (Case, Seq) [ Unique ];

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 16, VALUELIST = ",state,note,artifact,error,approval,execution,escalation");

Property FromState As %String(%JSONFIELDNAME = "fromState", MAXLEN = 32);

Property ToState As %String(%JSONFIELDNAME = "toState", MAXLEN = 32);

Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = 4000);

/// What the entry refers to: plan:<id>, snapshot:<id>, run:<id>, approval:<id>, ens:<header id>, escalation:<seq>, task:<id>.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 200);

Property Actor As %String(%JSONFIELDNAME = "actor", MAXLEN = 100);

/// Append an entry for a case. Called inside the case's own transaction. The case is referred to by its id, so saving
/// the entry never saves the caller's copy of the case with it.
ClassMethod Append(case As Shutter.Store.Case, kind As %String, fromState As %String, toState As %String, text As %String, actor As %String = "system", ref As %String = "") As %Status
{
    Set ev = ..%New()
    Do ev.CaseSetObjectId(case.%Id())
    Set ev.Seq = $INCREMENT(^Shutter.Counter("event", case.%Id()))
    Set ev.At = ##class(Shutter.Util.Time).NowUTCms()
    Set ev.Kind = kind
    Set ev.FromState = fromState
    Set ev.ToState = toState
    Set ev.Text = $EXTRACT(text, 1, 4000)
    Set ev.Actor = actor
    Set ev.Ref = ref
    Quit ev.%Save()
}

Storage Default
{
<Data name="CaseEventDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Seq</Value>
</Value>
<Value name="4">
<Value>At</Value>
</Value>
<Value name="5">
<Value>Kind</Value>
</Value>
<Value name="6">
<Value>FromState</Value>
</Value>
<Value name="7">
<Value>ToState</Value>
</Value>
<Value name="8">
<Value>Text</Value>
</Value>
<Value name="9">
<Value>Ref</Value>
</Value>
<Value name="10">
<Value>Actor</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.CaseEventD</DataLocation>
<DefaultData>CaseEventDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CaseEventD</IdLocation>
<IndexLocation>^Shutter.Store.CaseEventI</IndexLocation>
<StreamLocation>^Shutter.Store.CaseEventS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
