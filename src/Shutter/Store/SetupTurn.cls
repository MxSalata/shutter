/// One turn of Set up the site (CONTRACTS 14.7): what a person typed about a receiver being set up, what the agent was
/// shown of the draft (the model's view), the part of the draft its checks read (Shutter.Util.ProfileSetup.Frame), who
/// asked, and the turn the agent gave back once its checks passed, or why there is none. The run is a
/// Shutter.Store.AgentRun row naming the turn (with no case), so the day's budget and the costs page count it. The turns
/// of one conversation share its id and belong to who started it: the earlier texts the agent reads, the words a quote
/// must come from, and the limit on turns are all read from these rows, never from a request. Nothing here stores a
/// profile or a draft, and nothing here writes anywhere else, whatever the text says.
Class Shutter.Store.SetupTurn Extends (%Persistent, %JSON.Adaptor)
{

/// ST-nnnnnn
Property TurnId As %String(%JSONFIELDNAME = "turnId", MAXLEN = 32) [ Required ];

Index TurnIdx On TurnId [ Unique ];

/// Always setup: the question tier the agent works in.
Property Tier As %String(%JSONFIELDNAME = "tier", MAXLEN = 16) [ InitialExpression = "setup" ];

/// SC-nnnnnn: the conversation the turn belongs to.
Property Conversation As %String(%JSONFIELDNAME = "conversation", MAXLEN = 32) [ Required ];

Index ConversationIdx On Conversation;

/// The receiver the turn is about, by the name it has in the draft.
Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 200) [ Required ];

/// What the person typed, at most 500 characters (Shutter.Util.ProfileSetup.CleanText).
Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = 500) [ Required ];

/// What the agent was shown of the draft (Shutter.Util.ProfileSetup.View), as JSON.
Property ViewJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The part of the draft the checks read (Shutter.Util.ProfileSetup.Frame), as JSON. Never the whole draft.
Property FrameJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The stored profile's version the draft was made from, and the browser's count of the draft's changes, both echoed.
Property BaseVersion As %Integer(%JSONFIELDNAME = "baseVersion");

Property DraftRevision As %Integer(%JSONFIELDNAME = "draftRevision");

/// pending, answering, answered, schema_failed or failed, as a page question's.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",pending,answering,answered,schema_failed,failed") [ InitialExpression = "pending" ];

Property AskedBy As %String(%JSONFIELDNAME = "askedBy", MAXLEN = 100);

Index AskedByIdx On AskedBy;

Property AskedAt As %String(%JSONFIELDNAME = "askedAt", MAXLEN = 30);

Property AnsweredAt As %String(%JSONFIELDNAME = "answeredAt", MAXLEN = 30);

Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

/// The accepted turn (Shutter.Util.ProfileSetup.CheckTurn), as JSON.
Property TurnJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// live, as the bridge reported the run (a turn is never replayed or recorded); "" until it answered.
Property Mode As %String(%JSONFIELDNAME = "mode", MAXLEN = 16);

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100);

Property CostUSD As %Numeric(%JSONFIELDNAME = "costUsd", SCALE = 6);

/// The production message that carried the run's request: the Visual Trace link.
Property EnsMessageId As %String(%JSONFIELDNAME = "ensMessageId", MAXLEN = 20);

/// A turn left pending or answering this long was left behind (a restart in the middle of it): reading it marks it
/// failed, so the page never waits for ever and the conversation can go on.
Parameter STALEAFTERSECONDS = 600;

/// A new conversation's id.
ClassMethod NewConversation() As %String
{
    Quit "SC-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Shutter.Counter("setupconversation")), 6), " ", "0")
}

/// Whether an id has the shape of a conversation's.
ClassMethod IsConversation(id As %String) As %Boolean
{
    Quit $MATCH($GET(id), "^SC-[0-9]{6,}$")
}

/// Open a turn. The text is checked by the caller (the route) and again here; the view and the frame are the route's.
ClassMethod Create(conversation As %String, receiver As %String, text As %String, view As %DynamicObject, frame As %DynamicObject, baseVersion As %Integer, draftRevision As %Integer, askedBy As %String, Output t As Shutter.Store.SetupTurn) As %Status
{
    Set t = ""
    If '..IsConversation(conversation) Quit $$$ERROR($$$GeneralError, "Not a conversation's id")
    If receiver = "" Quit $$$ERROR($$$GeneralError, "No receiver is named")
    Set text = ##class(Shutter.Util.ProfileSetup).CleanText(text, .problem)
    If problem '= "" Quit $$$ERROR($$$GeneralError, problem)
    If '$ISOBJECT(frame) || '$ISOBJECT(##class(Shutter.Util.ProfileSetup).Find(frame, receiver)) Quit $$$ERROR($$$GeneralError, "The draft does not name the receiver")
    Set t = ..%New()
    Set t.TurnId = "ST-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Shutter.Counter("setupturn")), 6), " ", "0")
    Set t.Conversation = conversation, t.Receiver = receiver, t.Text = text
    Set t.ViewJSON = $SELECT($ISOBJECT(view): view.%ToJSON(), 1: "{}"), t.FrameJSON = frame.%ToJSON()
    Set t.BaseVersion = +baseVersion, t.DraftRevision = +draftRevision
    Set t.AskedBy = askedBy, t.State = "pending", t.AskedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit t.%Save()
}

ClassMethod ByTurnId(id As %String) As Shutter.Store.SetupTurn
{
    Set rowId = ""
    &sql(SELECT ID INTO :rowId FROM Shutter_Store.SetupTurn WHERE TurnId = :id)
    If (SQLCODE '= 0) || (rowId = "") Quit ""
    Quit ..%OpenId(rowId)
}

/// Who started a conversation (the one its first turn was asked by), or "" when it has no turn.
ClassMethod OwnerOf(conversation As %String) As %String
{
    Set owner = ""
    &sql(SELECT TOP 1 AskedBy INTO :owner FROM Shutter_Store.SetupTurn WHERE Conversation = :conversation ORDER BY ID)
    If SQLCODE '= 0 Quit ""
    Quit owner
}

/// How many turns a conversation holds.
ClassMethod Count(conversation As %String) As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.SetupTurn WHERE Conversation = :conversation)
    Quit +n
}

/// The id of a turn of the conversation that is still being read, or "": one turn at a time. A turn left behind past
/// its time is closed on the way, so it never blocks the conversation.
ClassMethod Pending(conversation As %String) As %String
{
    Set pending = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.SetupTurn WHERE Conversation = ? AND State IN ('pending', 'answering') ORDER BY ID", conversation)
    While rs.%Next() {
        Set t = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(t)
        If 't.CloseIfStale() Set pending = t.TurnId
    }
    Quit pending
}

/// What a person typed in a conversation, oldest first, as the rows hold it: the words a quote must come from.
ClassMethod Texts(conversation As %String, askedBy As %String) As %DynamicArray
{
    Set texts = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Text FROM Shutter_Store.SetupTurn WHERE Conversation = ? AND AskedBy = ? ORDER BY ID", conversation, askedBy)
    While rs.%Next() { Do texts.%Push(rs.%Get("Text")) }
    Quit texts
}

/// The earlier turns of the conversation as the agent reads them: what the person typed and, where a turn was accepted,
/// the agent's own sentence. The turn <var>before</var> and any after it are left out.
ClassMethod Earlier(conversation As %String, askedBy As %String, before As %String) As %DynamicArray
{
    Set earlier = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.SetupTurn WHERE Conversation = ? AND AskedBy = ? ORDER BY ID", conversation, askedBy)
    While rs.%Next() {
        Set t = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(t)
        Quit:t.TurnId=before
        Set e = {"you": (t.Text)}
        Set turn = t.Turn()
        If $ISOBJECT(turn) Set e."ask_shutter" = turn.%Get("say")
        Do earlier.%Push(e)
    }
    Quit earlier
}

Method View() As %DynamicObject
{
    Set o = ##class(Shutter.Util.Json).Parse(..ViewJSON, .sc)
    Quit $SELECT($ISOBJECT(o) && o.%IsA("%Library.DynamicObject"): o, 1: {})
}

Method Frame() As %DynamicObject
{
    Set o = ##class(Shutter.Util.Json).Parse(..FrameJSON, .sc)
    Quit $SELECT($ISOBJECT(o) && o.%IsA("%Library.DynamicObject"): o, 1: {})
}

/// The accepted turn, or "" when there is none.
Method Turn() As %DynamicObject
{
    If ..TurnJSON = "" Quit ""
    Set o = ##class(Shutter.Util.Json).Parse(..TurnJSON, .sc)
    Quit $SELECT($ISOBJECT(o) && o.%IsA("%Library.DynamicObject"): o, 1: "")
}

Method Answering() As %Status
{
    Set ..State = "answering"
    Quit ..%Save()
}

Method Answered(turn As %DynamicObject, run As Shutter.Store.AgentRun) As %Status
{
    Set ..State = "answered", ..Error = ""
    Set ..TurnJSON = turn.%ToJSON()
    Set ..AnsweredAt = ##class(Shutter.Util.Time).NowUTC()
    Do ..FromRun(run)
    Quit ..%Save()
}

/// The turn was refused by the checks (schema_failed, the problem), or none came (failed: the agent's status, a timeout).
/// Nothing of a refused turn is kept as drafted.
Method Fail(state As %String, error As %String, run As Shutter.Store.AgentRun = "") As %Status
{
    Set ..State = $SELECT(state = "schema_failed": "schema_failed", 1: "failed")
    Set ..Error = $EXTRACT(error, 1, 2000)
    Set ..TurnJSON = ""
    Set ..AnsweredAt = ##class(Shutter.Util.Time).NowUTC()
    Do ..FromRun(run)
    Quit ..%Save()
}

Method FromRun(run As Shutter.Store.AgentRun) [ Private ]
{
    If '$ISOBJECT(run) Quit
    Set ..Mode = run.Mode, ..Model = run.Model, ..EnsMessageId = run.EnsMessageId, ..CostUSD = +run.CostUSD
}

/// A turn left pending or answering beyond STALEAFTERSECONDS is marked failed when it is read.
Method CloseIfStale() As %Boolean
{
    If (..State '= "pending") && (..State '= "answering") Quit 0
    If ..AskedAt ]] ##class(Shutter.Util.Time).FromNow(-..#STALEAFTERSECONDS) Quit 0
    Do ..Fail("failed", "No answer within " _ ..#STALEAFTERSECONDS _ " s; the turn was left behind")
    Quit 1
}

/// The turns asked before the cutoff (an ISO UTC time), each with its runs and their tool calls, as the retention task
/// takes them with the cases' retention days and the uninstall takes them all: the typed text, the model's view, the part
/// of the draft and the accepted turn go with the row. Returns how many went; failed counts those a transaction gave back.
ClassMethod PurgeBefore(cutoff As %String, Output failed As %Integer) As %Integer
{
    Set n = 0, failed = 0
    If cutoff = "" Quit 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.SetupTurn WHERE AskedAt IS NOT NULL AND AskedAt < ?", cutoff)
    While rs.%Next() { If $$$ISOK(..PurgeTurn(rs.%Get("ID"))) { Set n = n + 1 } Else { Set failed = failed + 1 } }
    Quit n
}

/// One turn, the runs that read it (such a run has no case) and their tool calls, in one transaction.
ClassMethod PurgeTurn(id As %String) As %Status
{
    Set tid = ""
    &sql(SELECT TurnId INTO :tid FROM Shutter_Store.SetupTurn WHERE ID = :id)
    If (SQLCODE '= 0) || (tid = "") Quit $$$ERROR($$$GeneralError, "No setup turn with the row " _ id)
    Set keys = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE QuestionId = ? AND ""Case"" IS NULL AND EnsMessageId IS NOT NULL", tid)
    Set runKeys = ""
    While keys.%Next() { Set runKeys = runKeys _ $LISTBUILD(keys.%Get("EnsMessageId")) }
    TSTART
    Set sc = ..Exec("DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey IN (SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE QuestionId = ? AND ""Case"" IS NULL AND EnsMessageId IS NOT NULL)", tid)
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.AgentRun WHERE QuestionId = ? AND ""Case"" IS NULL", tid)
    If $$$ISOK(sc) Set sc = ..%DeleteId(id)
    If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK  Quit sc }
    For i = 1:1:$LISTLENGTH(runKeys) { Kill ^Shutter.Counter("toolcall", $LIST(runKeys, i)) }
    Quit sc
}

/// One SQL statement with one argument, as a status.
ClassMethod Exec(sql As %String, arg As %String) As %Status [ Private ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, arg)
    If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
    Quit $$$OK
}

/// The turn for the page: its text, its state and, once accepted, what the agent said and drafted. The model's view and
/// the part of the draft are not sent back: the asker sent the draft.
Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.turnId = ..TurnId, o.conversation = ..Conversation, o.receiver = ..Receiver, o.text = ..Text, o.state = ..State
    Do o.%Set("baseVersion", +..BaseVersion, "number")
    Do o.%Set("draftRevision", +..DraftRevision, "number")
    Set o.askedBy = ..AskedBy, o.askedAt = ..AskedAt
    If ..AnsweredAt = "" { Do o.%Set("answeredAt", "", "null") } Else { Set o.answeredAt = ..AnsweredAt }
    If ..Error = "" { Do o.%Set("error", "", "null") } Else { Set o.error = ..Error }
    If ..Mode = "" { Do o.%Set("mode", "", "null") } Else { Set o.mode = ..Mode }
    If ..Model = "" { Do o.%Set("model", "", "null") } Else { Set o.model = ..Model }
    Do o.%Set("costUsd", +..CostUSD, "number")
    If ..EnsMessageId = "" { Do o.%Set("ensMessageId", "", "null") } Else { Set o.ensMessageId = ..EnsMessageId }
    Set turn = ..Turn()
    If $ISOBJECT(turn) && (..State = "answered") { Set o.turn = turn } Else { Do o.%Set("turn", "", "null") }
    Quit o
}

Storage Default
{
<Data name="SetupTurnDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>TurnId</Value>
</Value>
<Value name="3">
<Value>Tier</Value>
</Value>
<Value name="4">
<Value>Conversation</Value>
</Value>
<Value name="5">
<Value>Receiver</Value>
</Value>
<Value name="6">
<Value>Text</Value>
</Value>
<Value name="7">
<Value>ViewJSON</Value>
</Value>
<Value name="8">
<Value>FrameJSON</Value>
</Value>
<Value name="9">
<Value>BaseVersion</Value>
</Value>
<Value name="10">
<Value>DraftRevision</Value>
</Value>
<Value name="11">
<Value>State</Value>
</Value>
<Value name="12">
<Value>AskedBy</Value>
</Value>
<Value name="13">
<Value>AskedAt</Value>
</Value>
<Value name="14">
<Value>AnsweredAt</Value>
</Value>
<Value name="15">
<Value>Error</Value>
</Value>
<Value name="16">
<Value>TurnJSON</Value>
</Value>
<Value name="17">
<Value>Mode</Value>
</Value>
<Value name="18">
<Value>Model</Value>
</Value>
<Value name="19">
<Value>CostUSD</Value>
</Value>
<Value name="20">
<Value>EnsMessageId</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.SetupTurnD</DataLocation>
<DefaultData>SetupTurnDefaultData</DefaultData>
<IdLocation>^Shutter.Store.SetupTurnD</IdLocation>
<IndexLocation>^Shutter.Store.SetupTurnI</IndexLocation>
<StreamLocation>^Shutter.Store.SetupTurnS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
