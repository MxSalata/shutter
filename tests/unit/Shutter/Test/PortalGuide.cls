/// The demo's portal page (CONTRACTS 16, v1.41): it escapes what began in a message, says so when there is no board case,
/// links only to what the demo's edge leaves open, and shows nothing it can't read.
Class Shutter.Test.PortalGuide Extends %UnitTest.TestCase
{

/// An agent class's MODEL, for the model a test item falls back to.
Parameter MODEL = "test-model-1";

/// The test production the item reads use, saved and removed by each test that needs it.
Parameter PRODUCTION = "Shutter.Test.GuideProduction";

Method Facts() As %DynamicObject
{
    Quit {"user": "demo-trace", "namespace": "SHUTTER", "updated": "13:44:30", "shutter": "running", "hospital": "stopped", "messages": 214, "queued": 0, "errors": 3,
        "feature": {"caseId": "C-000034", "session": "641", "members": 4},
        "cases": [{"caseId": "C-000041", "state": "blocked", "story": "<script>alert('x')</script> & more", "session": "650"}, {"caseId": "C-000040", "state": "resolved", "story": "Fine", "session": "not-a-number"}],
        "agents": [{"member": "conformance", "lastAt": "2026-11-04T13:44:30Z"}]}
}

Method TestEscapesWhatBeganInAMessage()
{
    Set h = ##class(Shutter.Portal.Guide).Html(..Facts(), "/csp/healthshare/shutter/")
    Do $$$AssertNotTrue(h [ "<script", "no script reaches the page")
    Do $$$AssertTrue(h [ "&lt;script&gt;", "the headline is shown as text")
    Do $$$AssertNotTrue(h [ "SESSIONID=not-a-number", "a session that isn't a number makes no link")
}

Method TestWhatItSays()
{
    Set guide = "Shutter.Portal.Guide"
    Set h = $CLASSMETHOD(guide, "Html", ..Facts(), "/csp/healthshare/shutter/")
    Do $$$AssertTrue(h [ "C-000034: the escalated S8 case", "the board's case by its number")
    Do $$$AssertTrue(h [ "4 agents, each in its own lane", "with the agents it counted")
    Do $$$AssertTrue(h [ "EnsPortal.VisualTrace.zen?SESSIONID=641", "and its trace")
    Do $$$AssertTrue(h [ ">Stopped<", "a stopped production says so")
    Do $$$AssertTrue(h [ "Agent Conformance", "the agents by name")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Story", "Blocked by the gate: Blocked: no receipt", ""), "Blocked by the gate: no receipt", "a blocked case says so once")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Story", "", "Ward unavailable"), "Ward unavailable", "a case with no headline shows its failure")
    Do $$$AssertTrue(h [ "last 2026-11-04 13:44 UTC", "and when each last ran, with its date, since a kept run can be days old")
    Do $$$AssertNotTrue(h [ "Mock-up", "no mock-up's words")
    Set f = ..Facts()
    Set f.feature = "", f.cases = [], f.agents = []
    Set f.hospital = "", f.errors = ""
    Set h = $CLASSMETHOD(guide, "Html", f, "/csp/healthshare/shutter/")
    Do $$$AssertTrue(h [ "No board case on this instance yet", "no S8 case yet, and it says so")
    Do $$$AssertTrue(h [ "No case on this instance yet", "no cases")
    Do $$$AssertTrue(h [ "No agent has run on this instance yet", "no agents")
    Do $$$AssertNotTrue(h [ "Hospital production", "a state it can't read leaves its tile out")
    Do $$$AssertNotTrue(h [ "Errors logged", "as does a count")
}

/// The edge's allow-list: the portal's three pages in both namespaces, the Visual Trace in Shutter's, and the app.
Method TestLinksOnlyToWhatTheEdgeLeavesOpen()
{
    Set h = ##class(Shutter.Portal.Guide).Html(..Facts(), "/csp/healthshare/shutter/")
    Set m = ##class(%Regex.Matcher).%New("href='([^']*)'", h), n = 0
    While m.Locate() {
        Set href = m.Group(1), n = n + 1
        Set ok = (href = "/shutter/index.html")
        If 'ok Set ok = ##class(%Regex.Matcher).%New("^/csp/healthshare/(shutter|hospital)/EnsPortal\.(ProductionMonitor|MessageViewer|EventLog)\.zen$", href).Locate()
        If 'ok Set ok = ##class(%Regex.Matcher).%New("^/csp/healthshare/shutter/EnsPortal\.VisualTrace\.zen\?SESSIONID=[0-9]+$", href).Locate()
        Do $$$AssertTrue(ok, "open on the demo's edge: " _ href)
    }
    Do $$$AssertTrue(n >= 8, "it has its links: " _ n)
    Do $$$AssertNotTrue(h [ "<form", "no form")
    Do $$$AssertNotTrue(h [ "<script", "no script")
    Do $$$AssertTrue(h [ "http-equiv='refresh'", "a plain refresh")
}

/// Read from this instance, each figure or empty; a namespace that does not exist reads as unknown, not as an error.
Method TestFactsAreReadOrEmpty()
{
    Set guide = "Shutter.Portal.Guide"
    Set f = $CLASSMETHOD(guide, "Facts")
    Do $$$AssertEquals(f.user, $USERNAME, "the caller")
    Do $$$AssertEquals(f.namespace, $NAMESPACE, "the namespace")
    Do $$$AssertTrue(f.cases.%IsA("%DynamicArray") && f.agents.%IsA("%DynamicArray"), "the lists are lists")
    Do $$$AssertEquals($CLASSMETHOD(guide, "ProductionState", "NO_SUCH_NAMESPACE"), "", "a namespace that isn't there")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Count", "SELECT COUNT(*) AS n FROM No_Such.Table"), "", "a count that can't run")
}

/// The Operations panel's allow-list: only the settings it names, never one whose name or value looks like a secret or an
/// address, even when a list names it.
Method TestOperationSettingsAllowList()
{
    Set guide = "Shutter.Portal.Guide"
    Kill s
    Set s("Host", "FailureTimeout") = 0, s("Host", "RetryInterval") = 5, s("Adapter", "ResponseTimeout") = 15
    Set s("Adapter", "Credentials") = "DownstreamAPI", s("Adapter", "SSLConfig") = "TLS", s("Adapter", "HTTPServer") = "receiver.example"
    Set s("Host", "ReplyCodeActions") = "secret://Shutter.Anthropic#key", s("Host", "From") = "someone@example.org"
    Set shown = $CLASSMETHOD(guide, "Shown", .s), json = shown.%ToJSON()
    Do $$$AssertEquals(shown.%Size(), 3, "three of the eight: " _ json)
    Do $$$AssertEquals(shown.%Get(0).name, "FailureTimeout", "in the list's order")
    Do $$$AssertEquals(shown.%Get(0).value, "0", "with its value")
    For word = "Credentials", "DownstreamAPI", "SSLConfig", "HTTPServer", "receiver.example", "secret://", "ReplyCodeActions", "example.org" {
        Do $$$AssertNotTrue(json [ word, "never shown: " _ word)
    }
    // A list that names a secret's setting still shows nothing of it.
    Kill s
    Set s("Host", "ApiToken") = "abc", s("Adapter", "Credentials") = "x", s("Host", "SMTPServer") = "mail", s("Host", "FailureTimeout") = 7
    Set shown = $CLASSMETHOD(guide, "Shown", .s, "Host:ApiToken,Adapter:Credentials,Host:SMTPServer,Host:FailureTimeout")
    Do $$$AssertEquals(shown.%ToJSON(), "[{""name"":""FailureTimeout"",""value"":7}]", "only the harmless one: " _ shown.%ToJSON())
    Do $$$AssertTrue($CLASSMETHOD(guide, "Hidden", "ReplyCodeActions", "sk-ant-api03-abc"), "a key's prefix is hidden")
    Do $$$AssertTrue($CLASSMETHOD(guide, "Hidden", "RetryInterval", "https://user:pw@host/"), "an address is hidden")
    Do $$$AssertNotTrue($CLASSMETHOD(guide, "Hidden", "ReplyCodeActions", ":?R=RF,:?E=S,:~=S,:?A=C,:*=S"), "reply codes are shown")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Clean", "sk-ant-api03-abc"), "hidden", "a Model set to a key by mistake")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Clean", "claude-opus-5-5"), "claude-opus-5-5", "a model id")
}

/// The model in effect and where it comes from, in the runner's order, and a configuration it may not read says so.
Method TestWhatRunsAnAgent()
{
    Set guide = "Shutter.Portal.Guide"
    Set r = $CLASSMETHOD(guide, "Runs", {"model": "model-item", "providerConfig": "", "agentClass": ""}, "", "AI.LLM.Shutter", "model-instance", 0)
    Do $$$AssertEquals(r.model, "model-item", "the item's Model first")
    Do $$$AssertEquals(r.from, "from the item's Model setting", "and says so")
    Do $$$AssertEquals(r.config, "AI.LLM.Shutter", "with the instance's configuration")
    Set r = $CLASSMETHOD(guide, "Runs", {"model": "", "providerConfig": "", "agentClass": ""}, "", "AI.LLM.Shutter", "model-instance", 0)
    Do $$$AssertEquals(r.model, "model-instance", "then the instance's configuration, from its record when the Config Store may not be read")
    Do $$$AssertEquals(r.from, "from the instance's configuration, SHUTTER_MODEL", "named as SHUTTER_MODEL")
    Do $$$AssertTrue(r.provider [ "anthropic", "the provider Shutter's setup writes: " _ r.provider)
    Set r = $CLASSMETHOD(guide, "Runs", {"model": "", "providerConfig": "Other", "agentClass": ""}, "", "AI.LLM.Shutter", "model-instance", 0)
    Do $$$AssertEquals(r.config, "AI.LLM.Other", "the item's configuration, under AI.LLM")
    Do $$$AssertEquals(r.model, "not readable", "whose model it may not read")
    Do $$$AssertEquals(r.provider, "not readable", "nor its provider")
    Set r = $CLASSMETHOD(guide, "Runs", {"model": "", "providerConfig": "", "agentClass": ($CLASSNAME())}, "", "", "", 0)
    Do $$$AssertEquals(r.model, "test-model-1", "with no configuration, the agent class's MODEL")
    Do $$$AssertEquals(r.from, "from the agent class " _ $CLASSNAME(), "named")
    Do $$$AssertEquals(r.config, "", "and no configuration")
    Set r = $CLASSMETHOD(guide, "Runs", {"model": "", "providerConfig": "", "agentClass": "No.Such.Agent"}, "", "", "", 0)
    Do $$$AssertEquals(r.model, "none", "an agent class that isn't there")
    Set r = $CLASSMETHOD(guide, "Runs", {"model": "model-item", "providerConfig": "", "agentClass": ""}, "ShutterMock", "AI.LLM.Shutter", "model-instance", 0)
    Do $$$AssertEquals(r.model, "mock", "the API mimic before anything else")
    Do $$$AssertEquals(r.config, "AI.LLM.ShutterMock", "with its configuration")
    Set r = $CLASSMETHOD(guide, "Runs", {"model": "sk-ant-api03-abc", "providerConfig": "secret://x", "agentClass": ""}, "", "", "", 0)
    Do $$$AssertEquals(r.model, "hidden", "a key in the Model setting is never shown")
    Do $$$AssertNotTrue(r.%ToJSON() [ "sk-ant", "anywhere")
    Do $$$AssertNotTrue(r.%ToJSON() [ "secret://", "nor a wallet reference")
}

/// A test production's items, read as the page reads them: the agent item's settings and limits, the operation's class and
/// allowed settings, and nothing of a credential or a secret-looking value.
Method TestReadsTheProductionItems()
{
    Set guide = "Shutter.Portal.Guide"
    Do ..RemoveProduction()
    Set sc = ..MakeProduction()
    Do $$$AssertStatusOK(sc, "the test production is saved")
    Try {
        Set items = $CLASSMETHOD(guide, "Items", ..#PRODUCTION), json = items.%ToJSON()
        Do $$$AssertEquals(items.readable, 1, "read: " _ json)
        Do $$$AssertEquals(items.production, ..#PRODUCTION, "that production")
        Do $$$AssertEquals(items.agents.%Size(), 1, "one agent item")
        Do $$$AssertEquals(items.operations.%Size(), 1, "one other operation; the service is left out")
        Set a = items.agents.%Get(0)
        Do $$$AssertEquals(a.name, "Test Agent", "the agent item")
        Do $$$AssertEquals(a.model, "test-model-2", "its Model")
        Do $$$AssertEquals(a.modelFrom, "from the item's Model setting", "from the item")
        Do $$$AssertEquals(a.mode, "replay", "the mode it sets")
        Do $$$AssertEquals(a.modeSetting, "replay", "set on the item")
        Do $$$AssertEquals(a.turns, 3, "its MaxIterations")
        Do $$$AssertEquals(a.budget, 120000, "TokenBudget's default")
        Do $$$AssertEquals(a.timeout, 120, "RequestTimeoutSeconds's default")
        Do $$$AssertEquals(a.agentClass, "Shutter.Agent.Conformance", "its agent class")
        Do $$$AssertEquals(a.pool, 2, "its pool")
        Set o = items.operations.%Get(0)
        Do $$$AssertEquals(o.name, "Test Out", "the operation")
        Do $$$AssertEquals(o.class, "Shutter.Operation.Ward", "its class")
        Do $$$AssertEquals(''o.enabled, 0, "disabled")
        Set shown = ""
        Set it = o.settings.%GetIterator()
        While it.%GetNext(, .one) { Set shown = shown _ one.name _ "=" _ one.value _ ";" }
        Do $$$AssertTrue(shown [ "FailureTimeout=7;", "its FailureTimeout: " _ shown)
        Do $$$AssertTrue(shown [ "ResponseTimeout=", "an adapter's setting, from the class's default: " _ shown)
        For word = "TestCreds", "Credentials", "secret://", "ReplyCodeActions", "receiver.example", "HTTPServer", "SSLConfig", "sk-ant" {
            Do $$$AssertNotTrue(json [ word, "never read out: " _ word)
        }
        Set h = $CLASSMETHOD(guide, "Html", {"user": "demo-trace", "namespace": "SHUTTER", "updated": "", "cases": [], "agents": [], "items": (items)}, "/csp/healthshare/shutter/")
        Do $$$AssertTrue(h [ "<b>Test Agent</b>", "the agent's card")
        Do $$$AssertTrue(h [ "test-model-2<span>from the item&#39;s Model setting</span>", "its model and where it comes from")
        Do $$$AssertTrue(h [ "<b>Test Out</b>", "the operation's card")
        Do $$$AssertNotTrue(h [ "TestCreds", "no credential on the page")
        Set none = $CLASSMETHOD(guide, "Items", "No.Such.Production")
        Do $$$AssertEquals(none.readable, 1, "a production with no items is read")
        Do $$$AssertEquals(none.agents.%Size() + none.operations.%Size(), 0, "as empty")
    } Catch ex {
        Do $$$AssertStatusOK(ex.AsStatus(), "the reads")
    }
    Do ..RemoveProduction()
}

/// The panels as drawn: escaped, with the line on where a model is set, and a row it couldn't read says so.
Method TestDrawsTheItemPanels()
{
    Set f = ..Facts()
    Set f.items = {"production": "Shutter.Production", "readable": 1,
        "agents": [{"name": "Agent <b>X</b>", "enabled": 1, "pool": 1, "model": "claude-opus-5-5", "modelFrom": "from the instance's configuration, SHUTTER_MODEL", "config": "AI.LLM.Shutter", "provider": "anthropic", "mode": "replay", "modeSetting": "auto", "turns": 8, "budget": 120000, "timeout": 120, "agentClass": "", "lastAt": "2026-11-04T13:44:30Z"}, {"name": "Agent Gone", "unreadable": true}],
        "operations": [{"name": "Downstream Out", "class": "Shutter.Operation.Ward", "enabled": 0, "pool": 1, "settings": [{"name": "FailureTimeout", "value": "<i>0</i>"}, {"name": "ReplyCodeActions", "value": ""}]}]}
    Set h = ##class(Shutter.Portal.Guide).Html(f, "/csp/healthshare/shutter/")
    Do $$$AssertTrue(h [ "Agents in Shutter.Production", "the agents' panel")
    Do $$$AssertTrue(h [ "Agent &lt;b&gt;X&lt;/b&gt;", "a name is escaped")
    Do $$$AssertTrue(h [ "&lt;i&gt;0&lt;/i&gt;", "as is a setting's value")
    Do $$$AssertTrue(h [ "model_provider anthropic", "the provider")
    Do $$$AssertTrue(h [ "auto, as the instance decides; recorded answers, no model called", "the mode and why")
    Do $$$AssertTrue(h [ "named by each request", "an item with no agent class")
    Do $$$AssertTrue(h [ "2026-11-04 13:44 UTC", "its last run")
    Do $$$AssertTrue(h [ "<b>Agent Gone</b></div><p class='none'>not readable</p>", "a row it couldn't read")
    Do $$$AssertTrue(h [ "<h2>Operations</h2>", "the operations' panel")
    Do $$$AssertTrue(h [ "warn'>Off", "a disabled operation says so")
    Do $$$AssertTrue(h [ "<dt>ReplyCodeActions</dt><dd>not set</dd>", "an empty setting says so")
    Do $$$AssertTrue(h [ "<dd>claude-opus-5-5<span>from the instance&#39;s configuration, SHUTTER_MODEL</span></dd>", "the model and where it comes from")
    Do $$$AssertTrue(h [ "Interoperability &gt; Configure &gt; Production, the item's Model setting); the instance's default is SHUTTER_MODEL.", "where a model is set")
    Set f.items = {"production": "Shutter.Production", "readable": 0, "agents": [], "operations": []}
    Set h = ##class(Shutter.Portal.Guide).Html(f, "/csp/healthshare/shutter/")
    Do $$$AssertTrue(h [ "not readable here", "a list it can't read says so")
}

/// Each item's last run is keyed by the item's own name, as its request header names it, not as SQL's grouping folds it.
Method TestLastRunIsByTheItemsOwnName()
{
    Set last = ##class(Shutter.Portal.Guide).LastRunByItem(), n = 0
    Set it = last.%GetIterator()
    While it.%GetNext(.item, .at) {
        Set n = n + 1
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS c FROM Ens.MessageHeader WHERE %EXACT(TargetConfigName) = ?", item)
        Do $$$AssertTrue(rs.%Next() && (rs.%Get("c") > 0), "a header names " _ item _ " exactly")
        Do $$$AssertTrue(at ? 4N1"-"2N1"-"2N1"T".E, "with a time: " _ at)
    }
    If n = 0 Do $$$AssertSkipped("no agent run with its request header on this instance")
}

Method MakeProduction() As %Status
{
    Set sc = $$$OK
    Try {
        Set p = ##class(Ens.Config.Production).%New()
        Set p.Name = ..#PRODUCTION
        Set defs = $LISTBUILD($LISTBUILD("Test Agent", "Shutter.Bridge.Operation.Agent", 2, 1, $LISTBUILD($LISTBUILD("Host", "AgentClass", "Shutter.Agent.Conformance"), $LISTBUILD("Host", "Mode", "replay"), $LISTBUILD("Host", "Model", "test-model-2"), $LISTBUILD("Host", "MaxIterations", 3))))
        Set defs = defs _ $LISTBUILD($LISTBUILD("Test Out", "Shutter.Operation.Ward", 1, 0, $LISTBUILD($LISTBUILD("Adapter", "Credentials", "TestCreds"), $LISTBUILD("Adapter", "HTTPServer", "receiver.example"), $LISTBUILD("Host", "ReplyCodeActions", "secret://Shutter.Anthropic#key"), $LISTBUILD("Host", "FailureTimeout", 7))))
        Set defs = defs _ $LISTBUILD($LISTBUILD("Test In", "Shutter.Service.API", 0, 1, ""))
        For d = 1:1:$LISTLENGTH(defs) {
            Set def = $LIST(defs, d)
            Set i = ##class(Ens.Config.Item).%New()
            Set i.Name = $LIST(def, 1), i.ClassName = $LIST(def, 2), i.PoolSize = $LIST(def, 3), i.Enabled = $LIST(def, 4), i.Production = p
            Set list = $LIST(def, 5)
            For k = 1:1:$LISTLENGTH(list) {
                Set one = $LIST(list, k), st = ##class(Ens.Config.Setting).%New()
                Set st.Target = $LIST(one, 1), st.Name = $LIST(one, 2), st.Value = $LIST(one, 3)
                Do i.Settings.Insert(st)
            }
            Do p.Items.Insert(i)
        }
        Set sc = p.%Save()
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

Method RemoveProduction()
{
    Try {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Config.Item WHERE Production = ?", ..#PRODUCTION)
        Do ##class(Ens.Config.Production).%DeleteId(..#PRODUCTION)
    } Catch ex {
    }
}

}
