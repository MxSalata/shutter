/// The public demo's way into IRIS: a page in the Management Portal's own application that says what is running, opens the
/// board's case in the Visual Trace, and links to the portal's pages the demo leaves open. It runs as the visitor, on the
/// demo as demo-trace, who reads the databases but holds no SQL privilege on Shutter's tables, so it reads through
/// %ExecDirectNoPriv: fixed queries, and only what the app's public sign-in can read too. That is why it answers only on a
/// demo instance, to a holder of Shutter_Portal or Shutter_Operate: a site's portal users, whose cases hold real messages,
/// get a 404. GET and HEAD only, with no broker, script or form, since the demo's edge refuses a POST to a page. A figure
/// that cannot be read leaves its tile out rather than failing the page.
Class Shutter.Portal.Guide Extends %CSP.Page
{

Parameter CHARSET = "utf-8";

Parameter CONTENTTYPE = "text/html";

/// The seconds between refreshes, a plain meta refresh.
Parameter REFRESH = 30;

/// How many of the latest cases it lists.
Parameter LATEST = 4;

/// The longest headline it shows; the case page has the rest.
Parameter STORYLENGTH = 110;

ClassMethod OnPreHTTP() As %Boolean [ ServerOnly = 1 ]
{
    If (%request.Method '= "GET") && (%request.Method '= "HEAD") {
        Set %response.Status = "405 Method Not Allowed"
        Do %response.SetHeader("Allow", "GET, HEAD")
        Quit 0
    }
    If '..Allowed() {
        Set %response.Status = "404 Not Found"
        Quit 0
    }
    Do %response.SetHeader("Cache-Control", "no-store")
    Do %response.SetHeader("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
    // A request with no session behind it, as from a caller that keeps no cookie, gives its licence unit back at once,
    // so it can't use up the instance's units. A visitor already in a portal session keeps it.
    If $ISOBJECT($GET(%session)) && %session.NewSession Set %session.EndSession = 1
    Quit 1
}

ClassMethod OnPage() As %Status [ ServerOnly = 1 ]
{
    Write ..Html(..Facts(), %request.Application)
    Quit $$$OK
}

/// A demo instance, and a caller the demo's portal is for.
ClassMethod Allowed() As %Boolean
{
    Set ok = 0
    Try {
        Set ok = ''$GET(^Shutter.Config("demo")) && ($SYSTEM.Security.Check("Shutter_Portal", "USE") || $SYSTEM.Security.Check("Shutter_Operate", "USE"))
    } Catch ex {
        Set ok = 0
    }
    Quit ''ok
}

/// What the page shows, read once per request. A figure that can't be read is empty.
ClassMethod Facts() As %DynamicObject
{
    Set f = {}
    Set f.user = $USERNAME, f.namespace = $NAMESPACE
    Set now = $ZDATETIME($ZTIMESTAMP, 3)
    Set f.updated = $PIECE(now, " ", 2)
    Set since = $SYSTEM.SQL.Functions.DATEADD("hh", -1, now)
    Set f.shutter = ..ProductionState($NAMESPACE)
    Set f.hospital = ..ProductionState("HOSPITAL")
    Set f.messages = ..Count("SELECT COUNT(*) AS n FROM Ens.MessageHeader WHERE TimeCreated >= ?", since)
    // 2 is the message status Queued
    Set f.queued = ..Count("SELECT COUNT(*) AS n FROM Ens.MessageHeader WHERE Status = 2")
    // 2 is the event type Error
    Set f.errors = ..Count("SELECT COUNT(*) AS n FROM Ens_Util.Log WHERE Type = 2 AND TimeLogged >= ?", since)
    Set f.feature = ..Feature()
    Set f.cases = ..LatestCases()
    Set f.agents = ..Agents()
    Quit f
}

/// running or stopped, from the runtime global a production keeps in its namespace, or empty when it can't be read. Not
/// Ens.Director's GetProductionStatus, which takes the runtime lock: this page answers every 30 seconds to anyone.
ClassMethod ProductionState(ns As %String) As %String
{
    Set state = ""
    Try {
        Set state = $SELECT($GET(^|ns|Ens.Runtime("Name")) '= "": "running", 1: "stopped")
    } Catch ex {
        Set state = ""
    }
    Quit state
}

/// The first column of a count, or empty when the query can't run.
ClassMethod Count(sql As %String, args...) As %String
{
    Set n = ""
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, args...)
        If (rs.%SQLCODE = 0) && rs.%Next() Set n = rs.%Get("n")
    } Catch ex {
        Set n = ""
    }
    Quit n
}

/// The newest escalated S8 case the agents ran on, found by query since its number changes with each build; "" if none.
ClassMethod Feature() As %DynamicObject
{
    Set out = ""
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 c.CaseId, c.EnsSessionId, (SELECT COUNT(DISTINCT r.MemberCode) FROM Shutter_Store.AgentRun r WHERE r.""Case"" = c.ID) AS Members FROM Shutter_Store.""Case"" c WHERE c.Scenario = 'S8' AND c.State = 'escalated' AND EXISTS (SELECT 1 FROM Shutter_Store.AgentRun a WHERE a.""Case"" = c.ID) ORDER BY c.ID DESC")
        If (rs.%SQLCODE = 0) && rs.%Next() {
            Set out = {}
            Set out.caseId = rs.%Get("CaseId"), out.session = rs.%Get("EnsSessionId"), out.members = +rs.%Get("Members")
        }
    } Catch ex {
        Set out = ""
    }
    Quit out
}

/// The latest cases, newest first.
ClassMethod LatestCases() As %DynamicArray
{
    Set out = []
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP ? CaseId, State, Headline, FailureText, EnsSessionId FROM Shutter_Store.""Case"" ORDER BY ID DESC", ..#LATEST)
        While (rs.%SQLCODE = 0) && rs.%Next() {
            Set story = ..Story(rs.%Get("Headline"), rs.%Get("FailureText"))
            Do out.%Push({"caseId": (rs.%Get("CaseId")), "state": (rs.%Get("State")), "story": (story), "session": (rs.%Get("EnsSessionId"))})
        }
    } Catch ex {
    }
    Quit out
}

/// A case's line: its headline, or the failure when it has none yet. A gate's summary starts "Blocked:", which the
/// workflow's headline has already said.
ClassMethod Story(headline As %String, failure As %String) As %String
{
    Quit $REPLACE($SELECT(headline '= "": headline, 1: failure), "Blocked by the gate: Blocked:", "Blocked by the gate:")
}

/// Each agent that has run here, with when it last did.
ClassMethod Agents() As %DynamicArray
{
    Set out = []
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(MemberCode) AS Member, MAX(StartedAt) AS LastAt FROM Shutter_Store.AgentRun WHERE MemberCode IS NOT NULL GROUP BY %EXACT(MemberCode) ORDER BY %EXACT(MemberCode)")
        While (rs.%SQLCODE = 0) && rs.%Next() {
            Do out.%Push({"member": (rs.%Get("Member")), "lastAt": (rs.%Get("LastAt"))})
        }
    } Catch ex {
    }
    Quit out
}

/// The page. app is this page's web application, whose portal pages it links to.
ClassMethod Html(f As %DynamicObject, app As %String) As %String
{
    If $EXTRACT(app, *) '= "/" Set app = app _ "/"
    Set hospital = ..HospitalApp(app, f.namespace)
    Set h = "<!doctype html><html lang='en-GB'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><meta name='robots' content='noindex'>"
    Set h = h _ "<meta http-equiv='refresh' content='" _ ..#REFRESH _ "'><title>Shutter in IRIS</title><style>" _ ..Css() _ "</style></head><body><main>"
    Set h = h _ "<header><div class='brand'>" _ ..Logo() _ "<div><h1>Shutter in IRIS</h1><p class='sub'>Live from this instance, drawn by IRIS itself. Read only, synthetic data.</p></div></div>"
    Set h = h _ "<p class='who'>Signed in as " _ ..E(f.user) _ ", namespace " _ ..E(f.namespace) _ "<br>Updated " _ ..E(f.updated) _ " UTC, refreshes every " _ ..#REFRESH _ " s</p></header>"
    Set h = h _ "<section class='tiles' aria-label='This instance now'>"
    Set h = h _ ..StateTile("Shutter production", f.shutter, "Shutter.Production")
    Set h = h _ ..StateTile("Hospital production", f.hospital, "Hospital.Production")
    Set h = h _ ..Tile("Messages, last hour", f.messages, "in " _ f.namespace)
    Set h = h _ ..Tile("Queued", f.queued, "waiting in " _ f.namespace)
    Set h = h _ ..Tile("Errors logged, last hour", f.errors, "the Event Log has each one")
    Set h = h _ "</section><div class='columns'><section class='panel wide'><h2>See the board of agents decide</h2>"
    Set h = h _ ..FeatureBox(f.feature, app) _ "<h2>Latest cases</h2>" _ ..CaseRows(f.cases, app)
    Set h = h _ "</section><section class='panel'><h2>Go to</h2>"
    Set h = h _ ..NavRow("Production Monitor", "Every item, live", "EnsPortal.ProductionMonitor.zen", app, hospital)
    Set h = h _ ..NavRow("Message Viewer", "Each message, and its session", "EnsPortal.MessageViewer.zen", app, hospital)
    Set h = h _ ..NavRow("Event Log", "What each component recorded", "EnsPortal.EventLog.zen", app, hospital)
    Set h = h _ "<a class='nav' href='/shutter/index.html'><b>Back to the Shutter app</b><span>Cases, approvals and the board</span></a>"
    Set h = h _ "<h2>Agents</h2>" _ ..AgentRows(f.agents) _ "</section></div>"
    Set h = h _ "<footer><span>Served by Shutter.Portal.Guide, a %CSP.Page in the " _ ..E(f.namespace) _ " namespace</span><span>Other portal pages are closed on the public demo</span></footer>"
    Quit h _ "</main></body></html>"
}

/// The hospital's portal application, or "" when this instance has no HOSPITAL namespace.
ClassMethod HospitalApp(app As %String, ns As %String) As %String
{
    Set out = ""
    Try {
        Set out = $SYSTEM.CSP.GetDefaultApp("HOSPITAL")
    } Catch ex {
        Set out = ""
    }
    If out = "" Set out = $REPLACE(app, "/" _ $ZCONVERT(ns, "L") _ "/", "/hospital/")
    If $EXTRACT(out, *) '= "/" Set out = out _ "/"
    Quit out
}

/// Text for HTML: everything from a case began in a message.
ClassMethod E(text As %String) As %String
{
    Quit $ZCONVERT(text, "O", "HTML")
}

ClassMethod Tile(label As %String, value As %String, hint As %String) As %String
{
    If value = "" Quit ""
    Quit "<div class='tile'><div class='lab'>" _ ..E(label) _ "</div><div class='val'>" _ ..E(value) _ "</div><div class='hint'>" _ ..E(hint) _ "</div></div>"
}

ClassMethod StateTile(label As %String, state As %String, hint As %String) As %String
{
    If state = "" Quit ""
    Quit "<div class='tile'><div class='lab'>" _ ..E(label) _ "</div><div class='val " _ $SELECT(state = "running": "ok", 1: "warn") _ "'>" _ $SELECT(state = "running": "Running", 1: "Stopped") _ "</div><div class='hint'>" _ ..E(hint) _ "</div></div>"
}

/// A case's Visual Trace, when it has a session.
ClassMethod TraceHref(session As %String, app As %String) As %String
{
    If (session = "") || (session '? 1.N) Quit ""
    Quit app _ "EnsPortal.VisualTrace.zen?SESSIONID=" _ session
}

ClassMethod FeatureBox(feature As %DynamicObject, app As %String) As %String
{
    If '$ISOBJECT(feature) Quit "<div class='feature'><div><b>No board case on this instance yet</b><span>An escalated S8 case appears here once the agents have run on one.</span></div></div>"
    Set href = ..TraceHref(feature.session, app)
    Set n = feature.members
    Set h = "<div class='feature'><div><b>" _ ..E(feature.caseId) _ ": the escalated S8 case</b><span>" _ n _ $SELECT(n = 1: " agent", 1: " agents") _ ", each in its own lane, then the gate.</span></div>"
    If href '= "" Set h = h _ "<a class='btn' href='" _ href _ "'>Open Visual Trace</a>"
    Quit h _ "</div>"
}

ClassMethod CaseRows(cases As %DynamicArray, app As %String) As %String
{
    If cases.%Size() = 0 Quit "<p class='none'>No case on this instance yet.</p>"
    Set h = "", it = cases.%GetIterator()
    While it.%GetNext(, .c) {
        Set story = c.story
        If $LENGTH(story) > ..#STORYLENGTH Set story = $EXTRACT(story, 1, ..#STORYLENGTH) _ "..."
        Set href = ..TraceHref(c.session, app)
        Set h = h _ "<div class='line'><b>" _ ..E(c.caseId) _ "</b><span class='story'>" _ ..E(story) _ "</span><span class='state" _ $SELECT(c.state = "escalated": " warn", c.state = "blocked": " warn", c.state = "resolved": " ok", 1: "") _ "'>" _ ..E(c.state) _ "</span>"
        If href '= "" Set h = h _ "<a class='btn small' href='" _ href _ "' aria-label='Trace of " _ ..E(c.caseId) _ "'>Trace</a>"
        Set h = h _ "</div>"
    }
    Quit h
}

ClassMethod NavRow(title As %String, about As %String, page As %String, app As %String, hospital As %String) As %String
{
    Quit "<div class='nav'><b>" _ ..E(title) _ "</b><span>" _ ..E(about) _ "</span><span class='pair'><a href='" _ app _ page _ "'>Shutter</a><a href='" _ hospital _ page _ "'>Hospital</a></span></div>"
}

ClassMethod AgentRows(agents As %DynamicArray) As %String
{
    If agents.%Size() = 0 Quit "<p class='none'>No agent has run on this instance yet.</p>"
    Set h = "", it = agents.%GetIterator()
    While it.%GetNext(, .a) {
        Set at = $TRANSLATE($EXTRACT(a.lastAt, 1, 16), "T", " ")
        Set h = h _ "<div class='lane'><span class='dot' aria-hidden='true'></span><span>Agent " _ ..E($ZCONVERT(a.member, "W")) _ "</span><span class='num'>" _ $SELECT(at = "": "", 1: "last " _ ..E(at) _ " UTC") _ "</span></div>"
    }
    Quit h
}

ClassMethod Logo() As %String
{
    Quit "<svg viewBox='0 0 32 32' aria-hidden='true'><defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#095c7c'/><stop offset='1' stop-color='#45acd1'/></linearGradient></defs><rect width='32' height='32' rx='8' fill='url(#g)'/><g fill='none' stroke='#fff' stroke-width='1.9' stroke-linecap='round'><circle cx='16' cy='16' r='10.2'/><line x1='16' y1='11.4' x2='26.12' y2='17.24'/><line x1='19.98' y1='13.7' x2='19.98' y2='25.39'/><line x1='19.98' y1='18.3' x2='9.86' y2='24.14'/><line x1='16' y1='20.6' x2='5.88' y2='14.76'/><line x1='12.02' y1='18.3' x2='12.02' y2='6.61'/><line x1='12.02' y1='13.7' x2='22.14' y2='7.86'/></g></svg>"
}

ClassMethod Css() As %String
{
    Set c = ":root{color-scheme:light dark;--bg:#f4f7f9;--panel:#fff;--soft:#e9f2f6;--text:#16232b;--muted:#55666f;--line:#d5dfe4;--accent:#095c7c;--on:#fff;--ok:#1a7a44;--warn:#8a5a00}"
    Set c = c _ "@media (prefers-color-scheme:dark){:root{--bg:#0d1518;--panel:#152127;--soft:#17303b;--text:#e8f0f3;--muted:#9db0b9;--line:#2a3b43;--accent:#45acd1;--on:#06202b;--ok:#5fd08a;--warn:#e8c26a}}"
    Set c = c _ "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif}main{max-width:1200px;margin:0 auto;padding:32px 16px 40px;display:flex;flex-direction:column;gap:20px}"
    Set c = c _ "header{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:12px}.brand{display:flex;align-items:center;gap:14px}.brand svg{width:44px;height:44px;flex:none}h1{margin:0;font-size:1.75rem;line-height:1.2;font-weight:600}.sub,.who{margin:0;color:var(--muted);font-size:.875rem}"
    Set c = c _ ".tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:16px}.tile,.panel{background:var(--panel);border:1px solid var(--line);border-radius:12px}.tile{padding:16px 18px}.lab,.hint{color:var(--muted);font-size:.8125rem}.val{font-size:1.625rem;line-height:2rem;font-weight:600}.ok{color:var(--ok)}.warn{color:var(--warn)}"
    Set c = c _ ".columns{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}@media (min-width:900px){.columns{grid-template-columns:2fr 1fr}}.panel{padding:18px 20px;display:flex;flex-direction:column;gap:10px;min-width:0}h2{margin:6px 0 2px;font-size:1.0625rem;font-weight:600}"
    Set c = c _ ".feature{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:12px;background:var(--soft);border:1px solid var(--accent);border-radius:10px;padding:14px 16px}.feature b,.nav b{display:block;font-weight:600}.feature span,.nav span{display:block;color:var(--muted);font-size:.8125rem}"
    Set c = c _ ".line{display:flex;flex-wrap:wrap;align-items:center;gap:6px 12px;padding:9px 12px;border-radius:8px;background:var(--soft)}.story{flex:1 1 220px;min-width:0;overflow-wrap:anywhere;font-size:.875rem}.state{font-size:.8125rem;color:var(--muted);min-width:76px}.state.ok{color:var(--ok)}.state.warn{color:var(--warn)}"
    Set c = c _ ".btn{flex:none;display:inline-block;background:var(--accent);color:var(--on);font-weight:600;font-size:.875rem;padding:9px 14px;border-radius:8px;text-decoration:none}.btn.small{padding:5px 12px;font-size:.8125rem}a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}"
    Set c = c _ ".nav{display:block;padding:10px 12px;border-radius:8px;background:var(--soft);color:inherit;text-decoration:none}a.nav:hover{outline:1px solid var(--accent)}.pair{margin-top:4px}.pair a{color:var(--accent);margin-right:14px;font-weight:600}"
    Set c = c _ ".lane{display:flex;align-items:center;gap:10px;font-size:.8125rem}.dot{width:10px;height:10px;border-radius:50%;background:var(--ok);flex:none}.num{margin-left:auto;color:var(--muted)}.none{margin:0;color:var(--muted);font-size:.875rem}"
    Quit c _ "footer{display:flex;flex-wrap:wrap;justify-content:space-between;gap:8px;color:var(--muted);font-size:.8125rem;border-top:1px solid var(--line);padding-top:12px}"
}

}
