/// A key typed into an agent item's Model or ProviderConfig setting by mistake is shown and stored as "hidden"
/// everywhere, by the rule the Portal Guide uses, and a run with one is refused before anything is looked up with it.
/// A real model id is never hidden. The key-shaped values are joined from two parts, so the repository's secret scan does
/// not take the source for a leaked key.
Class Shutter.Test.KeyMask Extends %UnitTest.TestCase
{

Parameter KEY = "PAS^HOSP^MRN-UT41^ENC-UT41^admit^2026-11-08T01:00:00Z";

Property CaseRowId As %String;

Method OnAfterAllTests() As %Status
{
    If ..CaseRowId '= "" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.AgentRun WHERE ""Case"" = ?", ..CaseRowId)
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", ..CaseRowId)
        Kill ^Shutter.Counter("event", ..CaseRowId)
        If ##class(Shutter.Store.Case).%ExistsId(..CaseRowId) Do ##class(Shutter.Store.Case).%DeleteId(..CaseRowId)
    }
    Quit $$$OK
}

/// The test's key-shaped values: an Anthropic key, an OpenAI project key and other shapes the guide hides.
ClassMethod Keys() As %List
{
    Quit $LISTBUILD("sk-" _ "ant-api03-NOTAREALKEY000", "sk-" _ "proj-NOTAREALKEY111", "AKIA" _ "IOSFODNN7EXAMPLE", "ghp_" _ "0123456789abcdefABCDEF", "hf_" _ "AbCdEf", "d41d8cd98f00b204" _ "e9800998ecf8427e")
}

/// Real model ids, and every model the price table holds: none is hidden.
ClassMethod Models() As %List
{
    Set l = $LISTBUILD("claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-sonnet-4-6", "claude-sonnet-5-5-20261101", "anthropic.claude-sonnet-5-5-20261101-v1:0", "us.anthropic.claude-opus-5-5-v1:0", "gpt-4.1", "gpt-4.1-mini", "gpt-4o-2024-08-06", "o4-mini", "gemini-2.5-pro", "mock", "Shutter", "OpenAI", "AI.LLM.Shutter", "AI.LLM.OpenAI")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Model FROM Shutter_Store.ModelPrice")
    While rs.%Next() { Set l = l _ $LISTBUILD(rs.%Get("Model")) }
    Set m = $GET(^Shutter.Config("aihub", "model"))
    If m '= "" Set l = l _ $LISTBUILD(m)
    Quit l
}

/// Real model ids written as a name and a version after "@", as one cloud names its models: an address word the rule
/// hides in other settings, but never a key in a Model.
ClassMethod ModelsAt() As %List
{
    Quit $LISTBUILD("gemini-1.5-pro@001", "claude-sonnet-5-5@20261101", "mistral-large@2407")
}

/// One rule: the guide's check and Shutter.Util.Secret's agree on every value, key-shaped or not.
Method TestTheGuidesRule()
{
    Set s = "Shutter.Util.Secret", g = "Shutter.Portal.Guide"
    Set all = ..Keys() _ ..Models() _ $LISTBUILD("someone@example.org", "tcp://10.0.0.1:2575", "task-runner", "Asia/Kolkata", "120", "")
    For i = 1:1:$LISTLENGTH(all) {
        Set v = $LISTGET(all, i)
        Do $$$AssertEquals($CLASSMETHOD(s, "Looks", v), $CLASSMETHOD(g, "LooksSecret", v), "the same answer for " _ v)
        Do $$$AssertEquals($CLASSMETHOD(s, "Clean", v), $CLASSMETHOD(g, "Clean", v), "and the same value shown")
    }
    Set keys = ..Keys()
    For i = 1:1:$LISTLENGTH(keys) Do $$$AssertEquals($CLASSMETHOD(s, "Clean", $LISTGET(keys, i)), "hidden", "a key reads hidden (" _ i _ ")")
}

/// A real model id, or a configuration's name, is never hidden.
Method TestARealModelShows()
{
    Set models = ..Models()
    For i = 1:1:$LISTLENGTH(models) {
        Set v = $LISTGET(models, i)
        Do $$$AssertEquals(##class(Shutter.Util.Secret).Clean(v), v, "shown as it is: " _ v)
    }
    Set models = ..Models() _ ..ModelsAt()
    For i = 1:1:$LISTLENGTH(models) {
        Set v = $LISTGET(models, i)
        Do $$$AssertNotTrue(##class(Shutter.Util.Secret).LooksModel(v), "not a key as a Model: " _ v)
        Do $$$AssertEquals(##class(Shutter.Util.Secret).CleanModel(v), v, "a Model shown as it is: " _ v)
    }
    // The guide's card shows such a Model as it is too, so the two agree.
    Set v = $LISTGET(..ModelsAt(), 1)
    Set r = ##class(Shutter.Portal.Guide).Runs({"model": (v), "providerConfig": "", "agentClass": ""}, "", "AI.LLM.Shutter", "model-instance", 0)
    Do $$$AssertEquals(r.model, v, "the guide's card shows " _ v)
    // Every key shape still reads as one in a Model, and an address in any other setting is still hidden.
    Set keys = ..Keys()
    For i = 1:1:$LISTLENGTH(keys) Do $$$AssertEquals(##class(Shutter.Util.Secret).CleanModel($LISTGET(keys, i)), "hidden", "a key in a Model reads hidden (" _ i _ ")")
    For v = "https://user:pw@host/", "tcp://10.0.0.1:2575", "secret://Shutter.Anthropic#key" Do $$$AssertEquals(##class(Shutter.Util.Secret).CleanModel(v), "hidden", "an address in a Model reads hidden: " _ v)
    Do $$$AssertEquals(##class(Shutter.Util.Secret).Clean("someone@example.org"), "hidden", "an address elsewhere stays hidden")
}

/// A Model written as name@version is used, shown and stored as it is: not refused, not hidden, not taken out of an error.
Method TestAModelWithAVersionIsUsed()
{
    Set v = $LISTGET(..ModelsAt(), 1)
    Set request = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Set request.ModeOverride = "live"
    Set op = {"AgentClass": "Shutter.Agent.Conformance", "Runner": "Shutter.Bridge.Runner.AIHub", "Mode": "live", "ProviderConfig": "OpenAI", "Model": (v), "MaxIterations": 8, "TokenBudget": 120000, "RequestTimeoutSeconds": 120}
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(request, op)
    Do $$$AssertEquals(##class(Shutter.Util.Secret).MaskSpec(spec), "", "not refused")
    Do $$$AssertEquals(spec.Model, v, "and used as set")
    Set r = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r.Model = v, r.ProviderConfig = "OpenAI", r.Error = "the provider has no model " _ v
    Do ##class(Shutter.Util.Secret).MaskResponse(r, $LISTBUILD("OpenAI"), v)
    Do $$$AssertEquals(r.Model _ "|" _ r.Error, v _ "|the provider has no model " _ v, "shown in the response and its error")
}

/// The run's spec: a key-shaped ProviderConfig or Model becomes "hidden" before any runner sees it, and the setting is
/// named for the refusal, which never repeats the value. A real model and configuration are left as they are.
Method TestTheSpecIsMasked()
{
    Set k1 = $LISTGET(..Keys(), 1), k2 = $LISTGET(..Keys(), 2)
    Set request = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Set request.ModeOverride = "live"
    Set op = {"AgentClass": "Shutter.Agent.Conformance", "Runner": "Shutter.Bridge.Runner.AIHub", "Mode": "live", "ProviderConfig": (k1), "Model": (k2), "MaxIterations": 8, "TokenBudget": 120000, "RequestTimeoutSeconds": 120}
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(request, op)
    Set keyed = ##class(Shutter.Util.Secret).MaskSpec(spec)
    Do $$$AssertEquals(keyed, "ProviderConfig", "the first key-shaped setting is named")
    Do $$$AssertEquals(spec.ProviderConfig _ "|" _ spec.Model, "hidden|hidden", "neither value is left in the spec")
    Set why = ##class(Shutter.Util.Secret).Refusal(keyed)
    Do $$$AssertEquals(why, "the item's ProviderConfig setting looks like a key; it was not used", "the refusal")
    Do $$$AssertNotTrue((why [ k1) || (why [ k2), "and it repeats neither value")
    Set op.ProviderConfig = "OpenAI", op.Model = k2
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(request, op)
    Do $$$AssertEquals(##class(Shutter.Util.Secret).MaskSpec(spec), "Model", "a key in Model alone is named")
    Do $$$AssertEquals(spec.ProviderConfig _ "|" _ spec.Model, "OpenAI|hidden", "the configuration's name stays")
    Set op.Model = "gpt-4.1"
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(request, op)
    Do $$$AssertEquals(##class(Shutter.Util.Secret).MaskSpec(spec), "", "nothing key-shaped")
    Do $$$AssertEquals(spec.ProviderConfig _ "|" _ spec.Model, "OpenAI|gpt-4.1", "a real model and configuration are used as set")
}

/// The response as it leaves the operation: Model and ProviderConfig hidden, the item's value taken out of the Error
/// (as the Config Store's error repeated it), and a real model and the rest of the error left alone.
Method TestTheResponseIsMasked()
{
    Set k1 = $LISTGET(..Keys(), 1), k2 = $LISTGET(..Keys(), 2)
    Set r = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r.Model = k2, r.ProviderConfig = k1
    Set r.Error = "ERROR #5809: Object to Load not found, class '%ConfigStore.Configuration', ID 'AI.LLM." _ k1 _ "'"
    Do ##class(Shutter.Util.Secret).MaskResponse(r, $LISTBUILD(k1, k2))
    Do $$$AssertEquals(r.Model _ "|" _ r.ProviderConfig, "hidden|hidden", "model and configuration hidden")
    Do $$$AssertEquals(r.Error, "ERROR #5809: Object to Load not found, class '%ConfigStore.Configuration', ID 'AI.LLM.hidden'", "the value is out of the error, the rest kept")
    Set r = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r.Model = "claude-opus-5-5", r.ProviderConfig = "Shutter", r.Error = "timeout after 120 s at https://api.example.org/v1"
    Do ##class(Shutter.Util.Secret).MaskResponse(r, $LISTBUILD("Shutter", "claude-opus-5-5"))
    Do $$$AssertEquals(r.Model _ "|" _ r.ProviderConfig, "claude-opus-5-5|Shutter", "a real model and configuration shown")
    Do $$$AssertEquals(r.Error, "timeout after 120 s at https://api.example.org/v1", "and an error with no key is untouched")
}

/// The live runner never looks a key-shaped name up in the Config Store, and its refusal repeats no value. The runner is
/// the aihub module's, so the core edition skips this.
Method TestTheRunnerDoesNotLookItUp()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub") {
        Do $$$AssertSkipped("the live runner is not installed (the core edition)")
        Quit
    }
    Set k1 = $LISTGET(..Keys(), 1), text = ""
    Try {
        Do ##class(Shutter.Bridge.Runner.AIHub).ProviderFrom(k1, .model)
    } Catch ex {
        Set text = ex.DisplayString()
    }
    Do $$$AssertTrue(text [ "looks like a key; it was not used", "refused: " _ text)
    Do $$$AssertNotTrue(text [ k1, "without the value")
    Do $$$AssertNotTrue(text [ "ConfigStore", "and not after a lookup")
}

/// A stored run holds "hidden" for a key-shaped Model or ProviderConfig, and the health route's last live run shows it
/// so; a real model is stored as it is. Rows stored before the rule are repaired at install, their Error too.
Method TestTheStoredRun()
{
    Set k1 = $LISTGET(..Keys(), 1), k2 = $LISTGET(..Keys(), 2)
    Set op = {"operation_key": (..#KEY), "encounter_id": "ENC-UT41", "patient_id": "MRN-UT41", "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "bed": null, "event_time": "2026-11-08T01:00:00Z", "source_system": "PAS", "source_message_id": "UT41", "payload_digest": "sha256:ut41"}
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "Delivery unavailable (test)", "", "", "policy", .case, .opened)
    Do $$$AssertStatusOK(sc, "a case for the runs")
    Quit:$$$ISERR(sc)
    Set ..CaseRowId = case.%Id()
    Set r = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r.Status = "model_error", r.Mode = "live", r.Model = k2, r.ProviderConfig = k1, r.AgentClass = "Shutter.Agent.Impact", r.StartedAt = "2099-01-01T00:00:00Z", r.ResultJSON = "{}"
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, "", "member", "impact", r, "", .run)
    Do $$$AssertStatusOK(sc, "the run is stored")
    Do $$$AssertEquals(run.Model _ "|" _ run.ProviderConfig, "hidden|hidden", "stored as hidden")
    Set last = ##class(Shutter.Store.AgentRun).LastLive()
    Do $$$AssertTrue($ISOBJECT(last) && (last.model = "hidden"), "the health route's last live run: " _ $SELECT($ISOBJECT(last): last.%ToJSON(), 1: "none"))
    // A row as an older build stored it, written past the class.
    Set id = run.%Id(), err = "ID 'AI.LLM." _ k1 _ "'", run = ""
    &sql(UPDATE Shutter_Store.AgentRun SET Model = :k2, ProviderConfig = :k1, Error = :err WHERE ID = :id)
    Do $$$AssertTrue(##class(Shutter.Util.Secret).RepairRuns() >= 1, "the repair changes it")
    Set run = ##class(Shutter.Store.AgentRun).%OpenId(id, 0)
    Do $$$AssertEquals(run.Model _ "|" _ run.ProviderConfig _ "|" _ run.Error, "hidden|hidden|ID 'AI.LLM.hidden'", "and the error no longer holds the value")
    Set r2 = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r2.Status = "ok", r2.Mode = "replay", r2.Model = "claude-opus-5-5", r2.ProviderConfig = "Shutter", r2.StartedAt = "2026-11-08T01:00:06Z", r2.ResultJSON = "{}"
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, "", "member", "impact", r2, "", .run2)
    Do $$$AssertEquals(run2.Model _ "|" _ run2.ProviderConfig, "claude-opus-5-5|Shutter", "a real model is stored as it is")
}

/// Every place that echoes the item's settings goes through the one rule: the item's start line and the run's last lines
/// (Agent.cls), the settings route, and the install's repair. Read from the methods' code lines (a comment naming the
/// rule does not count), as the production's own lines can only be seen with the item running (the end-to-end check,
/// tests/e2e/key_mask_check.py, reads those).
Method TestEveryEchoUsesTheRule()
{
    Do $$$AssertNotTrue(..Calls("    // Shutter.Util.Secret).MaskSpec(spec)", "MaskSpec"), "a comment is not a call")
    Do $$$AssertTrue(..Calls("    Set k = ##class(Shutter.Util.Secret).MaskSpec(spec)", "MaskSpec"), "a code line is")
    For pair = $LISTBUILD("Shutter.Bridge.Operation.Agent||OnInit", "CleanModel"), $LISTBUILD("Shutter.Bridge.Operation.Agent||OnInit", "Clean"), $LISTBUILD("Shutter.Bridge.Operation.Agent||OnAgentRequest", "MaskSpec"), $LISTBUILD("Shutter.Bridge.Operation.Agent||OnAgentRequest", "MaskResponse"), $LISTBUILD("Shutter.API.Dispatch||Settings", "CleanModel"), $LISTBUILD("Shutter.API.Dispatch||Settings", "Clean"), $LISTBUILD("Shutter.Setup||InstallStatus", "RepairRuns") {
        Set m = $LIST(pair, 1), call = $LIST(pair, 2)
        Set def = ##class(%Dictionary.MethodDefinition).%OpenId(m)
        Do $$$AssertTrue($ISOBJECT(def), m _ " reads")
        Continue:'$ISOBJECT(def)
        Do def.Implementation.Rewind()
        Set code = def.Implementation.Read(3000000)
        Do $$$AssertTrue(..Calls(code, call), m _ " calls Shutter.Util.Secret's " _ call)
    }
}

/// Whether <var>code</var> calls Shutter.Util.Secret's <var>method</var> on a line that is not a comment.
ClassMethod Calls(code As %String, method As %String) As %Boolean
{
    Set code = $TRANSLATE(code, $CHAR(13))
    For i = 1:1:$LENGTH(code, $CHAR(10)) {
        Set line = $ZSTRIP($PIECE(code, $CHAR(10), i), "<W")
        Continue:(($EXTRACT(line, 1, 2) = "//") || ($EXTRACT(line, 1) = ";") || ($EXTRACT(line, 1, 2) = "#;"))
        If line [ ("##class(Shutter.Util.Secret)." _ method _ "(") Return 1
    }
    Quit 0
}

}
