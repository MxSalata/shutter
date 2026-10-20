/// The API mimic's answers, JSON in and JSON out with no HTTP (Shutter.Mock.API serves them): one model turn of a
/// board member's run. The member's recording is replayed turn by turn when the case's material facts are the
/// recorded case's; otherwise the answer is a deterministic one, from the catalogue match the evidence already
/// carries. Stateless: every request is judged again from its own messages. Every text it writes starts with [mock].
/// A test fixture: in tests/mock, outside both IPM modules and the image.
Class Shutter.Mock.Turns
{

Parameter PREFIX = "[mock] ";

/// Fields that change from run to run and decide nothing: left out when a tool result is compared with the
/// recording's.
Parameter VOLATILE = ",observed_at,fresh_until,applied_at,epoch,seq,session_id,ens_session_id,ens_header_id,source_header_id,sent_at,finding_id,id,score,at,";

/// The run's context from the API key the live runner sent (smk1. and base64url JSON: k the replay key, c the case,
/// m the member, t the terminal tool, r the production message), or "" when the key is not one.
ClassMethod Decode(token As %String) As %DynamicObject
{
    If $EXTRACT(token, 1, 5) '= "smk1." Quit ""
    Try {
        Set b = $TRANSLATE($EXTRACT(token, 6, *), "-_", "+/")
        Set b = b _ $EXTRACT("===", 1, (4 - ($LENGTH(b) # 4)) # 4)
        Set ctx = ##class(%DynamicAbstractObject).%FromJSON($ZCONVERT($SYSTEM.Encryption.Base64Decode(b), "I", "UTF8"))
        If '$ISOBJECT(ctx) || 'ctx.%IsA("%DynamicObject") Return ""
        Return ctx
    } Catch ex {
        Return ""
    }
}

/// One answer: {"status": 200, "body": a chat.completion} or {"status": 400, "body": {"error": ...}}. <var>log</var>
/// gets what the call log records: the run, the member, the turn, the source (replay:<key> or fallback:<entry>), and
/// any divergence, drift or failed tool.
ClassMethod Answer(ctx As %DynamicObject, request As %DynamicObject, size As %Integer, Output log As %DynamicObject) As %DynamicObject
{
    Set log = {}
    If '$ISOBJECT(ctx) Quit ..Refuse("The API key is not a run token of the live runner", "invalid_api_key")
    Set log.run = ctx.r, log.member = ctx.m
    Set messages = request.%Get("messages")
    If '$ISOBJECT(messages) || (messages.%Size() = 0) Quit ..Refuse("The request has no messages", "invalid_request")
    Set conv = ..Read(messages)
    Set n = conv.assistants.%Size()
    Set offered = ..Offered(request)
    Set log.turn = n, log.tools = ..Names(offered)
    // The self test's call: no case and no tools.
    If ctx.m = "selftest" Set log.source = "selftest" Quit ..Reply(request, size, n, "pong")
    Set first = conv.users.%Get(0)
    Set case = ..TagCase(first)
    If (case = "") || (case '= ctx.c) Quit ..Refuse("The evidence names case " _ case _ " and the run is for " _ ctx.c, "context_mismatch")
    Set heading = ..Heading(ctx.m)
    If (heading = "") || (conv.system '[ heading) Quit ..Refuse("The instructions are not the " _ ctx.m _ " member's", "context_mismatch")
    If ..Offer(offered, ctx.t) = "" Quit ..Refuse("The terminal tool " _ ctx.t _ " is not offered", "context_mismatch")
    Set context = ..Context(first)
    Set term = ..Terminal(conv, ctx.t)
    Set rec = ..Recording(ctx, context, offered, .why)
    Set log.source = $SELECT($ISOBJECT(rec): "replay:" _ ctx.k, 1: "fallback:" _ ..Choose(context).id)
    If why '= "" Set log.divergence = why
    // Refusals of the terminal tool beyond the recording's own: the first is answered with the catalogue's call, the
    // next ends the run with the problems, so the case shows them.
    Set extra = term.refusals - $SELECT($ISOBJECT(rec): rec.refusals, 1: 0)
    If term.accepted {
        Set text = ""
        If $ISOBJECT(rec) && (extra <= 0) Set text = ..FinalOf(rec.turns)
        If text = "" Set text = ..Done(ctx, context)
        Quit ..Reply(request, size, n, ..Mark(text))
    }
    If extra > 0 {
        If $ISOBJECT(rec) && (extra = 1) {
            Set log.divergence = "the recorded " _ ctx.t _ " was refused: the catalogue's call instead"
            Quit ..Reply(request, size, n, "", ..TerminalCall(ctx, context))
        }
        Set log.divergence = ctx.t _ " refused " _ term.refusals _ " times"
        Quit ..Reply(request, size, n, ..#PREFIX _ ctx.t _ " refused: " _ $EXTRACT(term.problems, 1, 1500))
    }
    If $ISOBJECT(rec) {
        Set drift = ..Drift(conv, n, rec, ctx.t, .failed)
        If drift Set log.drift = drift
        If failed '= "" {
            Set log.failed = failed
            If $GET(^Shutter.Config("aihub", "mockStrict")) Quit ..Reply(request, size, n, ..#PREFIX _ "diverged at turn " _ n _ ": " _ failed _ " failed")
        }
        If (conv.users.%Size() > 1) || (n >= rec.turns.%Size()) {
            Set log.divergence = $SELECT(conv.users.%Size() > 1: "the loop asked again", 1: "past the recording's end") _ ": the catalogue's " _ ctx.t
            Quit ..Reply(request, size, n, "", ..TerminalCall(ctx, context))
        }
        Set turn = rec.turns.%Get(n)
        If turn.calls.%Size() = 0 {
            Set log.divergence = "the recording closes before an accepted " _ ctx.t _ ": the catalogue's call"
            Quit ..Reply(request, size, n, "", ..TerminalCall(ctx, context))
        }
        Quit ..Reply(request, size, n, ..Mark(turn.content), turn.calls)
    }
    // From the catalogue: the member's reads first, then the terminal call.
    If (n = 0) && (conv.users.%Size() = 1) {
        Set calls = ..Reads(ctx, context, offered)
        If calls.%Size() > 0 Quit ..Reply(request, size, n, "", calls)
    }
    Quit ..Reply(request, size, n, "", ..TerminalCall(ctx, context))
}

/// The member's recording as turns to replay, when replay is on and the material facts of the recorded case are
/// this case's (Facts); else "" and <var>why</var> says why not.
ClassMethod Recording(ctx As %DynamicObject, context As %DynamicObject, offered As %DynamicObject, Output why As %String) As %DynamicObject
{
    Set why = ""
    If $GET(^Shutter.Config("aihub", "mockReplay"), 1) = 0 Set why = "replay is off" Quit ""
    If ctx.k = "" Set why = "no replay key" Quit ""
    Set record = ##class(Shutter.Bridge.Record).Find(ctx.k)
    If '$ISOBJECT(record) Set why = "no recording for " _ ctx.k Quit ""
    Set t = ..Object(record.TranscriptJSON)
    Set messages = $SELECT($ISOBJECT(t): t.%Get("messages"), 1: "")
    If '$ISOBJECT(messages) Set why = "the recording has no transcript" Quit ""
    Set recorded = ..Read(messages)
    Set diff = ..Differ(..Facts(..Context(recorded.users.%Get(0))), ..Facts(context))
    If diff '= "" Set why = "the facts differ from the recording's: " _ diff Quit ""
    Set from = record.CorrelationKey, to = ctx.c
    Set rec = {"turns": (..Turns(messages, offered, ctx.t, from, to)), "results": (recorded.results), "from": (from), "to": (to)}
    Set rec.refusals = ..Terminal(recorded, ctx.t).refusals
    Quit rec
}

/// A recording's assistant turns as the mimic sends them: the calls to tools this run offers (a knowledge collection
/// not built drops its search), the recorded case id replaced by this one, the terminal call's summary marked, and a
/// turn left with nothing in it skipped.
ClassMethod Turns(messages As %DynamicArray, offered As %DynamicObject, terminal As %String, from As %String, to As %String) As %DynamicArray
{
    Set out = []
    Set iter = messages.%GetIterator()
    While iter.%GetNext(.i, .m) {
        Continue:'$ISOBJECT(m)
        Continue:(##class(Shutter.Util.Json).Str(m, "role") '= "assistant")
        Set content = ..Swap(..Text(m.%Get("content")), from, to)
        Set calls = []
        Set tc = m.%Get("tool_calls")
        If $ISOBJECT(tc) {
            Set it2 = tc.%GetIterator()
            While it2.%GetNext(.j, .c) {
                Set name = ..Offer(offered, ..CallName(c))
                Continue:(name = "")
                Set args = ..Swap(..CallArgs(c), from, to)
                If ..Bare(name) = terminal Set args = ..MarkResult(args)
                Do calls.%Push({"name": (name), "arguments": (args), "recorded": (##class(Shutter.Util.Json).Str(c, "id"))})
            }
        }
        Continue:((calls.%Size() = 0) && ($ZSTRIP(content, "<>W") = ""))
        Do out.%Push({"content": (content), "calls": (calls)})
    }
    Quit out
}

/// The material facts of a case's evidence: the scenario and the event, the catalogue's entry, outcome, matches
/// and conditions, the receiver's version and state, whether there is a receipt, conditional writes and, for the
/// coordinator, each specialist's disposition. Case ids, nonces, times, epochs and other volatile fields are not
/// among them.
ClassMethod Facts(context As %DynamicObject) As %DynamicObject
{
    Set j = "Shutter.Util.Json"
    Set f = {}
    Set ev = ..Evidence(context)
    Set f.scenario = $CLASSMETHOD(j, "Str", ev, "scenario")
    Set f.event = $CLASSMETHOD(j, "Str", ev.%Get("operation"), "event")
    Set cat = ev.%Get("catalogue")
    Set f.entry = $CLASSMETHOD(j, "Str", cat, "entry"), f.outcome = $CLASSMETHOD(j, "Str", cat, "outcome")
    Set ids = "", matches = $SELECT($ISOBJECT(cat): cat.%Get("matches"), 1: "")
    If $ISOBJECT(matches) {
        Set iter = matches.%GetIterator()
        While iter.%GetNext(.i, .m) { Set ids = ids _ "," _ $CLASSMETHOD(j, "Str", m, "id") }
    }
    Set f.matches = $EXTRACT(ids, 2, *)
    Set cond = $SELECT($ISOBJECT(cat): cat.%Get("conditions"), 1: "")
    If $ISOBJECT(cond) {
        Set iter = cond.%GetIterator()
        While iter.%GetNext(.k, .v) { Do f.%Set("condition " _ k, $SELECT($ISOBJECT(v): v.%ToJSON(), 1: v)) }
    }
    Set ward = ev.%Get("ward_state")
    Set f."ward_version" = $CLASSMETHOD(j, "Str", ward, "version"), f."ward_state" = $CLASSMETHOD(j, "Str", ward, "state")
    Set receipt = ev.%Get("receipt")
    Set f.receipt = $SELECT('$ISOBJECT(receipt): "none", receipt.%IsDefined("error"): "absent", 1: "present")
    Set f."conditional_writes" = $CLASSMETHOD(j, "Str", ev.%Get("route"), "conditional_writes")
    Set findings = $SELECT($ISOBJECT(context): context.%Get("findings"), 1: "")
    If $ISOBJECT(findings) {
        Set iter = findings.%GetIterator()
        While iter.%GetNext(.i, .x) { Set said($CLASSMETHOD(j, "Str", x, "member_code")) = $CLASSMETHOD(j, "Str", x, "disposition") }
        Set list = "", k = ""
        For {
            Set k = $ORDER(said(k))
            Quit:(k = "")
            Set list = list _ $SELECT(list = "": "", 1: ",") _ k _ ":" _ said(k)
        }
        Set f.findings = list
    }
    Quit f
}

/// How the recorded facts differ from this case's, or "". A condition only one side has (one added since the
/// recording) is left out.
ClassMethod Differ(recorded As %DynamicObject, current As %DynamicObject) As %String
{
    Set out = ""
    Set iter = recorded.%GetIterator()
    While iter.%GetNext(.k, .v) {
        Continue:'current.%IsDefined(k)
        Set w = current.%Get(k)
        If v '= w Set out = out _ $SELECT(out = "": "", 1: "; ") _ k _ " " _ v _ " now " _ w
    }
    Quit out
}

/// Whether the terminal tool was accepted, how many times it was refused, and the last refusal's problems.
ClassMethod Terminal(conv As %DynamicObject, terminal As %String) As %DynamicObject
{
    Set out = {"accepted": 0, "refusals": 0, "problems": ""}
    Set iter = conv.assistants.%GetIterator()
    While iter.%GetNext(.i, .m) {
        Set tc = m.%Get("tool_calls")
        Continue:'$ISOBJECT(tc)
        Set it2 = tc.%GetIterator()
        While it2.%GetNext(.j, .c) {
            Continue:(..Bare(..CallName(c)) '= terminal)
            Set id = ##class(Shutter.Util.Json).Str(c, "id")
            Continue:'conv.results.%IsDefined(id)
            Set text = conv.results.%Get(id), o = ..Object(text)
            If ##class(Shutter.Util.Json).Bool(o, "accepted") {
                Set out.accepted = 1
            } Else {
                Set out.refusals = out.refusals + 1
                Set out.problems = $SELECT('$ISOBJECT(o): text, $ISOBJECT(o.%Get("problems")): o.problems.%ToJSON(), 1: ##class(Shutter.Util.Json).Str(o, "error", text))
            }
        }
    }
    Quit out
}

/// The previous turn's tool results against the recording's: how many differ beyond the volatile fields, and in
/// <var>failed</var> the tools (other than the terminal one) that failed or were refused.
ClassMethod Drift(conv As %DynamicObject, n As %Integer, rec As %DynamicObject, terminal As %String, Output failed As %String) As %Integer
{
    Set failed = "", drift = 0
    If n = 0 Quit 0
    Set prev = conv.assistants.%Get(n - 1)
    Set tc = $SELECT($ISOBJECT(prev): prev.%Get("tool_calls"), 1: "")
    If '$ISOBJECT(tc) Quit 0
    Set turn = rec.turns.%Get(n - 1)
    Set iter = tc.%GetIterator()
    While iter.%GetNext(.j, .c) {
        Set name = ..Bare(..CallName(c))
        Continue:(name = terminal)
        Set got = conv.results.%Get(##class(Shutter.Util.Json).Str(c, "id"))
        If ..Failed(got) Set failed = failed _ $SELECT(failed = "": "", 1: ", ") _ name
        Continue:'$ISOBJECT(turn)
        Set rc = turn.calls.%Get(j)
        Continue:'$ISOBJECT(rc)
        Set want = ..Swap(rec.results.%Get(rc.recorded), rec.from, rec.to)
        If ..Stable(got) '= ..Stable(want) Set drift = drift + 1
    }
    Quit drift
}

/// The catalogue entry the deterministic answer follows: the single match; with several or none, the match (or
/// else the catalogue entry) whose scenarios name the case's scenario; otherwise none. With its title, preferred
/// outcome and why, and the confidence the findings state (0.9, 0.6 or 0.3).
ClassMethod Choose(context As %DynamicObject) As %DynamicObject
{
    Set j = "Shutter.Util.Json"
    Set out = {"id": "", "title": "", "outcome": "", "why": "", "confidence": 0.3}
    Set ev = ..Evidence(context)
    Set cat = ev.%Get("catalogue")
    Set matches = $SELECT($ISOBJECT(cat): cat.%Get("matches"), 1: "")
    Set m = ""
    If $ISOBJECT(matches) && (matches.%Size() = 1) {
        Set m = matches.%Get(0), out.confidence = 0.9
    } Else {
        Set scenario = $CLASSMETHOD(j, "Str", ev, "scenario")
        If scenario '= "" {
            If $ISOBJECT(matches) {
                Set iter = matches.%GetIterator()
                While iter.%GetNext(.i, .x) {
                    Set e = ##class(Shutter.Catalogue.Entry).ById($CLASSMETHOD(j, "Str", x, "id"))
                    If $ISOBJECT(e) && ..Covers(e.ToObject(), scenario) Set m = x Quit
                }
            }
            If '$ISOBJECT(m) {
                Set iter = ##class(Shutter.Catalogue.Entry).All().%GetIterator()
                While iter.%GetNext(.i, .x) {
                    If ..Covers(x, scenario) Set m = x Quit
                }
            }
            If $ISOBJECT(m) Set out.confidence = 0.6
        }
    }
    If $ISOBJECT(m) {
        Set out.id = $CLASSMETHOD(j, "Str", m, "id"), out.title = $CLASSMETHOD(j, "Str", m, "title")
        Set pref = m.%Get("preferred")
        Set out.outcome = $CLASSMETHOD(j, "Str", pref, "outcome"), out.why = $CLASSMETHOD(j, "Str", pref, "why")
    }
    Quit out
}

/// Whether a catalogue entry (as Shutter.Catalogue.Entry ToObject gives it) names the scenario.
ClassMethod Covers(entry As %DynamicObject, scenario As %String) As %Boolean
{
    Set list = entry.%Get("scenarios")
    If '$ISOBJECT(list) Quit 0
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .s) { If s = scenario Return 1 }
    Quit 0
}

/// The disposition an entry's preferred outcome means, as the case workflow's policy path maps it.
ClassMethod Disposition(entry As %DynamicObject) As %String
{
    If entry.id = "" Quit "more_evidence"
    Quit $CASE(entry.outcome, "resend": "resend", "resend_chain": "resend", "resend_latest": "resend", "reconcile": "reconcile", "none": "superseded", : "escalate")
}

/// The member's first turn from the catalogue: its read tools that are offered, each for this case, and one search
/// of its knowledge collection for the entry's title.
ClassMethod Reads(ctx As %DynamicObject, context As %DynamicObject, offered As %DynamicObject) As %DynamicArray
{
    Set list = $CASE(ctx.m, "conformance": "GetMessage,GetValidation,GetFailure,search_contracts", "encounter": "GetWardState,GetReceipt,GetTimeline,search_lifecycle", "impact": "GetRoute,GetWardState,GetReceipt,GetFailure,search_effects", "coordinator": "search_playbooks", "generalist": "GetMessage,GetValidation,GetFailure,GetWardState,GetReceipt,GetTimeline,GetRoute,search_playbooks", : "")
    Set e = ..Choose(context)
    Set query = $SELECT(e.title '= "": e.title, 1: "failed " _ ##class(Shutter.Util.Json).Str(..Evidence(context).%Get("operation"), "event") _ " delivery")
    Set calls = []
    For i = 1:1:$LENGTH(list, ",") {
        Set want = $PIECE(list, ",", i)
        Set name = ..Offer(offered, want)
        Continue:(name = "")
        If $EXTRACT(want, 1, 7) = "search_" {
            Set args = {"query": (query)}
            If ..Takes(offered.%Get(name), "top_k") Set args."top_k" = 3
        } Else {
            Set args = {"caseId": (ctx.c)}
        }
        Do calls.%Push({"name": (name), "arguments": (args.%ToJSON())})
    }
    Quit calls
}

/// The terminal call from the catalogue: SubmitFindings with the entry's disposition, or SubmitPlan with the one
/// action the policy path would take for it, the specialists who said otherwise kept as disagreements.
ClassMethod TerminalCall(ctx As %DynamicObject, context As %DynamicObject) As %DynamicArray
{
    Set j = "Shutter.Util.Json"
    Set ev = ..Evidence(context)
    Set e = ..Choose(context), d = ..Disposition(e)
    Set label = $SELECT(e.id = "": "no catalogue entry", 1: "catalogue " _ e.id _ " (" _ e.title _ ")")
    Set refs = ..Refs(ev)
    If ctx.t = "SubmitPlan" {
        Set plan = {"disposition": (d)}
        Set plan.summary = ..#PREFIX _ "One plan from " _ label _ ": " _ d _ $SELECT(e.outcome '= "": ", its preferred outcome " _ e.outcome, 1: "") _ ". Deterministic, from the evidence's catalogue match; no model planned this case."
        Set op = $CLASSMETHOD(j, "Str", ev.%Get("operation"), "operation_key")
        Set version = +$CLASSMETHOD(j, "Str", ev.%Get("ward_state"), "version", 0)
        Set plan.preconditions = []
        If d = "resend" {
            Set plan.action = {"type": "resend", "operation_key": (op), "expected_version": (version)}
            Set plan.preconditions = [("The receiver's version is still " _ version _ " at dispatch"), "No later event for the encounter before dispatch"]
        } ElseIf d = "reconcile" {
            Set plan.action = {"type": "reconcile", "operation_key": (op)}
        } Else {
            Set plan.action = {"type": "none"}
        }
        If e.id '= "" Do refs.%Push("catalogue")
        Set plan."evidence_refs" = refs
        Set plan.disagreements = $SELECT(ctx.m = "coordinator": ..Disagreements(context, d, e.id), 1: [])
        Set plan."catalogue_entry" = e.id, plan.outcome = $SELECT(e.id = "": "", 1: "preferred")
        Set plan.why = ..#PREFIX _ $SELECT(e.why '= "": e.why, 1: "No catalogue entry fits this case's evidence.")
        Set args = {"caseId": (ctx.c), "plan": (plan)}
    } Else {
        Set f = {"disposition": (d), "confidence": (e.confidence)}
        Set f.summary = ..#PREFIX _ "Seen as the " _ ctx.m _ " member: " _ d _ ", from " _ label _ $SELECT(e.outcome '= "": ", whose preferred outcome is " _ e.outcome, 1: "") _ ". Deterministic, from the evidence's catalogue match."
        Set f.violations = [], f.unknowns = [(..#PREFIX _ "No model reviewed this case; this is the catalogue's preferred outcome.")]
        Set f."evidence_refs" = refs
        Set args = {"caseId": (ctx.c), "findings": (f)}
    }
    Quit [{"name": (ctx.t), "arguments": (args.%ToJSON())}]
}

/// For the coordinator: each specialist whose disposition differs from the plan's, kept.
ClassMethod Disagreements(context As %DynamicObject, disposition As %String, entry As %String) As %DynamicArray
{
    Set j = "Shutter.Util.Json"
    Set out = []
    Set findings = context.%Get("findings")
    If '$ISOBJECT(findings) Quit out
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .x) {
        Set said = $CLASSMETHOD(j, "Str", x, "disposition")
        Continue:(said = disposition)
        Do out.%Push({"member": ($CLASSMETHOD(j, "Str", x, "member_code")), "said": (said), "why_kept": (..#PREFIX _ "the plan follows " _ $SELECT(entry '= "": "catalogue " _ entry _ "'s preferred outcome", 1: "no catalogue entry"))})
    }
    Quit out
}

/// The evidence kinds present in the snapshot, as evidence_refs name them.
ClassMethod Refs(ev As %DynamicObject) As %DynamicArray
{
    Set refs = []
    For kind = "operation", "failure:error", "message", "validation", "ward_state", "receipt", "timeline", "route" {
        Set key = $PIECE(kind, ":"), label = $PIECE(kind, ":", *)
        Set type = ev.%GetTypeOf(key)
        If (type '= "unassigned") && (type '= "null") Do refs.%Push(label)
    }
    Quit refs
}

/// The closing text from the catalogue, once the terminal tool has accepted.
ClassMethod Done(ctx As %DynamicObject, context As %DynamicObject) As %String
{
    Set e = ..Choose(context)
    Quit ..#PREFIX _ "Submitted " _ ..Disposition(e) _ " for " _ ctx.c _ " from " _ $SELECT(e.id = "": "no catalogue entry", 1: "catalogue " _ e.id) _ " (deterministic, no model)."
}

/// The recording's closing text: its last turn, when that turn calls no tool.
ClassMethod FinalOf(turns As %DynamicArray) As %String
{
    If turns.%Size() = 0 Quit ""
    Set last = turns.%Get(turns.%Size() - 1)
    Quit $SELECT(last.calls.%Size() = 0: last.content, 1: "")
}

/// A chat.completion answering with <var>content</var> and, when given, tool calls ({name, arguments} each) whose
/// ids the mimic mints (call_<turn>_<n>). The usage is an estimate: four characters a token.
ClassMethod Reply(request As %DynamicObject, size As %Integer, n As %Integer, content As %String, calls As %DynamicArray = "") As %DynamicObject
{
    Set msg = {"role": "assistant"}
    If content '= "" {
        Set msg.content = content
    } Else {
        Do msg.%Set("content", "", "null")
    }
    Set finish = "stop"
    If $ISOBJECT(calls) && (calls.%Size() > 0) {
        Set out = []
        Set iter = calls.%GetIterator()
        While iter.%GetNext(.j, .c) { Do out.%Push({"id": ("call_" _ n _ "_" _ j), "type": "function", "function": {"name": (c.name), "arguments": (c.arguments)}}) }
        Set msg."tool_calls" = out, finish = "tool_calls"
    }
    Set body = {"id": ("chatcmpl-mock-" _ $ZHEX($RANDOM(1048576)) _ $ZHEX($RANDOM(1048576))), "object": "chat.completion", "created": (+$ZDATETIME($HOROLOG, -2)), "model": (##class(Shutter.Util.Json).Str(request, "model", "mock"))}
    Set choice = {"index": 0, "message": (msg), "finish_reason": (finish)}
    Set body.choices = [(choice)]
    Set prompt = (size \ 4) + 1, completion = ($LENGTH(msg.%ToJSON()) \ 4) + 1
    Set body.usage = {"prompt_tokens": (prompt), "completion_tokens": (completion), "total_tokens": (prompt + completion), "prompt_tokens_details": {"cached_tokens": 0}}
    Quit {"status": 200, "body": (body)}
}

/// An error answer in OpenAI's shape. The live runner reports it as model_error: the message never says denied,
/// timeout or loop, which it reads as statuses of their own.
ClassMethod Refuse(message As %String, code As %String) As %DynamicObject
{
    Quit {"status": 400, "body": {"error": {"message": (..#PREFIX _ message), "type": "invalid_request_error", "code": (code)}}}
}

/// A request's conversation: the system prompt, the user messages' texts, the assistant messages, and the tool
/// results by call id.
ClassMethod Read(messages As %DynamicArray) As %DynamicObject
{
    Set conv = {"system": "", "users": [], "assistants": [], "results": {}}
    Set iter = messages.%GetIterator()
    While iter.%GetNext(.i, .m) {
        Continue:'$ISOBJECT(m)
        Set role = ##class(Shutter.Util.Json).Str(m, "role")
        If (role = "system") || (role = "developer") {
            Set conv.system = conv.system _ ..Text(m.%Get("content"))
        } ElseIf role = "user" {
            Do conv.users.%Push(..Text(m.%Get("content")))
        } ElseIf role = "assistant" {
            Do conv.assistants.%Push(m)
        } ElseIf role = "tool" {
            Do conv.results.%Set(##class(Shutter.Util.Json).Str(m, "tool_call_id"), ..Text(m.%Get("content")))
        }
    }
    Quit conv
}

/// The tools a request offers, by name, with their definitions.
ClassMethod Offered(request As %DynamicObject) As %DynamicObject
{
    Set out = {}
    Set tools = request.%Get("tools")
    If '$ISOBJECT(tools) Quit out
    Set iter = tools.%GetIterator()
    While iter.%GetNext(.i, .t) {
        Continue:'$ISOBJECT(t)
        Set fn = t.%Get("function")
        Set name = ##class(Shutter.Util.Json).Str($SELECT($ISOBJECT(fn): fn, 1: t), "name")
        If name '= "" Do out.%Set(name, t)
    }
    Quit out
}

ClassMethod Names(offered As %DynamicObject) As %String
{
    Set out = ""
    Set iter = offered.%GetIterator()
    While iter.%GetNext(.k, .v) { Set out = out _ $SELECT(out = "": "", 1: ",") _ k }
    Quit out
}

/// The offered tool a name stands for: the name itself, or an offered name that ends with it after a prefix; "" when
/// the run does not offer it.
ClassMethod Offer(offered As %DynamicObject, name As %String) As %String
{
    If name = "" Quit ""
    If offered.%IsDefined(name) Quit name
    Set iter = offered.%GetIterator()
    While iter.%GetNext(.k, .v) { If ..Bare(k) = name Return k }
    Quit ""
}

/// Whether a tool definition has a parameter of that name.
ClassMethod Takes(tool As %DynamicObject, param As %String) As %Boolean
{
    If '$ISOBJECT(tool) Quit 0
    Set fn = tool.%Get("function")
    Set params = $SELECT($ISOBJECT(fn): fn.%Get("parameters"), 1: tool.%Get("parameters"))
    Set props = $SELECT($ISOBJECT(params): params.%Get("properties"), 1: "")
    Quit $ISOBJECT(props) && props.%IsDefined(param)
}

ClassMethod Bare(name As %String) As %String
{
    Quit $PIECE($PIECE(name, ":", *), "__", *)
}

/// A tool call's name, in the wire shape ({function: {name}}) or the recorded one ({name}).
ClassMethod CallName(call As %DynamicObject) As %String
{
    Set fn = call.%Get("function")
    Quit ##class(Shutter.Util.Json).Str($SELECT($ISOBJECT(fn): fn, 1: call), "name")
}

/// A tool call's arguments as JSON text, in either shape.
ClassMethod CallArgs(call As %DynamicObject) As %String
{
    Set fn = call.%Get("function")
    Set args = $SELECT($ISOBJECT(fn): fn.%Get("arguments"), 1: call.%Get("arguments"))
    Quit $SELECT($ISOBJECT(args): args.%ToJSON(), 1: args)
}

/// The terminal call's arguments with the summary of the findings or the plan marked.
ClassMethod MarkResult(args As %String) As %String
{
    Set o = ..Object(args)
    If '$ISOBJECT(o) || 'o.%IsA("%DynamicObject") Quit args
    For key = "findings", "plan" {
        Set r = o.%Get(key)
        If $ISOBJECT(r) && (r.%GetTypeOf("summary") = "string") Set r.summary = ..Mark(r.summary)
    }
    Quit o.%ToJSON()
}

ClassMethod Mark(text As %String) As %String
{
    If (text = "") || ($EXTRACT(text, 1, $LENGTH(..#PREFIX)) = ..#PREFIX) Quit text
    Quit ..#PREFIX _ text
}

ClassMethod Swap(text As %String, from As %String, to As %String) As %String
{
    If (from = "") || (from = to) Quit text
    Quit $REPLACE(text, from, to)
}

/// A message's text: a string, or the text parts of a content array.
ClassMethod Text(content) As %String
{
    If '$ISOBJECT(content) Quit $GET(content)
    If content.%IsA("%DynamicArray") {
        Set out = ""
        Set iter = content.%GetIterator()
        While iter.%GetNext(.i, .p) { Set out = out _ $SELECT($ISOBJECT(p): ##class(Shutter.Util.Json).Str(p, "text"), 1: p) }
        Quit out
    }
    Quit content.%ToJSON()
}

/// The case the evidence tag names (case="C-...").
ClassMethod TagCase(text As %String) As %String
{
    Quit $PIECE($PIECE($PIECE($PIECE(text, "<evidence-", 2), ">"), "case=""", 2), """")
}

/// The JSON inside the evidence tag of the first user message: {case_id, evidence, findings?}, or {}.
ClassMethod Context(text As %String) As %DynamicObject
{
    Set rest = $PIECE(text, "<evidence-", 2, *)
    If rest = "" Quit {}
    Set nonce = $PIECE($PIECE(rest, " "), ">")
    Set o = ..Object($PIECE($PIECE(rest, ">", 2, *), "</evidence-" _ nonce _ ">", 1))
    Quit $SELECT($ISOBJECT(o) && o.%IsA("%DynamicObject"): o, 1: {})
}

ClassMethod Evidence(context As %DynamicObject) As %DynamicObject
{
    Set ev = $SELECT($ISOBJECT(context): context.%Get("evidence"), 1: "")
    Quit $SELECT($ISOBJECT(ev): ev, 1: {})
}

/// The heading a member's instructions carry, which the system prompt must contain.
ClassMethod Heading(member As %String) As %String
{
    Quit $CASE(member, "conformance": "# Conformance specialist", "encounter": "# Encounter Integrity specialist", "impact": "# Impact Analysis specialist", "coordinator": "# Coordinator", "generalist": "# Single investigator", : "")
}

/// Whether a tool result is a failure or a refusal: an error text, or an object with an error and no result.
ClassMethod Failed(text As %String) As %Boolean
{
    If $ZCONVERT($EXTRACT($ZSTRIP(text, "<W"), 1, 5), "L") = "error" Quit 1
    Set o = ..Object(text)
    Quit $ISOBJECT(o) && o.%IsA("%DynamicObject") && o.%IsDefined("error") && 'o.%IsDefined("accepted")
}

/// A tool result for comparison: the JSON without its volatile fields, or the text as it is.
ClassMethod Stable(text As %String) As %String
{
    Set o = ..Object(text)
    If '$ISOBJECT(o) Quit text
    Do ..Strip(o)
    Quit o.%ToJSON()
}

ClassMethod Strip(o As %DynamicAbstractObject)
{
    Set drop = "", isObject = o.%IsA("%DynamicObject")
    Set iter = o.%GetIterator()
    While iter.%GetNext(.k, .v) {
        If isObject && (..#VOLATILE [ ("," _ k _ ",")) Set drop = drop _ $LISTBUILD(k) Continue
        If $ISOBJECT(v) Do ..Strip(v)
    }
    Set p = 0
    While $LISTNEXT(drop, p, k) { Do o.%Remove(k) }
}

/// JSON text as a dynamic object or array, or "".
ClassMethod Object(text As %String) As %DynamicAbstractObject
{
    If $ZSTRIP($GET(text), "<>W") = "" Quit ""
    Try {
        Return ##class(%DynamicAbstractObject).%FromJSON(text)
    } Catch ex {
        Return ""
    }
}

}
