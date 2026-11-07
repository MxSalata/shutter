/// The routes of the Settings screen for watched namespaces (CONTRACTS 11.1), so that onboarding can be read and done by
/// someone who does not write SQL. Everything is the work of Shutter.Util.Onboard, called as the SQL procedures call it:
/// this class checks who is asking and what was shown to them. A plan comes with a digest of what it says and the options
/// it was read with, and an apply must bring that digest back, so what runs is what the person read. The forwarder's
/// password never comes through here: Setup.OnboardCredential stays a terminal command.
Class Shutter.API.Onboarding
{

/// The options a plan or an apply takes (CONTRACTS 11.1), in the order the digest reads them.
Parameter OPTIONS = "production,shutter_host,shutter_port,ssl_config,credential,receivers,alert_on_error";

/// The instance's own namespaces, never offered.
Parameter SYSTEMNAMESPACES = "%SYS,HSCUSTOM,HSLIB,HSSYS,ENSLIB,ENSDEMO";

/// Changes to a namespace need this as well as Shutter_Configure, as Shutter.Util.Onboard asks.
Parameter ADMIN = "%Admin_Manage";

/// The options as the helpers should read them: only known names, and an empty value is as if not given. Anything else sets
/// problem, so a slip never runs on the defaults.
ClassMethod CleanOptions(options, Output problem As %String) As %DynamicObject
{
    Set problem = "", clean = {}
    If (options = "") Quit clean
    If '$ISOBJECT(options) || 'options.%IsA("%DynamicObject") Set problem = "options must be a JSON object" Quit clean
    Set allowed = $LISTFROMSTRING(..#OPTIONS)
    Set it = options.%GetIterator()
    While it.%GetNext(.key, .value) {
        If '$LISTFIND(allowed, key) Set problem = "There is no option " _ key _ ", so nothing was read or changed" Quit
        If $ISOBJECT(value) Set problem = "The option " _ key _ " must be a plain value, so nothing was read or changed" Quit
        If options.%GetTypeOf(key) = "boolean" { Do clean.%Set(key, value, "boolean") Continue }
        If (value '= "") Do clean.%Set(key, value)
    }
    Quit clean
}

/// A digest of what a person reads in a plan, and the options it was read with.
ClassMethod Digest(plan As %DynamicObject, options As %DynamicObject) As %String
{
    Set text = plan.production _ $CHAR(10) _ plan.actions.%ToJSON() _ $CHAR(10) _ plan.warnings.%ToJSON() _ $CHAR(10) _ plan.todo.%ToJSON()
    Set allowed = $LISTFROMSTRING(..#OPTIONS)
    For i = 1:1:$LISTLENGTH(allowed) {
        Set key = $LIST(allowed, i)
        If $ISOBJECT(options) && options.%IsDefined(key) Set text = text _ $CHAR(10) _ key _ "=" _ options.%Get(key)
    }
    Quit ##class(Shutter.Util.Digest).SHA256Hex(text)
}

/// The fresh plan and its digest when the digest brought back is not its own; "" when it is.
ClassMethod StalePlan(ns As %String, options As %DynamicObject, digest As %String) As %DynamicObject
{
    Set plan = ##class(Shutter.Util.Onboard).Plan(ns, options)
    Set now = ..Digest(plan, options)
    If now = digest Quit ""
    Quit {"plan": (plan), "digest": (now)}
}

/// Whether a namespace may be offered at all: not Shutter's own, one of the instance's, or an implied one (^^path).
ClassMethod Offerable(ns As %String, own As %String = {$NAMESPACE}) As %Boolean
{
    If (ns = "") || (ns = own) || ($EXTRACT(ns) = "^") Quit 0
    Quit '$LISTFIND($LISTFROMSTRING(..#SYSTEMNAMESPACES), ns)
}

/// The namespaces with Interoperability enabled that could be onboarded, the watched ones left out: [{namespace}].
ClassMethod Available(watched As %DynamicArray = "") As %DynamicArray
{
    Set out = [], taken = ""
    If $ISOBJECT(watched) {
        Set it = watched.%GetIterator()
        While it.%GetNext(, .w) { If 'w.removed Set taken(w.namespace) = 1 }
    }
    Set own = $NAMESPACE
    Do ##class(%SYS.Namespace).ListAll(.all)
    Set ns = ""
    For {
        Set ns = $ORDER(all(ns)) Quit:ns=""
        Continue:'..Offerable(ns, own)
        Continue:$DATA(taken(ns))
        Set enabled = 0
        Try { Set enabled = ##class(%EnsembleMgr).IsEnsembleNamespace(ns) } Catch ex { Set enabled = 0 }
        If enabled Do out.%Push({"namespace": (ns)})
    }
    Quit out
}

/// What taking a namespace off would touch, from the record the apply kept: it reads and changes nothing. Whether a mapping
/// or a draft really goes is decided at the removal (messages left, a person's edit), and the answer then says which.
ClassMethod RemovalPreview(ns As %String) As %DynamicObject
{
    Set ns = ##class(Shutter.Util.Onboard).NS(ns)
    Set p = {"namespace": (ns), "production": ($GET(^Shutter.Config("onboard", ns))), "renamed": ($GET(^Shutter.Config("onboard", ns, "renamed"))), "items": [], "alertOnError": [], "mappings": [], "drafted": []}
    Do p.%Set("onboarded", $DATA(^Shutter.Config("onboard", ns)) > 0, "boolean")
    For part = "items", "alertOnError", "mappings", "drafted" {
        Set list = p.%Get(part), key = ""
        For { Set key = $ORDER(^Shutter.Config("onboard", ns, part, key)) Quit:key=""  Do list.%Push(key) }
    }
    Quit p
}

/// A helper's answer, with anything it writes kept away from the current device. Ens.Director.UpdateProduction writes its
/// progress there, and on a REST route that device is the reply, which then is no longer JSON.
ClassMethod Quietly(class As %String, method As %String, args...) As %DynamicObject
{
    Set io = $IO, null = $SELECT($SYSTEM.Version.GetOS() = "Windows": "NUL", 1: "/dev/null")
    Open null:"W":5
    If '$TEST Quit {"ok": false, "error": "Nothing was changed: the null device could not be opened"}
    Use null
    Try {
        Set answer = $CLASSMETHOD(class, method, args...)
    } Catch ex {
        Set answer = {"ok": false, "error": (ex.DisplayString())}
    }
    Use io
    Close null
    Quit answer
}

/// The request's body as an object: {} when empty, "" (after a 400) when it is not a JSON object.
ClassMethod BodyOr400() As %DynamicObject [ Private ]
{
    Set text = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    If $ZSTRIP(text, "<>W") = "" Quit {}
    Set body = ##class(Shutter.Util.Json).Parse(text, .sc)
    If $ISOBJECT(body) && body.%IsA("%DynamicObject") Quit body
    Do ##class(Shutter.API.Dispatch).Fail("400 Bad Request", "bad_request", "The body must be a JSON object")
    Quit ""
}

/// The body's options, checked; "" (after a 400) when they are not usable.
ClassMethod OptionsOr400(body As %DynamicObject) As %DynamicObject [ Private ]
{
    Set clean = ..CleanOptions(body.%Get("options"), .problem)
    If problem = "" Quit clean
    Do ##class(Shutter.API.Dispatch).Fail("400 Bad Request", "bad_request", problem)
    Quit ""
}

/// Whether the signed-in user may change a namespace; a 403 is written when not.
ClassMethod AdminOr403() As %Boolean [ Private ]
{
    If $SYSTEM.Security.Check(..#ADMIN, "USE") Quit 1
    Do ##class(Shutter.API.Dispatch).Fail("403 Forbidden", "forbidden", "This changes the instance's configuration: it needs a user holding " _ ..#ADMIN)
    Quit 0
}

/// GET /settings/namespaces: those watched (the Doctor's view) and those that could be, and whether this user may apply.
ClassMethod List() As %Status
{
    Set d = "Shutter.API.Dispatch"
    If '$CLASSMETHOD(d, "Allow", "Shutter_Configure") Quit $$$OK
    Set watched = ##class(Shutter.Util.Onboard).Watched()
    Set o = {"shutterNamespace": ($NAMESPACE), "watched": (watched), "available": (..Available(watched))}
    Do o.%Set("canApply", $SYSTEM.Security.Check(..#ADMIN, "USE"), "boolean")
    Quit $CLASSMETHOD(d, "Json", o)
}

/// POST /settings/namespaces/{ns}/plan {options}: the plan, changing nothing, with its digest.
ClassMethod Plan(ns As %String) As %Status
{
    Set d = "Shutter.API.Dispatch"
    If '$CLASSMETHOD(d, "Allow", "Shutter_Configure", 1) Quit $$$OK
    Set body = ..BodyOr400() If '$ISOBJECT(body) Quit $$$OK
    Set options = ..OptionsOr400(body) If '$ISOBJECT(options) Quit $$$OK
    Set plan = ##class(Shutter.Util.Onboard).Plan(ns, options)
    Quit $CLASSMETHOD(d, "Json", {"plan": (plan), "digest": (..Digest(plan, options))})
}

/// POST /settings/namespaces/{ns}/apply {options, digest}: runs the plan that digest names, and no other. 409 plan_changed
/// with the fresh plan when the namespace or the site profile has moved since it was read.
ClassMethod Apply(ns As %String) As %Status
{
    Set d = "Shutter.API.Dispatch"
    If '$CLASSMETHOD(d, "Allow", "Shutter_Configure", 1) Quit $$$OK
    If '..AdminOr403() Quit $$$OK
    Set body = ..BodyOr400() If '$ISOBJECT(body) Quit $$$OK
    Set options = ..OptionsOr400(body) If '$ISOBJECT(options) Quit $$$OK
    Set digest = ##class(Shutter.Util.Json).Str(body, "digest")
    If digest = "" Quit $CLASSMETHOD(d, "Fail", "400 Bad Request", "bad_request", "The body must carry the digest of the plan that was read: nothing was changed")
    Set stale = ..StalePlan(ns, options, digest)
    If $ISOBJECT(stale) Quit $CLASSMETHOD(d, "Fail", "409 Conflict", "plan_changed", "The plan has changed since it was read, so nothing was changed. Read the new plan", stale)
    Quit $CLASSMETHOD(d, "Json", ..Quietly("Shutter.Util.Onboard", "Apply", ns, options))
}

/// POST /settings/namespaces/{ns}/test: a marked test failure through the namespace's forwarder settings.
ClassMethod Test(ns As %String) As %Status
{
    Set d = "Shutter.API.Dispatch"
    If '$CLASSMETHOD(d, "Allow", "Shutter_Configure", 1) Quit $$$OK
    Quit $CLASSMETHOD(d, "Json", ..Quietly("Shutter.Util.Onboard", "Test", ns))
}

/// GET /settings/namespaces/{ns}/removal: what a removal would touch, changing nothing.
ClassMethod Removal(ns As %String) As %Status
{
    Set d = "Shutter.API.Dispatch"
    If '$CLASSMETHOD(d, "Allow", "Shutter_Configure") Quit $$$OK
    Quit $CLASSMETHOD(d, "Json", ..RemovalPreview(ns))
}

/// POST /settings/namespaces/{ns}/remove {unmap, credential}: takes off what the apply added, and says what stays.
ClassMethod Remove(ns As %String) As %Status
{
    Set d = "Shutter.API.Dispatch"
    If '$CLASSMETHOD(d, "Allow", "Shutter_Configure", 1) Quit $$$OK
    If '..AdminOr403() Quit $$$OK
    Set body = ..BodyOr400() If '$ISOBJECT(body) Quit $$$OK
    Set options = {}, wrong = ""
    Set it = body.%GetIterator()
    While it.%GetNext(.key, .value) {
        If (key = "unmap") || (key = "credential") { Do options.%Set(key, ''value, "boolean") } Else { Set wrong = key }
    }
    If wrong '= "" Quit $CLASSMETHOD(d, "Fail", "400 Bad Request", "bad_request", "There is no option " _ wrong _ ", so nothing was changed")
    Quit $CLASSMETHOD(d, "Json", ..Quietly("Shutter.Util.Onboard", "Remove", ns, options))
}

}
