/// What the ward system needs outside its own tables: the <code>Wards_API</code> resource and role (the web
/// application <code>/wards/api</code> requires the resource), and the demo flag that allows a reset.
Class Wards.Installer
{

/// Creates the resource and the role when missing, and marks the instance as a demo when <var>demo</var> is true.
/// Safe to run again.
ClassMethod Install(demo As %Boolean = 1) As %Status
{
    Set sc = $$$OK
    Set namespace = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        If '##class(Security.Resources).Exists("Wards_API") {
            Set sc = ##class(Security.Resources).Create("Wards_API", "The synthetic ward system's REST API", "")
        }
        If $$$ISOK(sc), '##class(Security.Roles).Exists("Wards_API") {
            Set sc = ##class(Security.Roles).Create("Wards_API", "Calls the synthetic ward system's REST API", "Wards_API:U")
        }
        Set $NAMESPACE = namespace
        If $$$ISOK(sc), demo {
            Set ^Wards.Config("demo") = 1
        }
    } Catch ex {
        Set $NAMESPACE = namespace
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// <method>Install</method> for scripts that reach IRIS through SQL: "ok", or the error text.
ClassMethod InstallSql(demo As %Boolean = 1) As %String [ SqlProc ]
{
    Set sc = ..Install(demo)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

}
