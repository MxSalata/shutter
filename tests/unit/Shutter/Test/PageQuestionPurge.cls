/// The retention of page questions (Shutter.Store.PageQuestion.PurgeBefore, Shutter.Util.RetentionTask): a question asked
/// longer ago than the retention days goes with its runs and their tool calls, and a newer one stays with its own. The rows
/// are the test's own, made with ids no question takes; a page question older than the retention days that was already
/// in this namespace goes too, as the daily task would take it.
Class Shutter.Test.PageQuestionPurge Extends %UnitTest.TestCase
{

/// A question of the test's asked at that time, a run that answered it and one tool call of that run. Returns its id.
ClassMethod Ask(tag As %String, askedAt As %String, Output runKey As %String) As %String
{
    Set q = ##class(Shutter.Store.PageQuestion).%New()
    Set q.QuestionId = "P-UT" _ $JOB _ tag, q.Page = "scenarios", q.Question = "What is S2?", q.AskedBy = "ut-page-purge"
    Set q.ContextJSON = "{}", q.State = "answered", q.AskedAt = askedAt
    Set sc = q.%Save()
    Quit:$$$ISERR(sc) ""
    Set runKey = "ut" _ $JOB _ tag
    Set run = ##class(Shutter.Store.AgentRun).%New()
    Set run.Role = "explain", run.MemberCode = "explain", run.QuestionId = q.QuestionId, run.EnsMessageId = runKey
    Set run.StartedAt = askedAt, run.Status = "ok"
    Set sc = run.%Save()
    Quit:$$$ISERR(sc) ""
    Set sc = ##class(Shutter.Bridge.ToolCall).Append(runKey, "SearchKnowledge", "{}", 1, 1, "typed text")
    Quit:$$$ISERR(sc) ""
    Quit q.QuestionId
}

/// What is left of a question of the test's: the question, its runs and their tool calls, as q|runs|calls.
ClassMethod Left(qid As %String, runKey As %String) As %String
{
    Set q = 0, runs = 0, calls = 0
    &sql(SELECT COUNT(*) INTO :q FROM Shutter_Store.PageQuestion WHERE QuestionId = :qid)
    &sql(SELECT COUNT(*) INTO :runs FROM Shutter_Store.AgentRun WHERE QuestionId = :qid)
    &sql(SELECT COUNT(*) INTO :calls FROM Shutter_Bridge.ToolCall WHERE RunKey = :runKey)
    Quit (+q) _ "|" _ (+runs) _ "|" _ (+calls)
}

/// Every row of the test's.
ClassMethod Clear(qids As %List, runKeys As %List)
{
    For i = 1:1:$LISTLENGTH(qids) {
        Set qid = $LIST(qids, i)
        &sql(DELETE FROM Shutter_Store.AgentRun WHERE QuestionId = :qid)
        &sql(DELETE FROM Shutter_Store.PageQuestion WHERE QuestionId = :qid)
    }
    For i = 1:1:$LISTLENGTH(runKeys) {
        Set key = $LIST(runKeys, i)
        &sql(DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey = :key)
        Kill ^Shutter.Counter("toolcall", key)
    }
}

/// With the task's 30 retention days, a question asked 31 days ago goes with its run and tool call, and one asked 29
/// days ago stays with both.
Method TestOldGoesNewStays()
{
    Set time = "Shutter.Util.Time"
    Set old = ..Ask("o", $CLASSMETHOD(time, "FromNow", -86400 * 31), .oldKey)
    Set new = ..Ask("n", $CLASSMETHOD(time, "FromNow", -86400 * 29), .newKey)
    Do $$$AssertTrue((old '= "") && (new '= ""), "two questions with a run and a tool call each")
    Do $$$AssertEquals(..Left(old, oldKey) _ " " _ ..Left(new, newKey), "1|1|1 1|1|1", "both there before")
    Set task = ##class(Shutter.Util.RetentionTask).%New()
    Set task.RetentionDays = 30
    Set n = ##class(Shutter.Store.PageQuestion).PurgeBefore(task.Cutoff(), .failed)
    Do $$$AssertTrue(n >= 1, "at least the old one went: " _ n)
    Do $$$AssertEquals(failed, 0, "none failed")
    Do $$$AssertEquals(..Left(old, oldKey), "0|0|0", "the old question, its run and its tool call are gone")
    Do $$$AssertEquals($DATA(^Shutter.Counter("toolcall", oldKey)), 0, "and its run's tool call counter")
    Do $$$AssertEquals(..Left(new, newKey), "1|1|1", "the newer one stays with its run and tool call")
    Do $$$AssertEquals(##class(Shutter.Store.PageQuestion).PurgeBefore(""), 0, "no cutoff takes nothing")
    Do ..Clear($LISTBUILD(old, new), $LISTBUILD(oldKey, newKey))
}

/// A case's run that happens to carry the same question id is a case question's, and stays.
Method TestACaseRunStays()
{
    Set old = ..Ask("c", "1900-01-01T00:00:00Z", .key)
    Set caseRun = ##class(Shutter.Store.AgentRun).%New()
    Set caseRun.Role = "explain", caseRun.QuestionId = old, caseRun.EnsMessageId = key _ "k"
    Set caseRun.Case = ##class(Shutter.Store.Case).%New()
    Set caseRun.Case.CaseId = "C-UT" _ $JOB, caseRun.Case.Receiver = "ut-page-purge", caseRun.Case.OperationKey = "ut-page-purge"
    Set sc = caseRun.%Save()
    Do $$$AssertStatusOK(sc, "a run with a case and the same question id")
    Set n = ##class(Shutter.Store.PageQuestion).PurgeBefore("1900-01-02T00:00:00Z", .failed)
    Do $$$AssertEquals(n _ "|" _ failed, "1|0", "the test's question went")
    Set left = 0, rid = caseRun.%Id()
    &sql(SELECT COUNT(*) INTO :left FROM Shutter_Store.AgentRun WHERE ID = :rid)
    Do $$$AssertEquals(+left, 1, "the case's run stays")
    Set cid = caseRun.Case.%Id()
    Do ##class(Shutter.Store.AgentRun).%DeleteId(rid), ##class(Shutter.Store.Case).%DeleteId(cid)
    Do ..Clear($LISTBUILD(old), $LISTBUILD(key))
}

}
