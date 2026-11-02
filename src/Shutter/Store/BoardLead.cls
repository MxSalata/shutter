/// One board per failure signature (CONTRACTS 6.6, v1.35): the case whose board runs for a signature within the window,
/// and what it decided. The first case of a signature convenes the board and is the leader; a case of the same signature
/// that arrives while the leader's board runs, or within the window after it, follows: it convenes no board and takes
/// the leader's decision (the disposition, the catalogue entry and outcome, the members' verdicts; never a word of text,
/// since the leader's text carries the leader's patient) through its own evidence, gate, rehearsal and approval. A lead
/// that failed (no plan) attracts no followers. A lead begun before the last scenario reset counts for nothing, as the
/// incident detector's window does, so a demo's scenario runs never coalesce with earlier ones.
Class Shutter.Store.BoardLead Extends (%Persistent, %JSON.Adaptor)
{

Property Signature As %String(%JSONFIELDNAME = "signature", MAXLEN = 80) [ Required ];

Index SigIdx On Signature;

Property LeaderCaseId As %String(%JSONFIELDNAME = "leaderCaseId", MAXLEN = 32) [ Required ];

Index LeaderIdx On LeaderCaseId;

Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",running,done,failed");

Property StartedAt As %String(%JSONFIELDNAME = "startedAt", MAXLEN = 30);

Property EndedAt As %String(%JSONFIELDNAME = "endedAt", MAXLEN = 30);

/// Until when a case of the signature follows this lead.
Property ExpiresAt As %String(%JSONFIELDNAME = "expiresAt", MAXLEN = 30);

/// The leader's plan object, for the followers' decision.
Property PlanJSON As %String(%JSONFIELDNAME = "plan", MAXLEN = "");

/// The members' verdicts: [{memberCode, role, disposition, confidence}], no text.
Property VerdictsJSON As %String(%JSONFIELDNAME = "verdicts", MAXLEN = "");

/// Why the lead failed, when it did.
Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 500);

/// How many cases took this lead's decision.
Property Followers As %Integer(%JSONFIELDNAME = "followers") [ InitialExpression = 0 ];

/// The signature's parts, for the record.
Property PartsJSON As %String(%JSONFIELDNAME = "parts", MAXLEN = "");

Parameter DEFAULTWINDOW = 600;

/// How long a lead holds its signature, in seconds: ^Shutter.Config("leadWindowSeconds"), 0 (no coalescing: every case its
/// own board) to 86400, 600 by default.
ClassMethod WindowSeconds() As %Integer
{
    Set w = $GET(^Shutter.Config("leadWindowSeconds"), ..#DEFAULTWINDOW)
    If (w '? 1.N) || (w > 86400) Quit ..#DEFAULTWINDOW
    Quit +w
}

/// The lead a case of the signature follows now: the newest lead of the signature that has not expired, has not failed,
/// and began after the last scenario reset; "" when the case is to lead itself.
ClassMethod Current(signature As %String) As Shutter.Store.BoardLead
{
    If signature = "" Quit ""
    Set now = ##class(Shutter.Util.Time).NowUTC(), resetAt = $GET(^Shutter.Config("resetAt"))
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Shutter_Store.BoardLead WHERE Signature = ? AND State <> 'failed' AND ExpiresAt > ? ORDER BY ID DESC", signature, now)
    If 'rs.%Next() Quit ""
    Set lead = ..%OpenId(rs.%Get("ID"))
    If '$ISOBJECT(lead) Quit ""
    If (resetAt '= "") && (lead.StartedAt ']] resetAt) && (lead.StartedAt '= resetAt) Quit ""
    Quit lead
}

/// The lead a case leads, if any (running or ended).
ClassMethod ForLeader(leaderCaseId As %String) As Shutter.Store.BoardLead
{
    Set id = ""
    &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store.BoardLead WHERE LeaderCaseId = :leaderCaseId ORDER BY ID DESC)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// A case convenes the board for its signature: the lead opens, running, for the window.
ClassMethod Begin(signature As %String, case As Shutter.Store.Case, parts As %DynamicObject = "", Output lead As Shutter.Store.BoardLead) As %Status
{
    Set lead = ..%New()
    Set lead.Signature = signature, lead.LeaderCaseId = case.CaseId, lead.State = "running"
    Set lead.StartedAt = ##class(Shutter.Util.Time).NowUTC(), lead.ExpiresAt = ##class(Shutter.Util.Time).FromNow(..WindowSeconds())
    If $ISOBJECT(parts) Set lead.PartsJSON = parts.%ToJSON()
    Quit lead.%Save()
}

/// The leader's board ended: done with its plan and the members' verdicts, or failed with the reason. Returns the lead,
/// or "" when the case leads nothing.
ClassMethod Finish(leaderCaseId As %String, state As %String, plan As %DynamicObject = "", verdicts As %DynamicArray = "", reason As %String = "") As Shutter.Store.BoardLead
{
    Set lead = ..ForLeader(leaderCaseId)
    If '$ISOBJECT(lead) Quit ""
    If lead.State '= "running" Quit lead
    Set lead.State = $SELECT(state = "done": "done", 1: "failed"), lead.EndedAt = ##class(Shutter.Util.Time).NowUTC()
    If $ISOBJECT(plan) Set lead.PlanJSON = plan.%ToJSON()
    If $ISOBJECT(verdicts) Set lead.VerdictsJSON = verdicts.%ToJSON()
    Set lead.Reason = $EXTRACT(reason, 1, 500)
    Set sc = lead.%Save()
    Quit lead
}

/// One more follower took the decision.
Method Followed() As %Status
{
    Set ..Followers = ..Followers + 1
    Quit ..%Save()
}

/// The cases following a leader and still waiting for its decision.
ClassMethod FollowersOf(leaderCaseId As %String) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT CaseId FROM Shutter_Store.""Case"" WHERE FollowsCase = ? AND State = 'investigating' ORDER BY ID", leaderCaseId)
    While rs.%Next() { Do out.%Push(rs.%Get("CaseId")) }
    Quit out
}

/// The members' verdicts of a snapshot's findings, without their text.
ClassMethod VerdictsOf(snapshot As Shutter.Store.Snapshot) As %DynamicArray
{
    Set out = []
    If '$ISOBJECT(snapshot) Quit out
    Set all = ##class(Shutter.Store.Finding).ForSnapshot(snapshot)
    Set it = all.%GetIterator()
    While it.%GetNext(, .f) {
        Continue:'$ISOBJECT(f)
        Set v = {}
        For k = "memberCode", "role", "disposition", "confidence" { If f.%IsDefined(k) Do v.%Set(k, f.%Get(k)) }
        Do out.%Push(v)
    }
    Quit out
}

/// The row as JSON with its id, the plan and the verdicts as objects.
Method Projection() As %DynamicObject
{
    Set o = ##class(Shutter.Util.Json).Project($THIS)
    For k = "plan", "verdicts", "parts" { If o.%GetTypeOf(k) = "string" Do o.%Set(k, ##class(Shutter.Util.Json).Parse(o.%Get(k), .psc)) }
    Quit o
}

Storage Default
{
<Data name="BoardLeadDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Signature</Value>
</Value>
<Value name="3">
<Value>LeaderCaseId</Value>
</Value>
<Value name="4">
<Value>State</Value>
</Value>
<Value name="5">
<Value>StartedAt</Value>
</Value>
<Value name="6">
<Value>EndedAt</Value>
</Value>
<Value name="7">
<Value>ExpiresAt</Value>
</Value>
<Value name="8">
<Value>PlanJSON</Value>
</Value>
<Value name="9">
<Value>VerdictsJSON</Value>
</Value>
<Value name="10">
<Value>Reason</Value>
</Value>
<Value name="11">
<Value>Followers</Value>
</Value>
<Value name="12">
<Value>PartsJSON</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.BoardLeadD</DataLocation>
<DefaultData>BoardLeadDefaultData</DefaultData>
<IdLocation>^Shutter.Store.BoardLeadD</IdLocation>
<IndexLocation>^Shutter.Store.BoardLeadI</IndexLocation>
<StreamLocation>^Shutter.Store.BoardLeadS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
