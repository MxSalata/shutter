/// A request to run an agent, carried through the production like any other message so that the
/// Visual Trace shows it. The context is data for the model, never instructions; the goal is the
/// task in plain words.
Class Shutter.Bridge.Msg.AgentRequest Extends Ens.Request
{

/// specialist, coordinator or generalist; free for other users of the bridge.
Property Role As %String(MAXLEN = 32);

/// The library member that runs, when the request comes from a board.
Property MemberCode As %String(MAXLEN = 32);

/// The declarative agent class to run. Overrides the operation's AgentClass setting when set.
Property AgentClass As %String(MAXLEN = 200);

/// The task, in plain words.
Property Goal As %String(MAXLEN = "");

/// JSON delivered to the model inside a marked data block.
Property Context As %String(MAXLEN = "");

/// What the run is about: the case id. Tools may only touch this key; policies enforce it.
Property CorrelationKey As %String(MAXLEN = 200);

/// The digest of the evidence the run reads.
Property SnapshotDigest As %String(MAXLEN = 80);

/// The schema class the terminal tool validates against (a %JSON.Adaptor class).
Property ResultClass As %String(MAXLEN = 200);

/// The terminal tool's name: submit_findings or submit_plan.
Property TerminalTool As %String(MAXLEN = 64) [ InitialExpression = "SubmitFindings" ];

/// The agent configuration version in force (instructions, tools, knowledge).
Property ConfigVersion As %String(MAXLEN = 32);

/// live, record or replay; empty uses the operation's Mode setting.
Property ModeOverride As %String(MAXLEN = 16);

/// The key a recording is stored and replayed under; empty derives it from the agent class, the
/// configuration version and the snapshot digest.
Property RecordKey As %String(MAXLEN = 300);

/// A token budget for this run; empty uses the operation's setting.
Property TokenBudget As %Integer;

Storage Default
{
<Data name="AgentRequestDefaultData">
<Subscript>"AgentRequest"</Subscript>
<Value name="1">
<Value>Role</Value>
</Value>
<Value name="2">
<Value>MemberCode</Value>
</Value>
<Value name="3">
<Value>AgentClass</Value>
</Value>
<Value name="4">
<Value>Goal</Value>
</Value>
<Value name="5">
<Value>Context</Value>
</Value>
<Value name="6">
<Value>CorrelationKey</Value>
</Value>
<Value name="7">
<Value>SnapshotDigest</Value>
</Value>
<Value name="8">
<Value>ResultClass</Value>
</Value>
<Value name="9">
<Value>TerminalTool</Value>
</Value>
<Value name="10">
<Value>ConfigVersion</Value>
</Value>
<Value name="11">
<Value>ModeOverride</Value>
</Value>
<Value name="12">
<Value>RecordKey</Value>
</Value>
<Value name="13">
<Value>TokenBudget</Value>
</Value>
</Data>
<DefaultData>AgentRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
