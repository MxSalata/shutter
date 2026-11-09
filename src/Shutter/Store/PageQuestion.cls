/// One question about a page of the web app (CONTRACTS 14.6), asked from the Ask Shutter panel: the page's name, the
/// question, the summary of the screen the web app sent (ids and labels only, held to its shape by
/// Shutter.Util.PageQuestion), who asked, and the answer of the Explain agent in the tier page, or why there is none. The
/// run is a Shutter.Store.AgentRun row naming the question (with no case), so the day's budget and the costs page count it.
/// Nothing here writes anywhere else: a page question is read-only by construction, whatever its text says.
Class Shutter.Store.PageQuestion Extends (%Persistent, %JSON.Adaptor)
{

/// P-nnnnnn
Property QuestionId As %String(%JSONFIELDNAME = "questionId", MAXLEN = 32) [ Required ];

Index QuestionIdx On QuestionId [ Unique ];

/// Always page: the question tier the agent works in.
Property Tier As %String(%JSONFIELDNAME = "tier", MAXLEN = 16) [ InitialExpression = "page" ];

/// The page's name as the web app sends it (scenarios, cases, incidents, ...).
Property Page As %String(%JSONFIELDNAME = "page", MAXLEN = 40) [ Required ];

/// The question as asked, at most 500 characters.
Property Question As %String(%JSONFIELDNAME = "question", MAXLEN = 500) [ Required ];

/// The summary of the screen as the agent got it (CleanContext), as JSON.
Property ContextJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// pending, answering, answered, schema_failed or failed, as a case question's.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",pending,answering,answered,schema_failed,failed") [ InitialExpression = "pending" ];

Property AskedBy As %String(%JSONFIELDNAME = "askedBy", MAXLEN = 100);

Index AskedByIdx On AskedBy;

Property AskedAt As %String(%JSONFIELDNAME = "askedAt", MAXLEN = 30);

Property AnsweredAt As %String(%JSONFIELDNAME = "answeredAt", MAXLEN = 30);

Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

/// The accepted answer (Shutter.Schema.Answer), as JSON.
Property AnswerJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// live, as the bridge reported the run (a page question is never replayed or recorded); "" until it answered.
Property Mode As %String(%JSONFIELDNAME = "mode", MAXLEN = 16);

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100);

Property CostUSD As %Numeric(%JSONFIELDNAME = "costUsd", SCALE = 6);

/// The production message that carried the run's request: the Visual Trace link.
Property EnsMessageId As %String(%JSONFIELDNAME = "ensMessageId", MAXLEN = 20);

/// A question left pending or answering this long was left behind (a restart in the middle of it): reading it marks it
/// failed, so the panel never waits for ever.
Parameter STALEAFTERSECONDS = 600;

/// Open a question about a page. The page, the text and the summary are checked by the caller (the route) and again here.
ClassMethod Create(page As %String, text As %String, context As %DynamicObject, askedBy As %String, Output q As Shutter.Store.PageQuestion) As %Status
{
    Set q = ""
    If '##class(Shutter.Util.PageQuestion).IsPage(page) Quit $$$ERROR($$$GeneralError, "Not a page's name: " _ $EXTRACT(page, 1, 40))
    Set text = ##class(Shutter.Util.PageQuestion).CleanQuestion(text, .problem)
    If problem '= "" Quit $$$ERROR($$$GeneralError, problem)
    Set clean = ##class(Shutter.Util.PageQuestion).CleanContext(context, .problem)
    If problem '= "" Quit $$$ERROR($$$GeneralError, problem)
    Set q = ..%New()
    Set q.QuestionId = "P-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Shutter.Counter("pagequestion")), 6), " ", "0")
    Set q.Page = page, q.Question = text, q.ContextJSON = clean.%ToJSON()
    Set q.AskedBy = askedBy, q.State = "pending", q.AskedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit q.%Save()
}

ClassMethod ByQuestionId(id As %String) As Shutter.Store.PageQuestion
{
    Set rowId = ""
    &sql(SELECT ID INTO :rowId FROM Shutter_Store.PageQuestion WHERE QuestionId = :id)
    If (SQLCODE '= 0) || (rowId = "") Quit ""
    Quit ..%OpenId(rowId)
}

/// The summary of the screen as it was handed to the agent.
Method Context() As %DynamicObject
{
    Set o = ##class(Shutter.Util.Json).Parse(..ContextJSON, .sc)
    Quit $SELECT($ISOBJECT(o) && o.%IsA("%Library.DynamicObject"): o, 1: {})
}

Method Answering() As %Status
{
    Set ..State = "answering"
    Quit ..%Save()
}

Method Answered(answer As %DynamicObject, run As Shutter.Store.AgentRun) As %Status
{
    Set ..State = "answered", ..Error = ""
    Set ..AnswerJSON = answer.%ToJSON()
    Set ..AnsweredAt = ##class(Shutter.Util.Time).NowUTC()
    Do ..FromRun(run)
    Quit ..%Save()
}

/// The answer was refused by the checks (schema_failed, the problem), or none came (failed: the agent's status, a timeout).
Method Fail(state As %String, error As %String, run As Shutter.Store.AgentRun = "") As %Status
{
    Set ..State = $SELECT(state = "schema_failed": "schema_failed", 1: "failed")
    Set ..Error = $EXTRACT(error, 1, 2000)
    Set ..AnsweredAt = ##class(Shutter.Util.Time).NowUTC()
    Do ..FromRun(run)
    Quit ..%Save()
}

Method FromRun(run As Shutter.Store.AgentRun) [ Private ]
{
    If '$ISOBJECT(run) Quit
    Set ..Mode = run.Mode, ..Model = run.Model, ..EnsMessageId = run.EnsMessageId, ..CostUSD = +run.CostUSD
}

/// A question left pending or answering beyond STALEAFTERSECONDS is marked failed when it is read.
Method CloseIfStale() As %Boolean
{
    If (..State '= "pending") && (..State '= "answering") Quit 0
    If ..AskedAt ]] ##class(Shutter.Util.Time).FromNow(-..#STALEAFTERSECONDS) Quit 0
    Do ..Fail("failed", "No answer within " _ ..#STALEAFTERSECONDS _ " s; the question was left behind")
    Quit 1
}

/// The questions asked before the cutoff (an ISO UTC time), each with its runs and their tool calls, as the retention task
/// takes them with the cases' retention days and the uninstall takes them all: the typed text, the summary of the screen
/// and the answer go with the row. Returns how many went; failed counts those a transaction gave back.
ClassMethod PurgeBefore(cutoff As %String, Output failed As %Integer) As %Integer
{
    Set n = 0, failed = 0
    If cutoff = "" Quit 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.PageQuestion WHERE AskedAt IS NOT NULL AND AskedAt < ?", cutoff)
    While rs.%Next() { If $$$ISOK(..PurgeQuestion(rs.%Get("ID"))) { Set n = n + 1 } Else { Set failed = failed + 1 } }
    Quit n
}

/// One question, the runs that answered it (a page question's run has no case) and their tool calls, in one transaction.
ClassMethod PurgeQuestion(id As %String) As %Status
{
    Set qid = ""
    &sql(SELECT QuestionId INTO :qid FROM Shutter_Store.PageQuestion WHERE ID = :id)
    If (SQLCODE '= 0) || (qid = "") Quit $$$ERROR($$$GeneralError, "No page question with the row " _ id)
    Set keys = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE QuestionId = ? AND ""Case"" IS NULL AND EnsMessageId IS NOT NULL", qid)
    Set runKeys = ""
    While keys.%Next() { Set runKeys = runKeys _ $LISTBUILD(keys.%Get("EnsMessageId")) }
    TSTART
    Set sc = ..Exec("DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey IN (SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE QuestionId = ? AND ""Case"" IS NULL AND EnsMessageId IS NOT NULL)", qid)
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.AgentRun WHERE QuestionId = ? AND ""Case"" IS NULL", qid)
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

/// The question for the panel: its page, its text, its state and its answer (no summary: the asker sent it).
Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.questionId = ..QuestionId, o.tier = ..Tier, o.page = ..Page, o.question = ..Question, o.state = ..State
    Set o.askedBy = ..AskedBy, o.askedAt = ..AskedAt
    If ..AnsweredAt = "" { Do o.%Set("answeredAt", "", "null") } Else { Set o.answeredAt = ..AnsweredAt }
    If ..Error = "" { Do o.%Set("error", "", "null") } Else { Set o.error = ..Error }
    If ..Mode = "" { Do o.%Set("mode", "", "null") } Else { Set o.mode = ..Mode }
    If ..Model = "" { Do o.%Set("model", "", "null") } Else { Set o.model = ..Model }
    Set o.costUsd = +..CostUSD
    If ..EnsMessageId = "" { Do o.%Set("ensMessageId", "", "null") } Else { Set o.ensMessageId = ..EnsMessageId }
    Set answer = ""
    If ..AnswerJSON '= "" Set answer = ##class(Shutter.Util.Json).Parse(..AnswerJSON, .sc)
    If $ISOBJECT(answer) { Set o.answer = answer } Else { Do o.%Set("answer", "", "null") }
    Quit o
}

Storage Default
{
<Data name="PageQuestionDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>QuestionId</Value>
</Value>
<Value name="3">
<Value>Tier</Value>
</Value>
<Value name="4">
<Value>Page</Value>
</Value>
<Value name="5">
<Value>Question</Value>
</Value>
<Value name="6">
<Value>ContextJSON</Value>
</Value>
<Value name="7">
<Value>State</Value>
</Value>
<Value name="8">
<Value>AskedBy</Value>
</Value>
<Value name="9">
<Value>AskedAt</Value>
</Value>
<Value name="10">
<Value>AnsweredAt</Value>
</Value>
<Value name="11">
<Value>Error</Value>
</Value>
<Value name="12">
<Value>AnswerJSON</Value>
</Value>
<Value name="13">
<Value>Mode</Value>
</Value>
<Value name="14">
<Value>Model</Value>
</Value>
<Value name="15">
<Value>CostUSD</Value>
</Value>
<Value name="16">
<Value>EnsMessageId</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.PageQuestionD</DataLocation>
<DefaultData>PageQuestionDefaultData</DefaultData>
<IdLocation>^Shutter.Store.PageQuestionD</IdLocation>
<IndexLocation>^Shutter.Store.PageQuestionI</IndexLocation>
<StreamLocation>^Shutter.Store.PageQuestionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
