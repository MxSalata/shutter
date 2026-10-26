/// One question asked about a case (CONTRACTS 14.2): a turn of a conversation, answered by the Explain agent (tier
/// explain) or by the board's members and coordinator (tier board) through the Case Question item, with the facts of
/// Shutter.Util.WhatIf as they were handed to the agents, the accepted answer with the case's identifiers restored, the
/// typed change the coordinator named resolved from the core's own facts (never from the agent's text), and the agents'
/// runs (Shutter.Store.AgentRun rows naming the question) for the costs page. Nothing here writes to a case or to a receiver:
/// a question is read-only by construction, whatever its text says.
Class Shutter.Store.CaseQuestion Extends (%Persistent, %JSON.Adaptor)
{

/// Q-nnnnnn
Property QuestionId As %String(%JSONFIELDNAME = "questionId", MAXLEN = 32) [ Required ];

Index QuestionIdx On QuestionId [ Unique ];

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

/// The conversation this turn belongs to: a suggested conversation's id from knowledge/questions/<S>.json (c1), or, for a
/// free question that starts one, the question's own id.
Property Conversation As %String(%JSONFIELDNAME = "conversation", MAXLEN = 64) [ Required ];

Index ConversationIdx On (Case, Conversation, Turn);

/// 1-based within the conversation.
Property Turn As %Integer(%JSONFIELDNAME = "turn") [ Required ];

/// explain (one agent, plain words from the evidence) or board (the specialists, then the coordinator's synthesis).
Property Tier As %String(%JSONFIELDNAME = "tier", MAXLEN = 16, VALUELIST = ",explain,board") [ Required ];

/// suggested (a turn of the scenario's file, recorded and replayable) or free (live only).
Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 16, VALUELIST = ",suggested,free") [ InitialExpression = "free" ];

/// The question as asked. What the agents see is this text through the model view (the case's identifiers as tokens).
Property Question As %String(%JSONFIELDNAME = "question", MAXLEN = 2000) [ Required ];

/// pending (sent to the item), answering (the agents run), answered, schema_failed (the answer was refused: the problem is
/// in error), failed (no answer: the agent's status, a timeout, an error).
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",pending,answering,answered,schema_failed,failed") [ InitialExpression = "pending" ];

Index StateIdx On State;

Property AskedBy As %String(%JSONFIELDNAME = "askedBy", MAXLEN = 100);

Property AskedAt As %String(%JSONFIELDNAME = "askedAt", MAXLEN = 30);

Property AnsweredAt As %String(%JSONFIELDNAME = "answeredAt", MAXLEN = 30);

/// Why the question ended schema_failed or failed.
Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

/// The what-if facts handed to the agents (Shutter.Util.WhatIf.ForCase(case).facts at the time), as JSON: what the
/// answer's setting, under_alternative and suggested_change are checked against.
Property FactsJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The accepted answer (Shutter.Schema.Answer, or Shutter.Schema.BoardAnswer for the board), identifiers restored.
Property AnswerJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The members' answers of a board question, [{member, status, answer?, error?}], identifiers restored.
Property MemberAnswersJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// {setting?: <fact>, under_alternative?: <fact>, suggested_change?: {...fact.suggested_change, why}}: the facts the
/// coordinator named, copied whole from FactsJSON, with the agent's why on the change.
Property ResolvedJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The key the answering run (the Explain agent's, or the coordinator's) was recorded and replayed under; "" for a free
/// question, which runs live only.
Property RecordKey As %String(%JSONFIELDNAME = "recordKey", MAXLEN = 300);

/// live, record or replay, as the bridge reported the answering run; "" until it answered.
Property Mode As %String(%JSONFIELDNAME = "mode", MAXLEN = 16);

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100);

/// The sum over the question's runs (0 for replays and mimic runs), from Shutter.Store.AgentRun.
Property CostUSD As %Numeric(%JSONFIELDNAME = "costUsd", SCALE = 6);

Property Runs As %Integer(%JSONFIELDNAME = "runs") [ InitialExpression = 0 ];

/// The production message that carried the answering run's request: the Visual Trace link.
Property EnsMessageId As %String(%JSONFIELDNAME = "ensMessageId", MAXLEN = 20);

/// A question left pending or answering this long was left behind (a restart in the middle of it): the next list marks
/// it failed, so the panel never waits for ever.
Parameter STALEAFTERSECONDS = 900;

/// Open a question. The conversation is the one given, else the question's own id; the turn is the one given (a suggested
/// turn), else the next in the conversation.
ClassMethod Create(case As Shutter.Store.Case, tier As %String, source As %String, text As %String, askedBy As %String, conversation As %String = "", turn As %Integer = 0, Output q As Shutter.Store.CaseQuestion) As %Status
{
    Set q = ""
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "A question needs a case")
    If (tier '= "explain") && (tier '= "board") Quit $$$ERROR($$$GeneralError, "The tier must be explain or board")
    Set text = $ZSTRIP(text, "<>W")
    If text = "" Quit $$$ERROR($$$GeneralError, "A question needs its text")
    If $LENGTH(text) > 2000 Quit $$$ERROR($$$GeneralError, "A question is at most 2000 characters")
    Set q = ..%New()
    Set q.QuestionId = "Q-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Shutter.Counter("question")), 6), " ", "0")
    Do q.CaseSetObjectId(case.%Id())
    Set q.Conversation = $SELECT(conversation = "": q.QuestionId, 1: $EXTRACT(conversation, 1, 64))
    Set q.Turn = $SELECT(+turn > 0: +turn, 1: ..NextTurn(case, q.Conversation))
    Set q.Tier = tier, q.Source = $SELECT(source = "suggested": "suggested", 1: "free")
    Set q.Question = text, q.AskedBy = askedBy, q.State = "pending"
    Set q.AskedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit q.%Save()
}

/// The next turn of a conversation of a case: one past the highest stored.
ClassMethod NextTurn(case As Shutter.Store.Case, conversation As %String) As %Integer
{
    Set id = case.%Id(), max = ""
    &sql(SELECT MAX(Turn) INTO :max FROM Shutter_Store.CaseQuestion WHERE "Case" = :id AND Conversation = :conversation)
    If SQLCODE '= 0 Set max = ""
    Quit +max + 1
}

/// The question of a case already asked for a suggested conversation's turn, or "".
ClassMethod ForTurn(case As Shutter.Store.Case, conversation As %String, turn As %Integer) As Shutter.Store.CaseQuestion
{
    Set id = case.%Id(), qid = ""
    &sql(SELECT TOP 1 ID INTO :qid FROM Shutter_Store.CaseQuestion WHERE "Case" = :id AND Conversation = :conversation AND Turn = :turn ORDER BY ID DESC)
    If (SQLCODE '= 0) || (qid = "") Quit ""
    Quit ..%OpenId(qid)
}

ClassMethod ByQuestionId(id As %String) As Shutter.Store.CaseQuestion
{
    Set rowId = ""
    &sql(SELECT ID INTO :rowId FROM Shutter_Store.CaseQuestion WHERE QuestionId = :id)
    If (SQLCODE '= 0) || (rowId = "") Quit ""
    Quit ..%OpenId(rowId)
}

/// The agents run: the facts are fixed now, and what follows is checked against them.
Method Answering(facts As %DynamicArray, recordKey As %String = "") As %Status
{
    Set ..State = "answering"
    Set ..FactsJSON = $SELECT($ISOBJECT(facts): facts.%ToJSON(), 1: "[]")
    Set ..RecordKey = recordKey
    Quit ..%Save()
}

/// A member of the board answered (or did not): kept for the coordinator's context and the page.
Method AddMemberAnswer(member As %String, status As %String, answer As %DynamicObject = "", error As %String = "") As %Status
{
    Set list = ..MemberAnswers()
    Set m = {}
    Set m.member = member, m.status = status
    If $ISOBJECT(answer) Set m.answer = answer
    If error '= "" Set m.error = $EXTRACT(error, 1, 1000)
    Do list.%Push(m)
    Set ..MemberAnswersJSON = list.%ToJSON()
    Quit ..%Save()
}

Method MemberAnswers() As %DynamicArray
{
    If ..MemberAnswersJSON = "" Quit []
    Set a = ##class(Shutter.Util.Json).Parse(..MemberAnswersJSON, .sc)
    If '$ISOBJECT(a) || 'a.%IsA("%Library.DynamicArray") Quit []
    Quit a
}

Method Facts() As %DynamicArray
{
    If ..FactsJSON = "" Quit []
    Set a = ##class(Shutter.Util.Json).Parse(..FactsJSON, .sc)
    If '$ISOBJECT(a) || 'a.%IsA("%Library.DynamicArray") Quit []
    Quit a
}

/// The accepted answer, with the resolved facts, and the answering run's mode, model and message.
Method Answered(answer As %DynamicObject, resolved As %DynamicObject, run As Shutter.Store.AgentRun) As %Status
{
    Set ..State = "answered", ..Error = ""
    Set ..AnswerJSON = answer.%ToJSON()
    Set ..ResolvedJSON = $SELECT($ISOBJECT(resolved): resolved.%ToJSON(), 1: "")
    Set ..AnsweredAt = ##class(Shutter.Util.Time).NowUTC()
    If $ISOBJECT(run) Set ..Mode = run.Mode, ..Model = run.Model, ..EnsMessageId = run.EnsMessageId
    Do ..SumRuns()
    Quit ..%Save()
}

/// The answer was refused by the core's checks (the problem), or no answer came (the agent's status, a timeout).
Method Fail(state As %String, error As %String, run As Shutter.Store.AgentRun = "") As %Status
{
    Set ..State = $SELECT(state = "schema_failed": "schema_failed", 1: "failed")
    Set ..Error = $EXTRACT(error, 1, 2000)
    Set ..AnsweredAt = ##class(Shutter.Util.Time).NowUTC()
    If $ISOBJECT(run) Set ..Mode = run.Mode, ..Model = run.Model, ..EnsMessageId = run.EnsMessageId
    Do ..SumRuns()
    Quit ..%Save()
}

/// The runs that name this question: their count and what they spent.
Method SumRuns()
{
    Set qid = ..QuestionId, n = 0, cost = 0
    &sql(SELECT COUNT(*), SUM(CostUSD) INTO :n, :cost FROM Shutter_Store.AgentRun WHERE QuestionId = :qid)
    If SQLCODE '= 0 Set n = 0, cost = 0
    Set ..Runs = +n, ..CostUSD = +cost
}

/// Mark the questions of a case left pending or answering beyond STALEAFTERSECONDS as failed. Returns how many.
ClassMethod CloseStale(case As Shutter.Store.Case) As %Integer
{
    Set cutoff = ##class(Shutter.Util.Time).FromNow(-..#STALEAFTERSECONDS), id = case.%Id(), n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.CaseQuestion WHERE ""Case"" = ? AND State IN ('pending', 'answering') AND AskedAt < ?", id, cutoff)
    While rs.%Next() {
        Set q = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(q)
        Do q.Fail("failed", "No answer within " _ ..#STALEAFTERSECONDS _ " s; the question was left behind")
        Set n = n + 1
    }
    Quit n
}

// ---- the checks on the way back (CONTRACTS 14.4) ----

/// Check an agent's answer against this question's facts and the model view the agents saw: answer text present; cites
/// are evidence ids of the model view (a top-level key of the view, with or without a path under it) or W<n> fact ids;
/// confidence, when given, high, medium or low; for the board, setting, under_alternative and suggested_change each name
/// a fact id of the facts. Returns 1 and the resolved facts, or 0 and the problem.
ClassMethod CheckAnswer(answer As %DynamicObject, facts As %DynamicArray, view As %DynamicObject, board As %Boolean, Output resolved As %DynamicObject, Output problem As %String) As %Boolean
{
    Set resolved = {}, problem = ""
    Set json = "Shutter.Util.Json"
    If '$ISOBJECT(answer) || 'answer.%IsA("%Library.DynamicObject") Set problem = "The answer is not a JSON object" Quit 0
    Set text = $CLASSMETHOD(json, "Str", answer, "answer")
    If $ZSTRIP(text, "<>W") = "" Set problem = "The answer has no text" Quit 0
    If $LENGTH(text) > 1200 Set problem = "The answer is longer than 1200 characters" Quit 0
    Set conf = $CLASSMETHOD(json, "Str", answer, "confidence")
    If (conf '= "") && (conf '= "high") && (conf '= "medium") && (conf '= "low") Set problem = "confidence must be high, medium or low, not " _ $EXTRACT(conf, 1, 40) Quit 0
    // The fact ids.
    Set byId = {}
    If $ISOBJECT(facts) {
        Set fi = facts.%GetIterator()
        While fi.%GetNext(, .f) { If $ISOBJECT(f) && ($CLASSMETHOD(json, "Str", f, "id") '= "") Do byId.%Set($CLASSMETHOD(json, "Str", f, "id"), f) }
    }
    Set cites = answer.%Get("cites")
    If $ISOBJECT(cites) && cites.%IsA("%Library.DynamicArray") {
        Set ci = cites.%GetIterator()
        While ci.%GetNext(, .c) {
            If '..CiteKnown(c, byId, view) Set problem = "cites names " _ $EXTRACT(c, 1, 80) _ ", which is neither an evidence id of the model view nor a fact" Quit
        }
        If problem '= "" Quit 0
    } ElseIf answer.%IsDefined("cites") && (answer.%Get("cites") '= "") {
        Set problem = "cites must be an array" Quit 0
    }
    If 'board Quit 1
    For key = "setting", "under_alternative", "suggested_change" {
        Continue:'answer.%IsDefined(key)
        Set ref = answer.%Get(key)
        Continue:((ref = "") || (ref = $CHAR(0)))
        If '$ISOBJECT(ref) || 'ref.%IsA("%Library.DynamicObject") Set problem = key _ " must be an object naming a fact" Quit
        Set fid = $CLASSMETHOD(json, "Str", ref, "fact")
        Set fact = $SELECT(fid = "": "", 1: byId.%Get(fid))
        If (fid = "") || '$ISOBJECT(fact) Set problem = key _ " names a setting or change that is not among the facts" _ $SELECT(fid '= "": " (" _ $EXTRACT(fid, 1, 40) _ ")", 1: "") Quit
        If key = "suggested_change" {
            Set change = fact.%Get("suggested_change")
            If '$ISOBJECT(change) Set problem = "suggested_change names " _ fid _ ", which carries no change" Quit
            Set copy = ##class(%DynamicObject).%FromJSON(change.%ToJSON())
            Set copy.fact = fid
            Set why = $CLASSMETHOD(json, "Str", ref, "why")
            If why '= "" Set copy.why = $EXTRACT(why, 1, 1000)
            Do resolved.%Set(key, copy)
        } Else {
            Do resolved.%Set(key, ##class(%DynamicObject).%FromJSON(fact.%ToJSON()))
        }
    }
    If problem '= "" Quit 0
    Set persp = answer.%Get("perspectives")
    If answer.%IsDefined("perspectives") && ($ISOBJECT(persp) = 0) && (persp '= "") Set problem = "perspectives must be an array" Quit 0
    Quit 1
}

/// A cite is a fact id, or an evidence id of the model view: one of its top-level keys, alone or followed by a path
/// (message.notes, history[2], timeline.3).
ClassMethod CiteKnown(cite As %String, byId As %DynamicObject, view As %DynamicObject) As %Boolean
{
    If $ISOBJECT(cite) Quit 0
    Set c = $ZSTRIP(cite, "<>W")
    If c = "" Quit 0
    If $ISOBJECT(byId) && byId.%IsDefined(c) Quit 1
    If '$ISOBJECT(view) Quit 0
    Set head = $PIECE($PIECE($PIECE(c, ".", 1), "[", 1), ":", 1)
    If head = "" Quit 0
    If view.%IsDefined(head) Quit 1
    // The evidence may sit one level down (context.case.evidence): look there too.
    Set vi = view.%GetIterator()
    While vi.%GetNext(, .v) { If $ISOBJECT(v) && v.%IsA("%Library.DynamicObject") && v.%IsDefined(head) Return 1 }
    Quit 0
}

// ---- what the routes read ----

/// The question for the page. With full, the facts, the members' answers and the resolved change too.
Method ToObject(full As %Boolean = 1) As %DynamicObject
{
    Set o = {}
    Set o.questionId = ..QuestionId
    Set o.caseId = $SELECT($ISOBJECT(..Case): ..Case.CaseId, 1: "")
    Set o.conversation = ..Conversation, o.turn = ..Turn, o.tier = ..Tier, o.source = ..Source
    Set o.question = ..Question, o.state = ..State
    Set o.askedBy = ..AskedBy, o.askedAt = ..AskedAt
    If ..AnsweredAt = "" { Do o.%Set("answeredAt", "", "null") } Else { Set o.answeredAt = ..AnsweredAt }
    Set o.error = ..Error
    If ..Mode = "" { Do o.%Set("mode", "", "null") } Else { Set o.mode = ..Mode }
    If ..Model = "" { Do o.%Set("model", "", "null") } Else { Set o.model = ..Model }
    Set o.costUsd = +..CostUSD, o.runs = +..Runs
    If ..RecordKey = "" { Do o.%Set("recordKey", "", "null") } Else { Set o.recordKey = ..RecordKey }
    If ..EnsMessageId = "" { Do o.%Set("ensMessageId", "", "null") } Else { Set o.ensMessageId = ..EnsMessageId }
    Set answer = ""
    If ..AnswerJSON '= "" Set answer = ##class(Shutter.Util.Json).Parse(..AnswerJSON, .sc)
    If $ISOBJECT(answer) { Set o.answer = answer } Else { Do o.%Set("answer", "", "null") }
    If 'full Quit o
    Set o.facts = ..Facts()
    Set o.memberAnswers = ..MemberAnswers()
    Set resolved = ""
    If ..ResolvedJSON '= "" Set resolved = ##class(Shutter.Util.Json).Parse(..ResolvedJSON, .sc)
    If $ISOBJECT(resolved) { Set o.resolved = resolved } Else { Set o.resolved = {} }
    Set runs = []
    Set qid = ..QuestionId
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, Role, MemberCode, Status, Mode, Model, CostUSD, DurationMs, EnsMessageId, Error FROM Shutter_Store.AgentRun WHERE QuestionId = ? ORDER BY ID", qid)
    While rs.%Next() {
        Set r = {}
        Set r.runId = rs.%Get("ID"), r.role = rs.%Get("Role"), r.member = rs.%Get("MemberCode"), r.status = rs.%Get("Status")
        Set r.mode = rs.%Get("Mode"), r.model = rs.%Get("Model"), r.costUsd = +rs.%Get("CostUSD"), r.durationMs = +rs.%Get("DurationMs")
        Set r.ensMessageId = rs.%Get("EnsMessageId"), r.error = rs.%Get("Error")
        Do runs.%Push(r)
    }
    Set o.agentRuns = runs
    Quit o
}

/// The questions of a case, by conversation and turn, as the list shows them (no facts, no members' answers).
ClassMethod ListForCase(case As Shutter.Store.Case) As %DynamicArray
{
    Set out = []
    Do ..CloseStale(case)
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.CaseQuestion WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set q = ..%OpenId(rs.%Get("ID"))
        If $ISOBJECT(q) Do out.%Push(q.ToObject(0))
    }
    Quit out
}

/// The earlier answered turns of a conversation before a turn, oldest first, at most the last `keep`:
/// [{turn, tier, question, answer}], for the agents' context (the caller tokenises the texts).
ClassMethod EarlierTurns(case As Shutter.Store.Case, conversation As %String, beforeTurn As %Integer, keep As %Integer = 3) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ (+keep) _ " ID FROM Shutter_Store.CaseQuestion WHERE ""Case"" = ? AND Conversation = ? AND Turn < ? AND State = 'answered' ORDER BY Turn DESC", case.%Id(), conversation, +beforeTurn)
    Set ids = ""
    While rs.%Next() { Set ids = $LISTBUILD(rs.%Get("ID")) _ ids }
    For i = 1:1:$LISTLENGTH(ids) {
        Set q = ..%OpenId($LIST(ids, i))
        Continue:'$ISOBJECT(q)
        Set t = {}
        Set t.turn = q.Turn, t.tier = q.Tier, t.question = q.Question
        Set answer = ""
        If q.AnswerJSON '= "" Set answer = ##class(Shutter.Util.Json).Parse(q.AnswerJSON, .sc)
        If $ISOBJECT(answer) Set t.answer = answer
        Do out.%Push(t)
    }
    Quit out
}

// ---- the suggested conversations (knowledge/questions/<S>.json) ----

/// The scenario's file of suggested conversations under the module root ({scenario, conversations: [{id, turns: [{turn,
/// tier, text}]}]}), or "" when the scenario has none or the file does not parse.
ClassMethod SuggestedFile(scenario As %String) As %DynamicObject
{
    If (scenario = "") || (scenario '? 1"S"1.3N) Quit ""
    Set root = $GET(^Shutter.Config("root"))
    If root = "" Quit ""
    Set path = ##class(%File).NormalizeDirectory(root) _ "knowledge/questions/" _ scenario _ ".json"
    If '##class(%File).Exists(path) Quit ""
    Set obj = ""
    Try {
        Set stream = ##class(%Stream.FileCharacter).%New()
        Set stream.TranslateTable = "UTF8"
        Set sc = stream.LinkToFile(path)
        If $$$ISOK(sc) Set obj = ##class(%DynamicObject).%FromJSON(stream)
    } Catch ex {
        Set obj = ""
    }
    If '$ISOBJECT(obj) || 'obj.%IsA("%Library.DynamicObject") Quit ""
    Quit obj
}

/// The suggested conversations of a case's scenario, each turn with the question already asked for it (the newest):
/// {scenario, conversations: [{id, turns: [{turn, tier, text, asked: {questionId, state} | null}]}]}. A case without a
/// scenario, or a scenario without a file, has no conversations.
ClassMethod Suggested(case As Shutter.Store.Case) As %DynamicObject
{
    Set out = {}
    Set out.scenario = case.Scenario
    Set out.conversations = []
    Set file = ..SuggestedFile(case.Scenario)
    If '$ISOBJECT(file) Quit out
    Set convs = file.%Get("conversations")
    If '$ISOBJECT(convs) || 'convs.%IsA("%Library.DynamicArray") Quit out
    Set ci = convs.%GetIterator()
    While ci.%GetNext(, .c) {
        Continue:'$ISOBJECT(c)
        Set id = ##class(Shutter.Util.Json).Str(c, "id")
        Continue:(id = "")
        Set conv = {}
        Set conv.id = id, conv.turns = []
        Set turns = c.%Get("turns")
        If $ISOBJECT(turns) && turns.%IsA("%Library.DynamicArray") {
            Set ti = turns.%GetIterator()
            While ti.%GetNext(, .t) {
                Continue:'$ISOBJECT(t)
                Set turn = +##class(Shutter.Util.Json).Str(t, "turn")
                Continue:(turn < 1)
                Set row = {}
                Set row.turn = turn
                Set row.tier = $SELECT(##class(Shutter.Util.Json).Str(t, "tier") = "board": "board", 1: "explain")
                Set row.text = $EXTRACT(##class(Shutter.Util.Json).Str(t, "text"), 1, 2000)
                Set asked = ..ForTurn(case, id, turn)
                If $ISOBJECT(asked) { Set a = {} Set a.questionId = asked.QuestionId, a.state = asked.State Set row.asked = a } Else { Do row.%Set("asked", "", "null") }
                Do conv.turns.%Push(row)
            }
        }
        Do out.conversations.%Push(conv)
    }
    Quit out
}

/// The tier and text of a suggested turn of the case's scenario; 0 when the file has no such turn.
ClassMethod SuggestedTurn(case As Shutter.Store.Case, conversation As %String, turn As %Integer, Output tier As %String, Output text As %String) As %Boolean
{
    Set tier = "", text = ""
    Set all = ..Suggested(case)
    Set ci = all.conversations.%GetIterator()
    While ci.%GetNext(, .c) {
        Continue:(c.id '= conversation)
        Set ti = c.turns.%GetIterator()
        While ti.%GetNext(, .t) {
            If +t.turn = +turn Set tier = t.tier, text = t.text Return (text '= "")
        }
    }
    Quit 0
}

Storage Default
{
<Data name="CaseQuestionDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>QuestionId</Value>
</Value>
<Value name="3">
<Value>Case</Value>
</Value>
<Value name="4">
<Value>Conversation</Value>
</Value>
<Value name="5">
<Value>Turn</Value>
</Value>
<Value name="6">
<Value>Tier</Value>
</Value>
<Value name="7">
<Value>Source</Value>
</Value>
<Value name="8">
<Value>Question</Value>
</Value>
<Value name="9">
<Value>State</Value>
</Value>
<Value name="10">
<Value>AskedBy</Value>
</Value>
<Value name="11">
<Value>AskedAt</Value>
</Value>
<Value name="12">
<Value>AnsweredAt</Value>
</Value>
<Value name="13">
<Value>Error</Value>
</Value>
<Value name="14">
<Value>FactsJSON</Value>
</Value>
<Value name="15">
<Value>AnswerJSON</Value>
</Value>
<Value name="16">
<Value>MemberAnswersJSON</Value>
</Value>
<Value name="17">
<Value>ResolvedJSON</Value>
</Value>
<Value name="18">
<Value>RecordKey</Value>
</Value>
<Value name="19">
<Value>Mode</Value>
</Value>
<Value name="20">
<Value>Model</Value>
</Value>
<Value name="21">
<Value>CostUSD</Value>
</Value>
<Value name="22">
<Value>Runs</Value>
</Value>
<Value name="23">
<Value>EnsMessageId</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.CaseQuestionD</DataLocation>
<DefaultData>CaseQuestionDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CaseQuestionD</IdLocation>
<IndexLocation>^Shutter.Store.CaseQuestionI</IndexLocation>
<StreamLocation>^Shutter.Store.CaseQuestionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
