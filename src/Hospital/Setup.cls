/// Installs the demo hospital: a production of its own in the HOSPITAL namespace, not Shutter's, whose failed
/// deliveries reach Shutter through the forwarder (docs/CONTRACTS.md, section 11). Runs in the HOSPITAL namespace
/// after the iris-shutter module is loaded into Shutter's: the classes come through the namespace's package mappings
/// (Installer.cls), so nothing is loaded or compiled here. Safe to run again.
Class Hospital.Setup Extends %RegisteredObject
{

/// The folders, the credentials, the feed's time zone, the default settings and the production. shutterNs is the
/// namespace Shutter runs in: the feed's time zone is copied from its site profile, so that both read the same HL7
/// timestamp the same way and build the same operation key, and the hospital's folders are recorded there for the
/// scenario runner. Returns "ok" or the error text; callable over SQL (SELECT Hospital.Setup_Install('SHUTTER')).
ClassMethod Install(shutterNs As %String = "SHUTTER") As %String [ SqlProc ]
{
    Set sc = ..InstallStatus(shutterNs)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

ClassMethod InstallStatus(shutterNs As %String = "SHUTTER") As %Status
{
    Set sc = $$$OK
    Try {
        // SQL hands an empty string over as $CHAR(0).
        If ($GET(shutterNs) = "") || (shutterNs = $CHAR(0)) Set shutterNs = "SHUTTER"
        Set shutterNs = $ZCONVERT(shutterNs, "U")
        // Run in the hospital's namespace only: in Shutter's it would make Hospital.Production the production there.
        If $NAMESPACE = shutterNs Set sc = $$$ERROR($$$GeneralError, "Hospital.Setup runs in the hospital's namespace, not in Shutter's (" _ shutterNs _ ")") Quit
        Set ^Hospital.Config("shutterNamespace") = shutterNs
        Set ^Hospital.Config("installedAt") = ##class(Shutter.Util.Time).NowUTC()
        // The live hospital (v1.34): the install is told so (SHUTTER_LIVE=1), and the Live PAS item then runs.
        Set ^Hospital.Config("live") = ($SYSTEM.Util.GetEnviron("SHUTTER_LIVE") = "1")
        Set sc = ..CreateFolders() Quit:$$$ISERR(sc)
        Set sc = ..CreateCredentials() Quit:$$$ISERR(sc)
        // Shutter.Util.Time reads the zone from the site profile's cache in this namespace; the hospital has no profile
        // of its own, so Shutter's zone is copied in. A zone changed in Shutter's profile later needs this install again.
        Set zone = ..ShutterFeedTimeZone(shutterNs)
        Set ^Shutter.Config("feedZone") = $SELECT(zone '= "": zone, 1: "UTC")
        // "Prevent failures" (v1.34): PAS In validates and hands a refused message to the forwarder when Shutter's profile says so.
        Do ..PreventFailures(..ShutterPreventFailures(shutterNs))
        Set sc = ..ApplyDefaultSettings() Quit:$$$ISERR(sc)
        Do ..RecordInShutter(shutterNs)
        Set sc = ..RefreshShutterSecurity(shutterNs) Quit:$$$ISERR(sc)
        Set sc = ..StartProduction() Quit:$$$ISERR(sc)
        If $GET(^Hospital.Config("live")) Set sc = ##class(Ens.Director).EnableConfigItem("Live PAS", 1, 1)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Turns the live hospital on or off without an install (CONTRACTS 4.4, v1.34): the flag the player checks, and the Live
/// PAS item enabled or disabled in the running production. Returns "ok" or the error text; callable over SQL in the
/// hospital's namespace (SELECT Hospital.Setup_SetLive(1)). An install sets the flag again from SHUTTER_LIVE.
ClassMethod SetLive(on As %Boolean = 1) As %String [ SqlProc ]
{
    Set on = ''on
    Set ^Hospital.Config("live") = on
    // The running production is updated; one that is not running (an install while the image is built, a start still under
    // way) gets the item's state in its definition, and starts with it.
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Set running = $$$ISOK(sc) && (state = 1) && (name = "Hospital.Production")
    // Already as asked: EnableConfigItem would answer "already enabled" as an error.
    Set enabled = ""
    &sql(SELECT Enabled INTO :enabled FROM Ens_Config.Item WHERE Production = 'Hospital.Production' AND Name = 'Live PAS')
    If (SQLCODE = 0) && (''enabled = on) Quit "ok (already " _ $SELECT(on: "on", 1: "off") _ ")"
    Set sc = ##class(Ens.Director).EnableConfigItem("Live PAS", on, running)
    Quit $SELECT($$$ISOK(sc): "ok" _ $SELECT(running: "", 1: " (saved in the definition; the production is not running)"), 1: $SYSTEM.Status.GetErrorText(sc))
}

/// The inbound, archive and work folders under the manager directory, beside Shutter's own (the same volume).
ClassMethod CreateFolders() As %Status
{
    Set sc = $$$OK
    Set base = ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ "shutter/hospital")
    For sub = "in", "archive", "work" {
        Set dir = base _ sub _ "/"
        If '##class(%File).DirectoryExists(dir) && '##class(%File).CreateDirectoryChain(dir) {
            Set sc = $$$ERROR($$$GeneralError, "Cannot create " _ dir)
            Quit
        }
        Set ^Hospital.Config("dir", sub) = dir
    }
    Quit sc
}

/// The production's two credentials, in this namespace: DownstreamAPI for the ward system (the demo receiver's
/// client user, which Shutter's install creates) and ShutterIntake for the forwarder (the user forwarder, with the
/// Shutter_Forwarder role, created here when Shutter's install did not). Both take the demo password
/// (SHUTTER_DEMO_PASSWORD, else shutter).
ClassMethod CreateCredentials() As %Status
{
    Set sc = $$$OK
    Set password = $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_PASSWORD")
    If password = "" Set password = "shutter"
    Set sc = ..EnsureForwarderUser("forwarder", password)
    Quit:$$$ISERR(sc) sc
    Set sc = ##class(Ens.Config.Credentials).SetCredential("DownstreamAPI", "downstream-client", password, 1)
    Quit:$$$ISERR(sc) sc
    Quit ##class(Ens.Config.Credentials).SetCredential("ShutterIntake", "forwarder", password, 1)
}

/// The forwarder's user, in %SYS: created with the Shutter_Forwarder role when missing; an existing one gets the role
/// when it lacks it. The role is Shutter's (its install creates it); without it the intake answers 403.
ClassMethod EnsureForwarderUser(user As %String, password As %String) As %Status [ Private ]
{
    Set sc = $$$OK
    Set ns = $NAMESPACE
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set roles = $SELECT(##class(Security.Roles).Exists("Shutter_Forwarder"): "Shutter_Forwarder", 1: "")
        If '##class(Security.Users).Exists(user) {
            Set sc = ##class(Security.Users).Create(user, roles, password, "The demo hospital's forwarder to Shutter's intake", ns, "", "", 0, 1, "Used by the Shutter Forwarder item of Hospital.Production")
        } ElseIf roles '= "" {
            Do ##class(Security.Users).AddRoles(user, roles)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The feed's time zone as Shutter's namespace reads it; "" when that namespace or its profile cannot be read.
/// The demo hospital's side of "prevent failures" (CONTRACTS 11, v1.34): the flag ^Hospital.Config("preventFailures"), which
/// PAS to Downstream reads for every message. On, a message whose schema category is not loaded in this namespace is not
/// mapped or delivered: it goes to the Shutter Forwarder as a held message, and Shutter releases the case once the schema is
/// imported here. Shutter's profile store calls this when the setting changes, and the install applies the profile's value;
/// by hand: SELECT Hospital.Setup_PreventFailures(1) in the hospital's namespace. (The HL7 service's own Validation is not a
/// setting on this build, and only a routing engine has a BadMessageHandler: a site with one points it at the forwarder.)
ClassMethod PreventFailures(on As %Boolean = 1) As %String [ SqlProc ]
{
    Set ^Hospital.Config("preventFailures") = ''on
    Quit "ok"
}

/// Shutter's "prevent failures" setting, read in its namespace; off when it cannot be read.
ClassMethod ShutterPreventFailures(shutterNs As %String) As %Boolean [ Private ]
{
    Set on = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = shutterNs
        Set on = ##class(Shutter.Store.SiteProfile).PreventFailures()
    } Catch ex {
        Set on = 0
    }
    Quit ''on
}

ClassMethod ShutterFeedTimeZone(shutterNs As %String) As %String [ Private ]
{
    Set zone = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = shutterNs
        Set zone = ##class(Shutter.Store.SiteProfile).FeedTimeZone()
    } Catch ex {
        Set zone = ""
    }
    Quit zone
}

/// Shutter's roles brought up to date now that this namespace is recorded as the watched hospital: its operator and
/// approver read the hospital's databases from now on (the review targets and their state), and the SQL grants are
/// renewed with the roles. Shutter.Setup is not mapped into this namespace, so it is called in Shutter's.
ClassMethod RefreshShutterSecurity(shutterNs As %String) As %Status [ Private ]
{
    Set sc = $$$OK
    Try {
        New $NAMESPACE
        Set $NAMESPACE = shutterNs
        Set sc = $CLASSMETHOD("Shutter.Setup", "RefreshSecurity", shutterNs)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Where the hospital's feed is, written into Shutter's configuration for the scenario runner: hospitalIn and
/// hospitalArchive (the folders) and hospitalNamespace. Quiet when Shutter's namespace is not there.
ClassMethod RecordInShutter(shutterNs As %String) [ Private ]
{
    Set hospital = $NAMESPACE
    Set inbound = $GET(^Hospital.Config("dir", "in")), archive = $GET(^Hospital.Config("dir", "archive"))
    Try {
        New $NAMESPACE
        Set $NAMESPACE = shutterNs
        Set ^Shutter.Config("hospitalIn") = inbound
        Set ^Shutter.Config("hospitalArchive") = archive
        Set ^Shutter.Config("hospitalNamespace") = hospital
    } Catch ex {
    }
    Quit
}

/// System default settings for the production: the folders and the two addresses on this instance (Shutter's intake
/// and the demo receiver both answer on the instance's own web port), so the production definition carries none.
ClassMethod ApplyDefaultSettings() As %Status
{
    Set sc = $$$OK
    Set values("PAS In", "FilePath") = $GET(^Hospital.Config("dir", "in"))
    Set values("PAS In", "ArchivePath") = $GET(^Hospital.Config("dir", "archive"))
    Set values("PAS In", "WorkPath") = $GET(^Hospital.Config("dir", "work"))
    For item = "Downstream Out", "Shutter Forwarder" {
        Set values(item, "HTTPServer") = $GET(^Hospital.Config("httpServer"), "127.0.0.1")
        Set values(item, "HTTPPort") = $GET(^Hospital.Config("httpPort"), 52773)
    }
    Set item = ""
    For {
        Set item = $ORDER(values(item))
        Quit:(item="")
        Set name = ""
        For {
            Set name = $ORDER(values(item, name), 1, value)
            Quit:(name="")
            Continue:(value="")
            Set id = "Hospital.Production||" _ item _ "||*||" _ name
            Set d = ##class(Ens.Config.DefaultSettings).%OpenId(id)
            If '$ISOBJECT(d) {
                Set d = ##class(Ens.Config.DefaultSettings).%New()
                Set d.ProductionName = "Hospital.Production", d.ItemName = item, d.HostClassName = "*", d.SettingName = name
            }
            Set d.SettingValue = value
            Set d.Description = "Set by Hospital.Setup"
            Set sc = d.%Save()
            Quit:$$$ISERR(sc)
        }
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

/// Make Hospital.Production this namespace's production and start it, as Shutter.Setup does for Shutter's: while an
/// image is built (SHUTTER_BUILD=1) the instance stops right after, so the production starts with the container
/// instead and nothing is started here.
ClassMethod StartProduction() As %Status
{
    Set sc = $$$OK
    Set prod = "Hospital.Production"
    If '##class(%Dictionary.CompiledClass).%ExistsId(prod) Quit $$$ERROR($$$GeneralError, prod _ " is not visible in " _ $NAMESPACE _ ": is the Hospital package mapped from Shutter's namespace?")
    Try {
        // The class is compiled in Shutter's namespace and mapped here, and this namespace keeps its own copy of the
        // production definition, written by the class's projection when it is compiled here: so it is compiled here on
        // every install, and an upgrade's new items (the Live PAS of v1.34) reach the definition before UpdateProduction.
        Set sc = $SYSTEM.OBJ.Compile(prod, "ck-d")
        Quit:$$$ISERR(sc)
        If '##class(Ens.Config.Production).%ExistsId(prod) Set sc = $$$ERROR($$$GeneralError, prod _ " has no production definition in " _ $NAMESPACE _ " after compiling") Quit
        Do ##class(Ens.Director).SetAutoStart(prod)
        If $SYSTEM.Util.GetEnviron("SHUTTER_BUILD") = "1" Quit
        Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
        Quit:$$$ISERR(sc)
        If state = 1 {
            If name '= prod {
                Set sc = ##class(Ens.Director).StopProduction(30, 0)
                Quit:$$$ISERR(sc)
                Set sc = ##class(Ens.Director).StartProduction(prod)
            } Else {
                Set sc = ##class(Ens.Director).UpdateProduction()
            }
        } Else {
            Set sc = ##class(Ens.Director).StartProduction(prod)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

}
