/// GET /access (CONTRACTS 5): what each of the roles Shutter installs may do in Shutter, beside what the signed-in
/// caller may, for the Settings page's "Your access" table. A comparison to read, never a switch: nothing here changes who
/// the caller is or what they hold. Each role's column comes from its resources in Security.Roles, its granted roles'
/// included, as Shutter.Setup.CreateSecurity defines them (EnsureRole). Reading Security.Roles needs %Admin_Secure, which
/// no Shutter role holds, so the install, the portal's hardening and every start of the production record each role's
/// resources (Record) and a caller without it reads that record: a role a site changed by hand shows as it is from the
/// next start. The caller's column comes from $SYSTEM.Security.Check, as GET /me reads it, so a custom role is shown truly.
/// The reply names roles and resources, never a user, a password or anyone else.
Class Shutter.API.Access Extends %RegisteredObject
{

/// The roles a person signs in with, in the table's order: the public demo's viewer, the judges, the operator and the
/// approver. Shutter_Trace, the Management Portal's read-only role on the public demo, is read too, for the rows it has.
Parameter ROLES = "Shutter_Demo,Shutter_Judge,Shutter_Operator,Shutter_Approver,Shutter_Trace";

/// The rows, in order: what a person can do in Shutter.
Parameter ROWS = "view,approve,scenarios,reset,liveAgents,configure,inbox,guide,trace,publisher";

/// The Management Portal's page that holds the Workflow inbox (it names no resource of its own: the portal's pages need
/// %Ens_Portal, and the tasks reach the members of the Workflow role Shutter Approvers).
Parameter INBOXPAGE = "EnsPortal.WFWorklist";

/// The Management Portal's Visual Trace page.
Parameter TRACEPAGE = "EnsPortal.VisualTrace";

/// The whole reply: {demo, portalHardened, read, recordedAt, roles: [{role, installed}], rows: [{id, needs, available,
/// roles: {role: bool}, you}]}. needs is a list of alternatives, each a list of resources all of which a holder needs (as
/// resource:permission). read says where the roles' columns came from: "now" (Security.Roles, for a caller with
/// %Admin_Secure), "recorded" (the record, with its time) or "none" (no record yet: every role reads as not installed).
/// live is 1 or 0 to choose, for the tests; -1 reads now when the caller may.
ClassMethod Report(live As %Integer = -1) As %DynamicObject
{
    Set out = {}
    Set demo = ''$GET(^Shutter.Config("demo")), hardened = ($GET(^Shutter.Config("portalHardened")) '= "")
    If live = -1 Set live = $SYSTEM.Security.Check("%Admin_Secure", "USE")
    Do out.%Set("demo", demo, "boolean")
    Do out.%Set("portalHardened", hardened, "boolean")
    Set at = $GET(^Shutter.Config("access", "at"))
    Set out.read = $SELECT(live: "now", at '= "": "recorded", 1: "none")
    If 'live && (at '= "") Set out.recordedAt = at
    // Each role's resources, its granted roles' included: role -> "," _ name:perms _ "," ...
    Set roles = [], roleList = $LISTFROMSTRING(..#ROLES, ",")
    For i = 1:1:$LISTLENGTH(roleList) {
        Set role = $LIST(roleList, i), installed = 0
        If live {
            Set held(role) = ..Held(role, .installed)
        } Else {
            Set rec = $GET(^Shutter.Config("access", "roles", role))
            Set installed = +$LISTGET(rec, 1), held(role) = $LISTGET(rec, 2, ",")
        }
        Set r = {"role": (role)}
        Do r.%Set("installed", installed, "boolean")
        Do roles.%Push(r)
    }
    Set out.roles = roles
    Set rows = [], rowList = $LISTFROMSTRING(..#ROWS, ",")
    For i = 1:1:$LISTLENGTH(rowList) {
        Set id = $LIST(rowList, i)
        Set needs = ..Needs(id, hardened)
        Set available = ..Available(id, demo)
        Set row = {"id": (id), "needs": (needs)}
        Do row.%Set("available", available, "boolean")
        Set cells = {}
        For j = 1:1:$LISTLENGTH(roleList) {
            Set role = $LIST(roleList, j)
            Do cells.%Set(role, available && ..Meets(needs, held(role)), "boolean")
        }
        Set row.roles = cells
        Do row.%Set("you", available && ..CallerMeets(needs), "boolean")
        Do rows.%Push(row)
    }
    Set out.rows = rows
    Quit out
}

/// Records each role's resources in ^Shutter.Config("access") of the namespace, from Security.Roles, for the callers who
/// may not read it: {"roles", role} = $LISTBUILD(installed, held) and "at" the time. Called by the install
/// (Setup.CreateSecurity), the portal's hardening and every start of the production (Setup.ApplyEnvironment), which may
/// read it; a process without %Admin_Secure changes nothing. Returns 1 when it recorded.
ClassMethod Record(ns As %String = {$NAMESPACE}) As %Boolean
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit 0
    Set roleList = $LISTFROMSTRING(..#ROLES, ",")
    For i = 1:1:$LISTLENGTH(roleList) {
        Set role = $LIST(roleList, i), installed = 0
        Set held = ..Held(role, .installed)
        Set ^|ns|Shutter.Config("access", "roles", role) = $LISTBUILD(installed, held)
    }
    Set ^|ns|Shutter.Config("access", "at") = ##class(Shutter.Util.Time).NowUTC()
    Quit 1
}

/// What a row needs, as alternatives of resources (each resource:permission). The portal's pages need the portal
/// application's resource too once the public demo's hardening has made it Shutter_Portal (Setup.HardenPortal).
ClassMethod Needs(id As %String, hardened As %Boolean = 0) As %DynamicArray
{
    Set portal = $SELECT(hardened: ["Shutter_Portal:U"], 1: [])
    If id = "view" Quit [["Shutter_Operate:U"]]
    If id = "approve" Quit [["Shutter_Approve:U"]]
    If id = "scenarios" Quit [["Shutter_Scenarios:U"]]
    If id = "reset" Quit [["Shutter_ScenarioReset:U"]]
    If id = "liveAgents" Quit [["Shutter_LiveAgents:U"]]
    If id = "configure" Quit [["Shutter_Configure:U"]]
    If id = "publisher" Quit [["Shutter_Publish:U"]]
    // The Workflow inbox: the portal's pages, and the approvals the tasks are (Shutter Approvers' members are approvers).
    If id = "inbox" Quit [(..With(["%Ens_Portal:U", "Shutter_Approve:U"], ..PageResource(..#INBOXPAGE), portal))]
    If id = "trace" Quit [(..With(["%Ens_Portal:U"], ..PageResource(..#TRACEPAGE), portal))]
    // The Shutter in IRIS page (Shutter.Portal.Guide.Allowed): a holder of Shutter_Portal or of Shutter_Operate.
    If id = "guide" Quit [(..With(["Shutter_Portal:U"], "", portal)), (..With(["Shutter_Operate:U"], "", portal))]
    Quit []
}

/// A list of resources with one more and another list's added, each once.
ClassMethod With(list As %DynamicArray, one As %String, more As %DynamicArray) As %DynamicArray [ Private ]
{
    Set seen = ""
    Set out = []
    Set iter = list.%GetIterator()
    While iter.%GetNext(.k, .v) { If '$FIND(seen, "," _ v _ ",") Do out.%Push(v) Set seen = seen _ "," _ v _ "," }
    If (one '= "") && '$FIND(seen, "," _ one _ ",") Do out.%Push(one) Set seen = seen _ "," _ one _ ","
    Set iter = more.%GetIterator()
    While iter.%GetNext(.k, .v) { If '$FIND(seen, "," _ v _ ",") Do out.%Push(v) Set seen = seen _ "," _ v _ "," }
    Quit out
}

/// The resource a portal page asks of its user (its RESOURCE parameter, as resource or resource:permission), as
/// resource:U, or "" when the page or the parameter is not there. Only the first is taken when it names several.
ClassMethod PageResource(page As %String) As %String
{
    Set res = ""
    Try {
        If ##class(%Dictionary.CompiledClass).%ExistsId(page) Set res = $PARAMETER(page, "RESOURCE")
    } Catch ex {
        Set res = ""
    }
    Set res = $ZSTRIP($PIECE(res, ",", 1), "<>W")
    If res = "" Quit ""
    Set name = $PIECE(res, ":", 1), perm = $ZCONVERT($PIECE(res, ":", 2), "U")
    Set perm = $SELECT(perm = "": "U", perm [ "USE": "U", perm [ "WRITE": "W", perm [ "READ": "R", 1: $EXTRACT(perm))
    Quit name _ ":" _ perm
}

/// Whether a row is there to have on this instance: the Shutter in IRIS page on a demo instance alone, the publisher
/// where this build has it and its web application was made (the Doctor's publish block).
ClassMethod Available(id As %String, demo As %Boolean) As %Boolean
{
    If id = "guide" Quit ''demo
    If id = "publisher" Quit ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Publish.Service") && ''$GET(^Shutter.Config("webapp", "/mcp/shutter"))
    If id = "inbox" Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#INBOXPAGE)
    If id = "trace" Quit ..PageResource(..#TRACEPAGE) '= ""
    Quit 1
}

/// Whether a set of held resources ("," _ name:perms _ ",", as Held answers) meets one of the alternatives.
ClassMethod Meets(needs As %DynamicArray, held As %String) As %Boolean
{
    Set iter = needs.%GetIterator()
    While iter.%GetNext(.k, .alt) {
        Set ok = 1, inner = alt.%GetIterator()
        While inner.%GetNext(.n, .res) {
            If '..Holds(held, $PIECE(res, ":", 1), $PIECE(res, ":", 2)) Set ok = 0 Quit
        }
        If ok Quit
    }
    Quit +$GET(ok)
}

/// Whether the held set grants a resource with a permission (U, R or W).
ClassMethod Holds(held As %String, name As %String, perm As %String) As %Boolean
{
    Set at = $FIND($ZCONVERT(held, "U"), "," _ $ZCONVERT(name, "U") _ ":")
    If 'at Quit 0
    Set perms = $ZCONVERT($PIECE($EXTRACT(held, at, *), ",", 1), "U")
    Quit (perm = "") || (perms [ perm)
}

/// Whether the caller meets one of the alternatives, by $SYSTEM.Security.Check, as GET /me reads it.
ClassMethod CallerMeets(needs As %DynamicArray) As %Boolean
{
    Set iter = needs.%GetIterator()
    While iter.%GetNext(.k, .alt) {
        Set ok = 1, inner = alt.%GetIterator()
        While inner.%GetNext(.n, .res) {
            Set perm = $CASE($PIECE(res, ":", 2), "R": "READ", "W": "WRITE", : "USE")
            If '$SYSTEM.Security.Check($PIECE(res, ":", 1), perm) Set ok = 0 Quit
        }
        If ok Quit
    }
    Quit +$GET(ok)
}

/// A role's resources with its granted roles' (to any depth, each role once), as "," _ name:perms _ "," ... ; a resource
/// two roles grant keeps both permissions. installed is 0 when the role is not defined. Read in %SYS.
ClassMethod Held(role As %String, Output installed As %Boolean) As %String
{
    Set installed = 0, held = ",", todo = $LISTBUILD(role), done = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set installed = ''##class(Security.Roles).Exists(role)
        Quit:'installed
        Set i = 0
        While i < $LISTLENGTH(todo) {
            Set i = i + 1, name = $LIST(todo, i)
            Continue:$LISTFIND(done, name)
            Set done = done _ $LISTBUILD(name)
            Kill p
            Continue:'##class(Security.Roles).Exists(name)
            Continue:$$$ISERR(##class(Security.Roles).Get(name, .p))
            For j = 1:1:$LENGTH($GET(p("Resources")), ",") {
                Set r = $ZSTRIP($PIECE(p("Resources"), ",", j), "<>W")
                Continue:r=""
                Set held = held _ r _ ","
            }
            For j = 1:1:$LENGTH($GET(p("GrantedRoles")), ",") {
                Set g = $ZSTRIP($PIECE(p("GrantedRoles"), ",", j), "<>W")
                If (g '= "") && '$LISTFIND(todo, g) Set todo = todo _ $LISTBUILD(g)
            }
        }
    } Catch ex {
        Set held = ","
    }
    // The same resource from two roles: one entry with every permission either grants.
    Set out = ",", seen = ""
    For j = 2:1:$LENGTH(held, ",") - 1 {
        Set r = $PIECE(held, ",", j), name = $ZCONVERT($PIECE(r, ":", 1), "U")
        Continue:name=""
        Set perms(name) = $GET(perms(name)) _ $PIECE(r, ":", 2), label(name) = $PIECE(r, ":", 1)
    }
    Set name = ""
    For {
        Set name = $ORDER(perms(name))
        Quit:name=""
        Set out = out _ label(name) _ ":" _ perms(name) _ ","
    }
    Quit out
}

}
