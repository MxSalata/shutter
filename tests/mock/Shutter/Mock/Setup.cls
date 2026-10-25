/// Switches the API mimic on and off in this namespace, and checks it. Enable creates the web application
/// /shutter-mock (Shutter.Mock.API, unauthenticated, loopback callers only) with a role for this namespace's
/// databases, the Config Store configuration AI.LLM.ShutterMock (provider openai, base_url that web application, a
/// placeholder key) and the switch ^Shutter.Config("aihub","mock"), which Shutter.Setup MockConfig reads. Disable
/// removes all three. Enable runs on a demo instance only (the switch counts on no other), and when it fails it leaves
/// the mimic off: the switch cleared and what it had made removed, with Disable's own code. A test fixture: in
/// tests/mock, outside both IPM modules and the image.
Class Shutter.Mock.Setup
{

Parameter WEBAPP = "/shutter-mock";

Parameter CONFIG = "ShutterMock";

Parameter FQN = "AI.LLM.ShutterMock";

Parameter ROLE = "Shutter_MockClient";

/// Switch the mimic on. <var>model</var> is the model id sent on the wire (the runs are labelled mock whatever it
/// is). Refused while the agent mode is record, on an instance that is not a demo (the switch counts on a demo only,
/// Shutter.Setup MockConfig) and while UnknownUser is disabled, before anything is made. A failure after that leaves the
/// mimic off (Failed): the switch cleared, and the configuration, the web application and the role removed. Returns
/// Status() as JSON, or {"error": ...}.
ClassMethod Enable(model As %String = "mock") As %String [ SqlProc ]
{
    Try {
        If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Return {"error": "Enable needs %Admin_Secure: it creates a web application and a role"}.%ToJSON()
        If $ZCONVERT($GET(^Shutter.Config("aihub", "mode")), "L") = "record" Return {"error": "refused: the agent mode is record; set replay or live first"}.%ToJSON()
        If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub") Return {"error": "the live runner (the aihub module) is not installed"}.%ToJSON()
        If '$GET(^Shutter.Config("demo")) Return {"error": "refused: this is not a demo instance, and the mimic's switch counts on a demo only"}.%ToJSON()
        If '..UnknownUserEnabled() Return {"error": "UnknownUser is disabled on this instance, so the unauthenticated web application cannot answer"}.%ToJSON()
        If $ZSTRIP(model, "<>W") = "" Set model = "mock"
        Set ns = $NAMESPACE
        Set db = ##class(Shutter.Setup).DatabaseResource(ns), code = ##class(Shutter.Setup).DatabaseResource(ns, 1)
        Set resources = db _ ":RW" _ $SELECT((code '= "") && (code '= db): "," _ code _ ":R", 1: "")
        Set sc = ..Web(ns, resources)
        If $$$ISERR(sc) Return ..Failed("web application: " _ $SYSTEM.Status.GetErrorText(sc))
        // The address the production already reaches the downstream system at, from inside the instance.
        Set host = $GET(^Shutter.Config("downstreamHost"), $GET(^Shutter.Config("wardHost"), "127.0.0.1"))
        Set port = $GET(^Shutter.Config("downstreamPort"), $GET(^Shutter.Config("wardPort"), 52773))
        Do ##class(Shutter.Setup).RebuildDescriptorRegistry()
        If ##class(%ConfigStore.Configuration).Exists(..#FQN) Do ##class(%ConfigStore.Configuration).Delete(..#FQN)
        Set details = {"model_provider": "openai", "model": (model), "api_key": "shutter-mock-placeholder", "base_url": ("http://" _ host _ ":" _ port _ ..#WEBAPP _ "/v1")}
        Set sc = ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", ..#CONFIG, details, "Shutter API mimic", "Answers the live runner without a model (tests/mock)")
        If $$$ISERR(sc) Return ..Failed("config store: " _ $SYSTEM.Status.GetErrorText(sc))
        Set ^Shutter.Config("aihub", "mockModel") = model
        Set ^Shutter.Config("aihub", "mock") = ..#FQN
        Return ..Status()
    } Catch ex {
        Return ..Failed(ex.DisplayString())
    }
}

/// A failed Enable: the switch cleared and what Enable makes removed (Remove), so nothing of the mimic is left behind,
/// and the error as JSON.
ClassMethod Failed(error As %String) As %String [ Private ]
{
    Kill ^Shutter.Config("aihub", "mock"), ^Shutter.Config("aihub", "mockModel")
    Do ..Remove()
    Quit {"error": (error)}.%ToJSON()
}

/// Switch the mimic off: the switch first, so the next run resolves its mode as before, then its options, the
/// configuration, the web application and the role (Remove). The call log stays unless <var>clearLog</var> is 1.
/// Returns Status() as JSON, or {"error": ...} when something could not be removed.
ClassMethod Disable(clearLog As %Boolean = 0) As %String [ SqlProc ]
{
    Try {
        If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Return {"error": "Disable needs %Admin_Secure"}.%ToJSON()
        Kill ^Shutter.Config("aihub", "mock"), ^Shutter.Config("aihub", "mockModel")
        Kill ^Shutter.Config("aihub", "mockDebug"), ^Shutter.Config("aihub", "mockReplay"), ^Shutter.Config("aihub", "mockStrict")
        If clearLog Kill ^Shutter.MockLog
        Set sc = ..Remove()
        If $$$ISERR(sc) Return {"error": ($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
        Return ..Status()
    } Catch ex {
        Return {"error": (ex.DisplayString())}.%ToJSON()
    }
}

/// Removes what Enable makes beyond the switch, quietly when absent: the Config Store configuration, then in %SYS the
/// web application and the role. Shared by Disable and a failed Enable. Returns the first error met, having tried each.
ClassMethod Remove() As %Status [ Private ]
{
    Set sc = $$$OK
    Try {
        If ##class(%ConfigStore.Configuration).Exists(..#FQN) Do ##class(%ConfigStore.Configuration).Delete(..#FQN)
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        If ##class(Security.Applications).Exists(..#WEBAPP) {
            Set one = ##class(Security.Applications).Delete(..#WEBAPP)
            If $$$ISOK(sc) Set sc = one
        }
        If ##class(Security.Roles).Exists(..#ROLE) {
            Set one = ##class(Security.Roles).Delete(..#ROLE)
            If $$$ISOK(sc) Set sc = one
        }
    } Catch ex {
        If $$$ISOK(sc) Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Whether UnknownUser is enabled, read in %SYS: the unauthenticated web application answers through that account.
ClassMethod UnknownUserEnabled() As %Boolean [ Private ]
{
    Set enabled = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set sc = ##class(Security.Users).Get("UnknownUser", .user)
        If $$$ISOK(sc) Set enabled = ''$GET(user("Enabled"))
    } Catch ex {
        Set enabled = 0
    }
    Quit enabled
}

/// What is in place: the switch, the configuration (it holds no secret), the web application and the role, the
/// agent mode the instance records, the mode an item set to auto resolves to, the mode the environment would set at
/// the production's start, and the call log's length.
ClassMethod Status() As %String [ SqlProc ]
{
    Set o = {}
    Try {
        Set o.switch = ##class(Shutter.Setup).MockConfig()
        Set o.model = $GET(^Shutter.Config("aihub", "mockModel"))
        Do o.%Set("config", ##class(%ConfigStore.Configuration).Exists(..#FQN), "boolean")
        If o.config {
            Set sc = ##class(%ConfigStore.Configuration).GetDetails(..#FQN, .details, 0, 0)
            If $$$ISOK(sc) Set o."base_url" = details.%Get("base_url"), o.provider = details.%Get("model_provider")
        }
        // The switch counts on a demo instance only (Enable refuses elsewhere).
        Do o.%Set("demo", ''$GET(^Shutter.Config("demo")), "boolean")
        Set o."agent_mode" = $GET(^Shutter.Config("aihub", "mode"), "auto")
        Set o."auto_resolves_to" = ##class(Shutter.Bridge.Operation.Agent).ResolveMode("auto")
        // What the production's start applies (Shutter.Production OnStart): the mode the environment names, and
        // whether it carries a key (never the key).
        Set o."env_agent_mode" = $SYSTEM.Util.GetEnviron("SHUTTER_AGENT_MODE")
        Do o.%Set("env_key_set", $SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY") '= "", "boolean")
        Set o."log_lines" = +$GET(^Shutter.MockLog)
        Do o.%Set("replay", $GET(^Shutter.Config("aihub", "mockReplay"), 1) '= 0, "boolean")
        Do o.%Set("strict", ''$GET(^Shutter.Config("aihub", "mockStrict")), "boolean")
        Do o.%Set("debug", ''$GET(^Shutter.Config("aihub", "mockDebug")), "boolean")
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Do o.%Set("webapp", ##class(Security.Applications).Exists(..#WEBAPP), "boolean")
        Do o.%Set("role", ##class(Security.Roles).Exists(..#ROLE), "boolean")
    } Catch ex {
        Set o.error = ex.DisplayString()
    }
    Quit o.%ToJSON()
}

/// The no-cost proof, before any agent runs: every board item resolves to live through the live runner, with the
/// mimic's configuration in the spec the operation builds; the provider the runner makes is the mimic's (openai at
/// the mimic's base_url, the run's token as its key) and an agent keeps it through %Init, so the class's own
/// configuration (AI.LLM.Shutter) is never read; that provider lists models, passes AI Hub's TestConfiguration and
/// answers a ping, all at the mimic, as the call log shows; and a response labelled mock is refused as a recording.
/// Calls nothing but the mimic. Returns {ok, ...} as JSON, with the ping's request body. The mockDebug option, switched
/// on for the ping's body, is put back as it was whatever happens, so a failed test leaves no request bodies piling up.
ClassMethod SelfTest() As %String [ SqlProc ]
{
    Set o = {}, problems = []
    Set debug = $GET(^Shutter.Config("aihub", "mockDebug")), touched = 0
    Try {
        Set mock = ##class(Shutter.Setup).MockConfig()
        If mock = "" Return {"ok": false, "problems": ["the mimic is off: run Enable first"]}.%ToJSON()
        Set o.switch = mock
        // 1. The production's board items: auto (or live) resolves to live, through the live runner.
        Set o.items = ..Items(problems)
        // 2. The provider the runner makes for a run, and an agent made the way the runner makes it.
        Set spec = ##class(Shutter.Bridge.RunSpec).%New()
        Set spec.AgentClass = "Shutter.Agent.Conformance", spec.MemberCode = "selftest", spec.EnsMessageId = "selftest", spec.MockConfig = mock
        Set provider = ##class(Shutter.Bridge.Runner.AIHub).MockProvider(mock, spec, "SubmitFindings", .model)
        Set o.provider = provider.Name, o.model = model
        If provider.Name '= "openai" Do problems.%Push("the runner's provider is " _ provider.Name _ ", not the mimic's openai")
        Set agent = ##class(Shutter.Agent.Conformance).%New()
        Set agent.CaseId = "C-000000", agent.Provider = provider
        Set sc = agent.%Init({"caseId": "C-000000", "role": "specialist", "member": "selftest"})
        If $$$ISERR(sc) Do problems.%Push("the agent did not start: " _ $SYSTEM.Status.GetErrorText(sc))
        Do o.%Set("agent_keeps_provider", (agent.Provider = provider) && (agent.Provider.%token = provider.%token), "boolean")
        If 'o."agent_keeps_provider" Do problems.%Push("%Init replaced the provider")
        // 3. The wire, with the ping's body kept.
        Set mark = +$GET(^Shutter.MockLog)
        Set ^Shutter.Config("aihub", "mockDebug") = 1, touched = 1
        Set ids = []
        Set models = provider.ListModels()
        Set iter = models.%GetIterator()
        While iter.%GetNext(.i, .m) { Do ids.%Push(##class(Shutter.Util.Json).Str(m, "id")) }
        Set o.models = ids
        // The Config Store's own test of the configuration (the descriptor's TestConfiguration: the model is listed).
        Set sc = ##class(%ConfigStore.Configuration).Use(mock, .props, 1)
        Set o."test_configuration" = $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
        If $$$ISERR(sc) Do problems.%Push("TestConfiguration: " _ o."test_configuration")
        Set r = provider.ChatComplete(model, [{"role": "user", "content": "ping"}])
        Set o.ping = r.Content, o."ping_usage" = r.Usage
        If r.Content '= "pong" Do problems.%Push("the ping was not answered pong")
        // 4. The call log: each call arrived at the mimic, with the run's token.
        // The model list is fetched once and then kept by AI Hub's library, so only the first test logs it.
        Set calls = [], pinged = 0
        For n = mark + 1:1:+$GET(^Shutter.MockLog) {
            Set line = ##class(%DynamicObject).%FromJSON(^Shutter.MockLog(n))
            Do calls.%Push(line)
            If (line.path = "/v1/chat/completions") && (line.source = "selftest") && (line.scheme = "bearer") Set pinged = 1
            If $DATA(^Shutter.MockLog(n, "body")) && (line.path = "/v1/chat/completions") Set o."ping_body" = ##class(%DynamicObject).%FromJSON(^Shutter.MockLog(n, "body"))
        }
        Set o.calls = calls
        If 'pinged Do problems.%Push("the mimic logged no ping with the run's token")
        // 5. A response labelled mock is never stored as a recording.
        Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
        Set response.Model = "mock", response.Status = "ok"
        Set sc = ##class(Shutter.Bridge.Record).Store(spec, response, "", "", .stored)
        Do o.%Set("record_store_refuses_mock", $$$ISERR(sc), "boolean")
        If $$$ISOK(sc) {
            Do problems.%Push("Shutter.Bridge.Record Store kept a response labelled mock")
            If $ISOBJECT($GET(stored)) Do ##class(Shutter.Bridge.Record).%DeleteId(stored.%Id())
        }
        // 6. The openai provider's settings as AI Hub lists them (base_url among them).
        Set iter = ##class(%AI.Provider).%GetProviders().%GetIterator()
        While iter.%GetNext(.i, .p) {
            Continue:(p.name '= "openai")
            Set names = []
            Set it2 = p.config.%GetIterator()
            While it2.%GetNext(.j, .c) { Do names.%Push(c.name) }
            Set o."openai_settings" = names
        }
    } Catch ex {
        Do problems.%Push(ex.DisplayString())
    }
    // The debug option as it was, on the straight path and after a throw alike.
    If touched {
        If debug = "" { Kill ^Shutter.Config("aihub", "mockDebug") } Else { Set ^Shutter.Config("aihub", "mockDebug") = debug }
    }
    Do o.%Set("ok", problems.%Size() = 0, "boolean")
    Set o.problems = problems
    Quit o.%ToJSON()
}

/// The production's board items with their Mode setting, and the mode and mimic configuration of the spec the operation
/// builds for a request now (RunSpec FromRequest, with the item's settings); an item that would not run live through
/// the live runner, or whose spec does not carry the mimic, is a problem.
ClassMethod Items(problems As %DynamicArray) As %DynamicArray
{
    Set out = []
    Set prod = ##class(Ens.Config.Production).%OpenId(##class(Shutter.Setup).ProductionName())
    If '$ISOBJECT(prod) Do problems.%Push("no production definition") Quit out
    For i = 1:1:prod.Items.Count() {
        Set item = prod.Items.GetAt(i)
        Continue:(item.ClassName '= "Shutter.Bridge.Operation.Agent")
        Set mode = "auto", runner = "Shutter.Bridge.Runner.AIHub"
        For k = 1:1:item.Settings.Count() {
            Set s = item.Settings.GetAt(k)
            If s.Name = "Mode" Set mode = s.Value
            If s.Name = "Runner" Set runner = s.Value
        }
        // The operation's settings that FromRequest reads; a business host cannot be made outside the production.
        Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(##class(Shutter.Bridge.Msg.AgentRequest).%New(), {"Mode": (mode), "Runner": (runner)})
        Set resolved = spec.Mode
        Do out.%Push({"item": (item.Name), "enabled": (item.Enabled), "mode": (mode), "resolves_to": (resolved), "runner": (runner), "mock_config": (spec.MockConfig)})
        If item.Enabled && ((resolved '= "live") || (runner '= "Shutter.Bridge.Runner.AIHub")) Do problems.%Push(item.Name _ " would run " _ resolved _ " through " _ runner)
        If item.Enabled && (spec.MockConfig '= ##class(Shutter.Setup).MockConfig()) Do problems.%Push(item.Name _ "'s spec does not carry the mimic's configuration")
    }
    Quit out
}

/// Every recording replayed offline, turn by turn, through Shutter.Mock.Turns with no HTTP and no licence: each turn
/// must be the recording's own (its tool calls, for another case id), and a copy of each with the receiver's version
/// raised by one must go to the catalogue instead. Returns a summary as JSON.
ClassMethod Offline() As %String [ SqlProc ]
{
    Set o = {"recordings": 0, "turns": 0, "reproduced": 0, "switched": 0, "problems": []}
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Bridge.Record ORDER BY ""Key""")
        While rs.%Next() {
            Set record = ##class(Shutter.Bridge.Record).%OpenId(rs.%Get("ID"))
            Continue:'$ISOBJECT(record)
            Set o.recordings = o.recordings + 1
            Do ..ReplayOne(record, o)
        }
    } Catch ex {
        Do o.problems.%Push(ex.DisplayString())
    }
    Do o.%Set("ok", (o.problems.%Size() = 0) && (o.turns = o.reproduced) && (o.switched = o.recordings), "boolean")
    Quit o.%ToJSON()
}

/// One recording through the mimic for the case C-999999, and its copy with the version raised.
ClassMethod ReplayOne(record As Shutter.Bridge.Record, o As %DynamicObject)
{
    Set turns = "Shutter.Mock.Turns"
    Set t = $CLASSMETHOD(turns, "Object", record.TranscriptJSON)
    Set messages = $SELECT($ISOBJECT(t): t.%Get("messages"), 1: "")
    If '$ISOBJECT(messages) Do o.problems.%Push(record.Key _ ": no transcript") Quit
    Set case = "C-999999", from = record.CorrelationKey
    Set terminal = $SELECT(record.MemberCode = "coordinator": "SubmitPlan", record.MemberCode = "generalist": "SubmitPlan", 1: "SubmitFindings")
    Set ctx = {"k": (record.Key), "c": (case), "m": (record.MemberCode), "t": (terminal), "r": "offline"}
    // The offered tools: those the recording called, and the terminal one.
    Set tools = [], seen = {}
    Set recorded = $CLASSMETHOD(turns, "Read", messages)
    Set iter = recorded.assistants.%GetIterator()
    While iter.%GetNext(.i, .m) {
        Set tc = m.%Get("tool_calls")
        Continue:'$ISOBJECT(tc)
        Set it2 = tc.%GetIterator()
        While it2.%GetNext(.j, .c) {
            Set name = $CLASSMETHOD(turns, "CallName", c)
            If 'seen.%IsDefined(name) Do seen.%Set(name, 1), tools.%Push({"type": "function", "function": {"name": (name), "parameters": {"type": "object"}}})
        }
    }
    If 'seen.%IsDefined(terminal) Do tools.%Push({"type": "function", "function": {"name": (terminal), "parameters": {"type": "object"}}})
    Set system = $CLASSMETHOD(turns, "Heading", record.MemberCode) _ $CHAR(10) _ $SELECT($ISOBJECT(t): ##class(Shutter.Util.Json).Str(t, "base_system_prompt"), 1: "")
    Set user = $REPLACE(recorded.users.%Get(0), from, case)
    Set want = $CLASSMETHOD(turns, "Turns", messages, seen, terminal, from, case)
    Set request = {"model": "mock", "tools": (tools)}
    Set request.messages = [{"role": "system", "content": (system)}, {"role": "user", "content": (user)}]
    // Turn by turn: the mimic's answer must be the recording's turn, whose recorded results are fed back.
    For n = 0:1:12 {
        Set out = $CLASSMETHOD(turns, "Answer", ctx, request, 1000, .log)
        If out.status '= 200 Do o.problems.%Push(record.Key _ " turn " _ n _ ": " _ out.body.%ToJSON()) Quit
        If $EXTRACT(log.source, 1, 7) '= "replay:" Do o.problems.%Push(record.Key _ " turn " _ n _ ": " _ log.source _ " " _ log.divergence) Quit
        Set msg = out.body.choices.%Get(0).message
        Set expected = want.%Get(n)
        Set o.turns = o.turns + 1
        If ..Same(msg, expected) {
            Set o.reproduced = o.reproduced + 1
        } Else {
            Do o.problems.%Push(record.Key _ " turn " _ n _ " differs: " _ $EXTRACT(msg.%ToJSON(), 1, 300))
        }
        Set tc = msg.%Get("tool_calls")
        Quit:'$ISOBJECT(tc)
        Do request.messages.%Push(msg)
        Set it3 = tc.%GetIterator()
        While it3.%GetNext(.j, .c) {
            Set rc = $SELECT($ISOBJECT(expected): expected.calls.%Get(j), 1: "")
            Set result = $SELECT($ISOBJECT(rc): $REPLACE(recorded.results.%Get(rc.recorded), from, case), 1: "{}")
            Do request.messages.%Push({"role": "tool", "tool_call_id": (c.id), "content": (result)})
        }
    }
    // The copy whose receiver has moved on by one version: the catalogue answers instead.
    Set context = $CLASSMETHOD(turns, "Context", user)
    Set ward = $CLASSMETHOD(turns, "Evidence", context).%Get("ward_state")
    If '$ISOBJECT(ward) Do o.problems.%Push(record.Key _ ": no ward_state to change") Quit
    Set ward.version = ward.version + 1
    Set nonce = $PIECE($PIECE($PIECE(user, "<evidence-", 2), " "), ">")
    Set head = $PIECE(user, "<evidence-", 1) _ "<evidence-" _ $PIECE($PIECE(user, "<evidence-", 2, *), ">", 1) _ ">"
    Set copy = {"model": "mock", "tools": (tools)}
    Set copy.messages = [{"role": "system", "content": (system)}, {"role": "user", "content": (head _ $CHAR(10) _ context.%ToJSON() _ $CHAR(10) _ "</evidence-" _ nonce _ ">")}]
    Set out = $CLASSMETHOD(turns, "Answer", ctx, copy, 1000, .log)
    If (out.status = 200) && ($EXTRACT(log.source, 1, 9) = "fallback:") && (log.divergence [ "ward_version") {
        Set o.switched = o.switched + 1
    } Else {
        Do o.problems.%Push(record.Key _ " copy: " _ log.source _ " " _ log.divergence)
    }
}

/// Whether the mimic's message is the recording's turn: the same text and the same tool calls with the same arguments.
ClassMethod Same(msg As %DynamicObject, expected As %DynamicObject) As %Boolean
{
    If '$ISOBJECT(expected) Quit 0
    Set content = $SELECT(msg.%GetTypeOf("content") = "string": msg.content, 1: "")
    If content '= ##class(Shutter.Mock.Turns).Mark(expected.content) Quit 0
    Set tc = msg.%Get("tool_calls")
    Set count = $SELECT($ISOBJECT(tc): tc.%Size(), 1: 0)
    If count '= expected.calls.%Size() Quit 0
    For j = 0:1:count - 1 {
        Set c = tc.%Get(j), e = expected.calls.%Get(j)
        If (c.function.name '= e.name) || (c.function.arguments '= e.arguments) Return 0
    }
    Quit 1
}

/// Set one of the mimic's options: mockReplay (0 answers every run from the catalogue), mockStrict (1 ends a replayed
/// run at a failed tool) or mockDebug (1 keeps each request's body in the call log). "" removes it. Returns Status().
ClassMethod Option(name As %String, value As %String = "") As %String [ SqlProc ]
{
    If '$LISTFIND($LISTBUILD("mockReplay", "mockStrict", "mockDebug"), name) Quit {"error": ("no option " _ name)}.%ToJSON()
    If value = "" {
        Kill ^Shutter.Config("aihub", name)
    } Else {
        Set ^Shutter.Config("aihub", name) = value
    }
    Quit ..Status()
}

/// The call log from line <var>from</var> on, as a JSON array; with <var>bodies</var>, the bodies kept in debug mode.
ClassMethod Log(from As %Integer = 1, bodies As %Boolean = 0) As %String [ SqlProc ]
{
    Set out = []
    For n = from:1:+$GET(^Shutter.MockLog) {
        Continue:'$DATA(^Shutter.MockLog(n))
        Set line = ##class(%DynamicObject).%FromJSON(^Shutter.MockLog(n))
        Set line.n = n
        If bodies && $DATA(^Shutter.MockLog(n, "body")) Set line.body = ^Shutter.MockLog(n, "body")
        Do out.%Push(line)
    }
    Quit out.%ToJSON()
}

/// Who holds the instance's licence units (the user or address of each, and its connections), with the counters, so
/// a unit the mimic's calls hold can be told from the scenario runner's sign-ins.
ClassMethod Licences() As %String [ SqlProc ]
{
    Set o = {}, users = []
    Try {
        Set o.counters = ##class(%DynamicObject).%FromJSON(##class(Shutter.Setup).LicenseInfo())
        Set rs = ##class(%ResultSet).%New("%SYSTEM.License:UserList")
        Set sc = rs.Execute()
        If $$$ISERR(sc) Set o.error = $SYSTEM.Status.GetErrorText(sc)
        While rs.Next() {
            Set u = {}
            For i = 1:1:rs.GetColumnCount() { Do u.%Set(rs.GetColumnName(i), rs.GetData(i)) }
            Do users.%Push(u)
        }
    } Catch ex {
        Set o.error = ex.DisplayString()
    }
    Set o.users = users
    Quit o.%ToJSON()
}

/// The role and the web application, in %SYS: created when missing, brought to this definition when they exist.
ClassMethod Web(ns As %String, resources As %String) As %Status
{
    Set sc = $$$OK
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        If ##class(Security.Roles).Exists(..#ROLE) {
            Set props("Description") = "Shutter API mimic: the namespace's databases for /shutter-mock (tests/mock)", props("Resources") = resources
            Set sc = ##class(Security.Roles).Modify(..#ROLE, .props)
        } Else {
            Set sc = ##class(Security.Roles).Create(..#ROLE, "Shutter API mimic: the namespace's databases for /shutter-mock (tests/mock)", resources, "")
        }
        Quit:$$$ISERR(sc)
        Kill props
        Set props("NameSpace") = ns
        Set props("Description") = "Shutter API mimic (tests/mock): answers the live runner without a model, loopback callers only"
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 64
        Set props("DispatchClass") = "Shutter.Mock.API"
        Set props("MatchRoles") = ":" _ ..#ROLE
        Set props("UseCookies") = 2
        Set props("CookiePath") = ..#WEBAPP _ "/"
        If ##class(Security.Applications).Exists(..#WEBAPP) {
            Set sc = ##class(Security.Applications).Modify(..#WEBAPP, .props)
        } Else {
            Set sc = ##class(Security.Applications).Create(..#WEBAPP, .props)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

}
