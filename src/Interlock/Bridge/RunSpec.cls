/// Everything a runner needs for one agent run: the request's fields merged with the operation's
/// settings. Built by Interlock.Bridge.Operation.Agent.
Class Interlock.Bridge.RunSpec Extends %RegisteredObject
{

Property AgentClass As %String(MAXLEN = 200);

Property Role As %String(MAXLEN = 32);

Property MemberCode As %String(MAXLEN = 32);

Property Goal As %String(MAXLEN = "");

Property Context As %String(MAXLEN = "");

Property CorrelationKey As %String(MAXLEN = 200);

Property SnapshotDigest As %String(MAXLEN = 80);

Property ResultClass As %String(MAXLEN = 200);

Property TerminalTool As %String(MAXLEN = 64);

Property ConfigVersion As %String(MAXLEN = 32);

/// live, record or replay.
Property Mode As %String(MAXLEN = 16);

/// The runner class for live and record runs.
Property RunnerClass As %String(MAXLEN = 200);

Property ProviderConfig As %String(MAXLEN = 100);

Property Model As %String(MAXLEN = 100);

Property MaxIterations As %Integer;

Property TokenBudget As %Integer;

Property RequestTimeoutSeconds As %Integer;

Property RecordKey As %String(MAXLEN = 300);

/// The production message carrying the request: the key the tool-call audit rows use.
Property EnsMessageId As %String(MAXLEN = 20);

Property EnsSessionId As %String(MAXLEN = 20);

/// The key a recording of this run is stored and found under.
Method ReplayKey() As %String
{
    If ..RecordKey '= "" Quit ..RecordKey
    Quit "digest:" _ ..SnapshotDigest _ "|" _ ..AgentClass _ "|" _ ..ConfigVersion
}

/// Build the specification from a request and the operation's settings. Request fields win where set.
ClassMethod FromRequest(request As Interlock.Bridge.Msg.AgentRequest, op As Interlock.Bridge.Operation.Agent) As Interlock.Bridge.RunSpec
{
    Set s = ..%New()
    Set s.AgentClass = $SELECT(request.AgentClass '= "": request.AgentClass, 1: op.AgentClass)
    Set s.Role = request.Role, s.MemberCode = request.MemberCode
    Set s.Goal = request.Goal, s.Context = request.Context
    Set s.CorrelationKey = request.CorrelationKey, s.SnapshotDigest = request.SnapshotDigest
    Set s.ResultClass = request.ResultClass, s.TerminalTool = request.TerminalTool
    Set s.ConfigVersion = request.ConfigVersion
    Set s.Mode = $SELECT(request.ModeOverride '= "": request.ModeOverride, 1: op.Mode)
    Set s.RunnerClass = op.Runner
    Set s.ProviderConfig = op.ProviderConfig, s.Model = op.Model
    Set s.MaxIterations = op.MaxIterations
    Set s.TokenBudget = $SELECT(request.TokenBudget '= "": request.TokenBudget, 1: op.TokenBudget)
    Set s.RequestTimeoutSeconds = op.RequestTimeoutSeconds
    Set s.RecordKey = request.RecordKey
    Quit s
}

}
