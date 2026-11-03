/// What the downstream system needs outside its own tables: the <code>Downstream_API</code> resource and role (the
/// web application <code>/downstream/api</code> requires the resource), the <code>Downstream_Admin</code> resource
/// (the demo controls in <class>Downstream.API</class> require it too, and no role of the production's holds it), and
/// the demo flag that allows a reset.
Class Downstream.Installer
{

/// Creates the resources and the role when missing, removes the names from before the rename (the
/// <code>Wards_API</code> role and resource) when they exist, and marks the instance as a demo when <var>demo</var>
/// is true, and builds the bed index. Safe to run again.
ClassMethod Install(demo As %Boolean = 1) As %Status
{
    Set sc = $$$OK
    Set namespace = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If '##class(Security.Resources).Exists("Downstream_API") {
            Set sc = ##class(Security.Resources).Create("Downstream_API", "The demo bed-management system's REST API (the downstream system)", "")
        }
        // The controls' resource (faults, reset, the capability switch) is granted to no role here: an administrator
        // holds it through %All, and a site gives a role of its own both resources when a person is to use them.
        If $$$ISOK(sc), '##class(Security.Resources).Exists("Downstream_Admin") {
            Set sc = ##class(Security.Resources).Create("Downstream_Admin", "The demo bed-management system's controls: faults, reset and the capability switch", "")
        }
        If $$$ISOK(sc), '##class(Security.Roles).Exists("Downstream_API") {
            Set sc = ##class(Security.Roles).Create("Downstream_API", "Calls the downstream system's REST API", "Downstream_API:U")
        }
        If $$$ISOK(sc) Set sc = ..RemoveOldNames()
        Set $NAMESPACE = namespace
        If $$$ISOK(sc), demo {
            Set ^Downstream.Config("demo") = 1
        }
        // The bed index came after the table: encounters from before it are indexed once (small, and safe to repeat)
        If $$$ISOK(sc) Set sc = ##class(Downstream.Encounter).%BuildIndices($LISTBUILD("WardBedIdx"))
    } Catch ex {
        Set $NAMESPACE = namespace
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The Wards_API role, taken from every user that holds it first, and then its resource. Quiet when absent. Runs in
/// %SYS.
ClassMethod RemoveOldNames() As %Status [ Private ]
{
    Set sc = $$$OK
    If ##class(Security.Roles).Exists("Wards_API") {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Security.Users")
        While rs.%Next() {
            Set user = rs.%Get("Name")
            Kill props
            Continue:$$$ISERR(##class(Security.Users).Get(user, .props))
            Set roles = $LISTFROMSTRING($GET(props("Roles")), ","), at = $LISTFIND(roles, "Wards_API")
            Continue:'at
            Kill props
            Set props("Roles") = $LISTTOSTRING($LIST(roles, 1, at - 1) _ $LIST(roles, at + 1, *), ",")
            Set sc = ##class(Security.Users).Modify(user, .props)
            Quit:$$$ISERR(sc)
        }
        Quit:$$$ISERR(sc) sc
        Set sc = ##class(Security.Roles).Delete("Wards_API")
        Quit:$$$ISERR(sc) sc
    }
    If ##class(Security.Resources).Exists("Wards_API") Set sc = ##class(Security.Resources).Delete("Wards_API")
    Quit sc
}

/// <method>Install</method> for scripts that reach IRIS through SQL: "ok", or the error text.
ClassMethod InstallSql(demo As %Boolean = 1) As %String [ SqlProc ]
{
    Set sc = ..Install(demo)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

}
