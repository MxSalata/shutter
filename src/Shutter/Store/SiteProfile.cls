/// The site profile: the questionnaire's answers (CONTRACTS 6.4), one current row, with the shipped defaults
/// when no profile has been given. Read by the case workflow (the policy path), the gate and the incident.
Class Shutter.Store.SiteProfile Extends (%Persistent, %JSON.Adaptor)
{

Property Name As %String(%JSONFIELDNAME = "name", MAXLEN = 32) [ InitialExpression = "current", Required ];

Index NameIdx On Name [ Unique ];

Property Version As %Integer(%JSONFIELDNAME = "version") [ InitialExpression = 1 ];

/// The profile as JSON (the shape in CONTRACTS 6.4).
Property Json As %String(%JSONFIELDNAME = "profile", MAXLEN = "");

Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 200);

Property UpdatedAt As %String(%JSONFIELDNAME = "updatedAt", MAXLEN = 30);

Property UpdatedBy As %String(%JSONFIELDNAME = "updatedBy", MAXLEN = 160);

/// The shipped defaults: one receiver (the ward, tier 2), keep what is current, no authoritative source,
/// unconditional resends forbidden, automatic single chains for tiers 1 and 2, approvals elsewhere.
ClassMethod Default() As %DynamicObject
{
    Set p = {}
    Set p.version = 0
    Set p.receivers = [{"name": "Ward Out", "system": "the ward bed-management system", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false}]
    Set p."history_policy" = "current"
    Set p."authoritative_source" = ""
    Set p."unconditional_resend" = "forbidden"
    Set p.policy = {"1": {"single": "automatic", "ordered": "automatic", "interleaved": "board"}, "2": {"single": "automatic", "ordered": "approval", "interleaved": "board"}, "3": {"single": "approval", "ordered": "per_chain", "interleaved": "board"}}
    Set p.approvers = {"role": "Shutter Approvers", "escalation": "the integration team's on-call"}
    Set p.incident = {"threshold": 5, "window_minutes": 10, "quiet_seconds": 60}
    Quit p
}

/// The current profile as a dynamic object (the stored one, else the defaults), with "version" set.
ClassMethod Current() As %DynamicObject
{
    Set row = ..Row()
    If $ISOBJECT(row) && (row.Json '= "") {
        Set p = ##class(Shutter.Util.Json).Parse(row.Json, .sc)
        If $ISOBJECT(p) Set p.version = row.Version Quit p
    }
    Quit ..Default()
}

ClassMethod Row() As Shutter.Store.SiteProfile
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Store.SiteProfile WHERE Name = 'current')
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// Store a profile (JSON text) as the current one, with the next version.
ClassMethod Store(json As %String, source As %String = "", user As %String = "") As %Status
{
    Set p = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(p) || $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "The profile is not a JSON object")
    Set row = ..Row()
    If '$ISOBJECT(row) Set row = ..%New(), row.Version = 0
    Set row.Version = row.Version + 1
    Set row.Json = p.%ToJSON(), row.Source = source, row.UpdatedBy = user
    Set row.UpdatedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit row.%Save()
}

/// Seed from knowledge/site/profile.json when the file exists and differs from what is stored.
ClassMethod SeedFromFile(path As %String) As %Status
{
    If '##class(%File).Exists(path) Quit $$$OK
    Set text = ##class(Shutter.Knowledge.Text).ReadFile(path)
    If text = "" Quit $$$OK
    Set row = ..Row()
    If $ISOBJECT(row) && (row.Source = path) && (row.Json = ##class(Shutter.Util.Json).Parse(text, .sc).%ToJSON()) Quit $$$OK
    Quit ..Store(text, path)
}

/// The receiver's tier (the production item's name), default 2.
ClassMethod TierOf(receiver As %String) As %Integer
{
    Set p = ..Current()
    Set list = p.%Get("receivers")
    If $ISOBJECT(list) {
        Set iter = list.%GetIterator()
        While iter.%GetNext(.i, .r) { If ##class(Shutter.Util.Json).Str(r, "name") = receiver Quit }
        If $ISOBJECT($GET(r)) && (##class(Shutter.Util.Json).Str(r, "name") = receiver) Quit +##class(Shutter.Util.Json).Str(r, "tier", 2)
    }
    Quit 2
}

/// The policy for a tier and a chain kind: automatic, approval, per_chain or board. Tier 3 never
/// answers automatic unless the profile says so explicitly; an unknown pair answers approval.
ClassMethod Policy(tier As %Integer, chainKind As %String = "single") As %String
{
    Set p = ..Current()
    Set table = p.%Get("policy")
    Set row = $SELECT($ISOBJECT(table): table.%Get("" _ tier), 1: "")
    Set value = $SELECT($ISOBJECT(row): ##class(Shutter.Util.Json).Str(row, chainKind), 1: "")
    If '$LISTFIND($LISTBUILD("automatic", "approval", "per_chain", "board"), value) Quit "approval"
    Quit value
}

/// A top-level flag of the profile as a string (history_policy, authoritative_source, unconditional_resend).
ClassMethod Flag(name As %String, default As %String = "") As %String
{
    Quit ##class(Shutter.Util.Json).Str(..Current(), name, default)
}

/// An incident setting: threshold, window_minutes, quiet_seconds.
ClassMethod IncidentSetting(name As %String, default As %Integer) As %Integer
{
    Set inc = ..Current().%Get("incident")
    If '$ISOBJECT(inc) Quit default
    Set v = ##class(Shutter.Util.Json).Str(inc, name)
    Quit $SELECT(v = "": default, 1: +v)
}

Storage Default
{
<Data name="SiteProfileDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Name</Value>
</Value>
<Value name="3">
<Value>Version</Value>
</Value>
<Value name="4">
<Value>Json</Value>
</Value>
<Value name="5">
<Value>Source</Value>
</Value>
<Value name="6">
<Value>UpdatedAt</Value>
</Value>
<Value name="7">
<Value>UpdatedBy</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.SiteProfileD</DataLocation>
<DefaultData>SiteProfileDefaultData</DefaultData>
<IdLocation>^Shutter.Store.SiteProfileD</IdLocation>
<IndexLocation>^Shutter.Store.SiteProfileI</IndexLocation>
<StreamLocation>^Shutter.Store.SiteProfileS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
