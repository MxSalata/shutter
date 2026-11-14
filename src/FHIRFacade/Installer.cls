/// What serves the test FHIR server over HTTP on a demo install: its two resources, the role and the user the
/// production's FHIR items sign in with, their credential, and the web application <code>/fhir-facade/r4</code>. A site
/// install never calls this: a site's FHIR receiver is its own server.
Class FHIRFacade.Installer
{

/// The web application the test FHIR server answers at.
Parameter APPLICATION = "/fhir-facade/r4";

/// The user the production's FHIR items sign in as, and the credential that holds it.
Parameter USER = "fhir-client";

Parameter CREDENTIAL = "FHIRFacade";

/// The role that lets a caller read and write through <class>FHIRFacade.API</class>.
Parameter ROLE = "Shutter_FHIRFacadeClient";

/// Creates what is missing and brings the rest to this definition, for the namespace <var>ns</var>. Safe to run again.
/// <ul>
/// <li>the resources <code>FHIRFacade_API</code> and <code>FHIRFacade_Admin</code>, the names
/// <class>FHIRFacade.API</class> checks. The controls' resource is granted to no role here: an administrator holds it
/// through %All;</li>
/// <li>the role with <code>FHIRFacade_API:RW</code>;</li>
/// <li>the user, with that role and the one that carries the namespace's databases
/// (<code>Shutter_DownstreamClient</code>, or <code>Shutter_Operator</code> when that role is absent), and the demo's
/// password, whatever an earlier install left, so the credential always matches the user;</li>
/// <li>the credential, in <var>ns</var>;</li>
/// <li>the web application, with a password and nothing else: no resource and no matching roles, since the class
/// checks the resources itself and answers a caller without them as IRIS's own FHIR server does;</li>
/// <li>the node that tells the uninstall the application is Shutter's.</li>
/// </ul>
ClassMethod Install(ns As %String) As %Status
{
    Set sc = $$$OK
    Set namespace = $NAMESPACE
    Try {
        If ns = "" Set ns = namespace
        Set password = $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_PASSWORD")
        If password = "" Set password = "shutter"
        Set $NAMESPACE = "%SYS"
        Set sc = ..Security(ns, password)
        Set:$$$ISOK(sc) sc = ..Application(ns)
        Set $NAMESPACE = ns
        Set:$$$ISOK(sc) sc = ##class(Ens.Config.Credentials).SetCredential(..#CREDENTIAL, ..#USER, password, 1)
        Set:$$$ISOK(sc) ^Shutter.Config("webapp", ..#APPLICATION) = 1
        Set $NAMESPACE = namespace
    } Catch ex {
        Set $NAMESPACE = namespace
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// <method>Install</method> for scripts that reach IRIS through SQL: "ok", or the error text.
ClassMethod InstallSql(ns As %String = "") As %String [ SqlProc ]
{
    Set sc = ..Install(ns)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// The resources, the role and the user. Runs in %SYS.
ClassMethod Security(ns As %String, password As %String) As %Status [ Private ]
{
    Set sc = $$$OK
    If '##class(Security.Resources).Exists("FHIRFacade_API") {
        Set sc = ##class(Security.Resources).Create("FHIRFacade_API", "The test FHIR server's API: READ to read, WRITE to write", "")
        Quit:$$$ISERR(sc) sc
    }
    If '##class(Security.Resources).Exists("FHIRFacade_Admin") {
        Set sc = ##class(Security.Resources).Create("FHIRFacade_Admin", "The test FHIR server's controls: reset, faults and the counters", "")
        Quit:$$$ISERR(sc) sc
    }
    Set description = "Shutter: the production's client of the test FHIR server"
    If '##class(Security.Roles).Exists(..#ROLE) {
        Set sc = ##class(Security.Roles).Create(..#ROLE, description, "FHIRFacade_API:RW", "")
    } Else {
        Kill props
        Set props("Description") = description, props("Resources") = "FHIRFacade_API:RW", props("GrantedRoles") = ""
        Set sc = ##class(Security.Roles).Modify(..#ROLE, .props)
    }
    Quit:$$$ISERR(sc) sc
    // The role above carries only the server's own resource; the database comes with the downstream client's role,
    // or the web application answers 403.
    Set roles = ..#ROLE _ "," _ $SELECT(##class(Security.Roles).Exists("Shutter_DownstreamClient"): "Shutter_DownstreamClient", 1: "Shutter_Operator")
    If '##class(Security.Users).Exists(..#USER) {
        Quit ##class(Security.Users).Create(..#USER, roles, password, "Shutter production client for the test FHIR server", ns, "", "", 0, 1, "Used by the production's HTTP operation")
    }
    Set sc = ##class(Security.Users).AddRoles(..#USER, roles)
    Quit:$$$ISERR(sc) sc
    Kill props
    Set props("Password") = password, props("Enabled") = 1, props("ChangePassword") = 0, props("PasswordNeverExpires") = 1
    Quit ##class(Security.Users).Modify(..#USER, .props)
}

/// The web application. Runs in %SYS.
ClassMethod Application(ns As %String) As %Status [ Private ]
{
    Set props("NameSpace") = ns
    Set props("Description") = "Shutter: the test FHIR R4 server of the demo"
    Set props("Enabled") = 1
    Set props("AutheEnabled") = 32
    Set props("DispatchClass") = "FHIRFacade.API"
    Set props("Resource") = ""
    Set props("MatchRoles") = ""
    Set props("UseCookies") = 2
    Set props("CookiePath") = ..#APPLICATION _ "/"
    If ##class(Security.Applications).Exists(..#APPLICATION) Quit ##class(Security.Applications).Modify(..#APPLICATION, .props)
    Quit ##class(Security.Applications).Create(..#APPLICATION, .props)
}

}
