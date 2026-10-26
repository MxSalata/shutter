/// Questions about a case (Shutter.Store.CaseQuestion, Shutter.Process.Question; CONTRACTS 14.2 to 14.4) with no production
/// and no agent: the checks on an answer against the facts and the model view, the conversations' turns, the earlier turns
/// handed to a follow-up, the stale question, the record keys. The case is made by hand (scenario S99, which has no file of
/// suggested conversations) and every row made here is deleted after each test; the question counter is put back when
/// nothing else moved it meanwhile.
Class Shutter.Test.Question Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-Q-0001";

Property CaseRowId As %String;

Property CounterBefore As %String;

Method OnBeforeAllTests() As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..CounterBefore = $GET(^Shutter.Counter("question"))
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9007^ENC-9007^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9007", c.PatientId = "MRN9007", c.FailureKind = "delivery_failed"
    Set c.State = "escalated", c.Scenario = "S99", c.Receiver = "Downstream Out"
    Set c.Headline = "The transfer for encounter ENC-9007 was not delivered"
    Set c.OpenedAt = "2026-10-20T10:00:00Z", c.UpdatedAt = c.OpenedAt
    Set sc = c.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..CaseRowId = c.%Id()
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Purge(..CaseRowId)
    Set made = 0
    If ..CounterBefore '= "" Set made = $GET(^Shutter.Counter("question")) - ..CounterBefore
    If (..CounterBefore = "") || (made >= 0) {
        If ..CounterBefore = "" { Kill ^Shutter.Counter("question") } Else { Set ^Shutter.Counter("question") = ..CounterBefore }
    }
    Quit $$$OK
}

ClassMethod Purge(id As %String)
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseQuestion WHERE ""Case"" = ?", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
    Kill ^Shutter.Counter("event", id)
    If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
}

Method Case() As Shutter.Store.Case
{
    Quit ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
}

ClassMethod Facts() As %DynamicArray
{
    Quit [{"id": "W1", "kind": "alternative", "field": "receivers[].category", "receiver": "Downstream Out", "from": "current_state", "to": "history_of_record", "suggested_change": {"field": "receivers[].category", "receiver": "Downstream Out", "from": "current_state", "to": "history_of_record", "why": "the catalogue's", "valid": true, "stale": false}}, {"id": "W2", "kind": "policy", "field": "policy.2.single", "from": "automatic", "to": "approval"}]
}

ClassMethod View() As %DynamicObject
{
    Quit {"case_id": "C-1", "message": {"message_type": "ADT^A02", "notes": []}, "ward_state": {"version": 3}, "history": [{"event": "admit"}]}
}

/// The Explain agent's answer: the text, cites that are evidence ids or fact ids, a confidence from the three; anything else
/// is refused with the reason.
Method TestCheckAnswer()
{
    Set good = {"answer": "Nothing was written because a later movement was applied.", "cites": ["message", "W1", "ward_state.version", "history[0]"], "confidence": "high"}
    Do $$$AssertTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(good, ..Facts(), ..View(), 0, .resolved, .problem), "a good answer passes: " _ problem)
    Do $$$AssertEquals(resolved.%Size(), 0, "an explain answer resolves no change")
    Set bad = {"answer": "x", "cites": ["nowhere"]}
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 0, .resolved, .problem), "an unknown cite is refused")
    Do $$$AssertTrue(problem [ "nowhere", "the problem names the cite: " _ problem)
    Set bad = {"cites": []}
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 0, .resolved, .problem), "no text is refused")
    Set bad = {"answer": "x", "confidence": "sure"}
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 0, .resolved, .problem), "a confidence outside the three is refused")
    Set bad = {"answer": "x", "cites": "message"}
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 0, .resolved, .problem), "cites must be an array")
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer("", ..Facts(), ..View(), 0, .resolved, .problem), "no object is refused")
}

/// The coordinator's answer: setting, under_alternative and suggested_change name fact ids and nothing else; what is resolved
/// is the core's fact, with the agent's why on the change.
Method TestCheckBoardAnswer()
{
    Set good = {"answer": "The board agrees.", "perspectives": [{"member": "conformance", "view": "fine"}], "setting": {"fact": "W2"}, "suggested_change": {"fact": "W1", "why": "the records system keeps history"}, "cites": ["W1", "W2"], "confidence": "medium"}
    Do $$$AssertTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(good, ..Facts(), ..View(), 1, .resolved, .problem), "a good board answer passes: " _ problem)
    Do $$$AssertEquals(resolved.setting.id, "W2", "the setting is the fact whole")
    Do $$$AssertEquals(resolved.setting.field, "policy.2.single", "with its field")
    Do $$$AssertEquals(resolved."suggested_change".field, "receivers[].category", "the change is the fact's typed change")
    Do $$$AssertEquals(resolved."suggested_change".to, "history_of_record", "with its to")
    Do $$$AssertEquals(resolved."suggested_change".why, "the records system keeps history", "and the agent's why")
    Do $$$AssertEquals(resolved."suggested_change".fact, "W1", "naming the fact")
    Do $$$AssertNotTrue(resolved.%IsDefined("under_alternative"), "nothing unnamed is resolved")
    Set bad = {"answer": "x", "under_alternative": {"fact": "W9"}}
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 1, .resolved, .problem), "a fact that is not there is refused")
    Do $$$AssertTrue(problem [ "not among the facts", "the problem says so: " _ problem)
    Set bad = {"answer": "x", "suggested_change": {"fact": "W2"}}
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 1, .resolved, .problem), "a change naming a fact without one is refused")
    Do $$$AssertTrue(problem [ "carries no change", "the problem says so: " _ problem)
    Set bad = {"answer": "x", "setting": "W1"}
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 1, .resolved, .problem), "setting must be an object")
    // The same answer as an explain answer is not held to the board rule.
    Do $$$AssertTrue(##class(Shutter.Store.CaseQuestion).CheckAnswer(bad, ..Facts(), ..View(), 0, .resolved, .problem), "an explain answer is not checked for the board's fields")
}

/// A free question starts a conversation named after itself; a follow-up in it takes the next turn; a suggested turn keeps
/// the file's conversation and turn; the earlier turns handed to a follow-up are the answered ones before it, oldest first.
Method TestConversations()
{
    Set case = ..Case()
    Set sc = ##class(Shutter.Store.CaseQuestion).Create(case, "explain", "free", "Why was nothing written?", "operator", "", 0, .q1)
    Do $$$AssertStatusOK(sc, "a free question opens")
    Do $$$AssertEquals(q1.Conversation, q1.QuestionId, "a free question starts a conversation named after itself")
    Do $$$AssertEquals(q1.Turn, 1, "at turn 1")
    Do $$$AssertEquals(q1.State, "pending", "pending")
    Set sc = ##class(Shutter.Store.CaseQuestion).Create(case, "board", "free", "What if BEDMGR were authoritative?", "operator", q1.Conversation, 0, .q2)
    Do $$$AssertStatusOK(sc, "a follow-up opens")
    Do $$$AssertEquals(q2.Turn, 2, "the follow-up takes the next turn")
    Do $$$AssertEquals(q2.Tier, "board", "the tier is the turn's")
    Set sc = ##class(Shutter.Store.CaseQuestion).Create(case, "explain", "suggested", "Suggested three", "operator", "c1", 3, .q3)
    Do $$$AssertStatusOK(sc, "a suggested turn opens")
    Do $$$AssertEquals(q3.Conversation _ "." _ q3.Turn, "c1.3", "with the file's conversation and turn")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).NextTurn(case, "c1"), 4, "the next turn of c1 is 4")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).ForTurn(case, "c1", 3).QuestionId, q3.QuestionId, "the turn is found")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).ForTurn(case, "c1", 1), "", "an unasked turn is not")
    // Only answered turns are handed on.
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).EarlierTurns(case, q1.Conversation, 2).%Size(), 0, "a pending turn is not handed on")
    Set run = ""
    Do $$$AssertStatusOK(q1.Answering(..Facts(), ""), "the facts are fixed")
    Do $$$AssertStatusOK(q1.Answered({"answer": "Because a later movement stands.", "cites": ["W1"], "confidence": "high"}, {}, run), "answered")
    Set earlier = ##class(Shutter.Store.CaseQuestion).EarlierTurns(case, q1.Conversation, 2)
    Do $$$AssertEquals(earlier.%Size(), 1, "the answered turn is handed on")
    Do $$$AssertEquals(earlier.%Get(0).question, "Why was nothing written?", "with its question")
    Do $$$AssertEquals(earlier.%Get(0).answer.answer, "Because a later movement stands.", "and its answer")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).EarlierTurns(case, q1.Conversation, 1).%Size(), 0, "nothing before turn 1")
    Set list = ##class(Shutter.Store.CaseQuestion).ListForCase(case)
    Do $$$AssertEquals(list.%Size(), 3, "three questions listed")
    Do $$$AssertEquals(list.%Get(0).state, "answered", "the first answered")
    Do $$$AssertEquals(list.%Get(0).answer.answer, "Because a later movement stands.", "with its answer")
    Set full = q1.ToObject(1)
    Do $$$AssertEquals(full.facts.%Size(), 2, "the full object carries the facts")
    Do $$$AssertEquals(full.agentRuns.%Size(), 0, "and no runs here")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).ByQuestionId(q2.QuestionId).Turn, 2, "found by id")
    // Refusals.
    Do $$$AssertStatusNotOK(##class(Shutter.Store.CaseQuestion).Create(case, "other", "free", "x", "operator", "", 0, .qx), "a tier outside the two is refused")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.CaseQuestion).Create(case, "explain", "free", "   ", "operator", "", 0, .qx), "an empty question is refused")
}

/// A refused answer ends schema_failed with the problem; a question left pending beyond the stale limit is failed by the list.
Method TestFailuresAndStale()
{
    Set case = ..Case()
    Do $$$AssertStatusOK(##class(Shutter.Store.CaseQuestion).Create(case, "explain", "free", "Why?", "operator", "", 0, .q), "opened")
    Do $$$AssertStatusOK(q.Fail("schema_failed", "cites names nowhere", ""), "refused")
    Do $$$AssertEquals(q.State, "schema_failed", "schema_failed")
    Do $$$AssertEquals(q.Error, "cites names nowhere", "with the problem")
    Do $$$AssertStatusOK(##class(Shutter.Store.CaseQuestion).Create(case, "board", "free", "Still there?", "operator", "", 0, .old), "an old one")
    Set old.AskedAt = "2026-10-20T10:00:00Z"
    Do $$$AssertStatusOK(old.%Save(), "aged")
    Do $$$AssertStatusOK(##class(Shutter.Store.CaseQuestion).Create(case, "board", "free", "Fresh", "operator", "", 0, .fresh), "a fresh one")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).CloseStale(case), 1, "one stale question closed")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).ByQuestionId(old.QuestionId).State, "failed", "the old one failed")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).ByQuestionId(fresh.QuestionId).State, "pending", "the fresh one stands")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).ByQuestionId(q.QuestionId).State, "schema_failed", "the refused one is left as it was")
}

/// A scenario without a file of suggested conversations has none, and no suggested turn can be asked of it.
Method TestSuggestedWithoutFile()
{
    Set case = ..Case()
    Set all = ##class(Shutter.Store.CaseQuestion).Suggested(case)
    Do $$$AssertEquals(all.scenario, "S99", "the scenario is named")
    Do $$$AssertEquals(all.conversations.%Size(), 0, "no conversations")
    Do $$$AssertNotTrue(##class(Shutter.Store.CaseQuestion).SuggestedTurn(case, "c1", 1, .tier, .text), "no turn")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).SuggestedFile(""), "", "no scenario, no file")
    Do $$$AssertEquals(##class(Shutter.Store.CaseQuestion).SuggestedFile("../etc"), "", "only a scenario name is read")
}

/// The record key of a suggested turn names the scenario, the encounter, the event, the tier, the member, the conversation's
/// turn and the configuration version; a free question has none; the Explain agent's version is 1 unless its class says.
Method TestRecordKeys()
{
    Set case = ..Case()
    Do $$$AssertStatusOK(##class(Shutter.Store.CaseQuestion).Create(case, "board", "suggested", "What if?", "operator", "c1", 3, .q), "opened")
    Do $$$AssertEquals(##class(Shutter.Process.Question).RecordKeyFor("question:S8:ENC-9007:transfer", q, "coordinator", "2"), "question:S8:ENC-9007:transfer|board|coordinator|c1.3|2", "the key")
    Do $$$AssertEquals(##class(Shutter.Process.Question).RecordKeyFor("", q, "explain", "1"), "", "a free question has no key")
    Do $$$AssertEquals(##class(Shutter.Process.Question).ConfigVersionOf("No.Such.Class", "1"), "1", "the default when the class is not here")
    Set req = ##class(Shutter.Process.Question).BuildRequest(case, q, {"tier": "board"}, "member", "conformance", "Shutter.Agent.Conformance", "3", "SubmitAnswer", "Shutter.Schema.Answer", "Answer", 30000, 4, "k")
    Do $$$AssertEquals(req.Role _ "|" _ req.MemberCode _ "|" _ req.TerminalTool _ "|" _ req.ResultClass _ "|" _ req.ConfigVersion _ "|" _ req.RecordKey _ "|" _ req.TokenBudget _ "|" _ req.MaxIterations, "member|conformance|SubmitAnswer|Shutter.Schema.Answer|3|k|30000|4", "the request carries the fields")
    Do $$$AssertEquals(req.CorrelationKey, q.QuestionId, "correlated to the question")
}

}
