/// S26's steps around the hold for a schema not loaded here (CONTRACTS 4.3 and 12): "prevent failures" on for the one run,
/// and the site's schema forgotten and imported. The stored site profile is never touched, so playing the scenario moves no
/// profile version and voids no approval.
Class Shutter.Scenarios.SiteSchema
{

/// On for this run: the setting's cached value, which every store of the profile and the runner's reset clear. Off clears
/// it, so the next read goes back to what the profile says.
ClassMethod PreventFailures(on As %Boolean)
{
    If on {
        Set ^Shutter.Config("preventFailures") = 1
    } Else {
        Kill ^Shutter.Config("preventFailures")
    }
}

/// Removes a site's schema category, never a standard one, so the next read finds it missing; and a case a cut-off run left
/// held for it stops waiting, as its receiver has been reset since.
ClassMethod Forget(category As %String)
{
    Set list = ##class(Shutter.Util.Schemas).Categories(), li = list.%GetIterator()
    While li.%GetNext(, .c) { If (c.category = category) && c.standard Return }
    Kill ^EnsHL7.Schema(category), ^EnsHL7.Description(category), ^Shutter.Config("schemaNamed", category)
    &sql(UPDATE Shutter_Store."Case" SET HeldSchema = NULL WHERE HeldSchema = :category)
    Do ##class(Shutter.Util.Schemas).Changed()
}

/// Imports a schema file through Shutter's own import. Returns an empty string, or what went wrong.
ClassMethod Import(path As %String) As %String
{
    Set sc = ##class(Shutter.Util.Schemas).Import(path, .category)
    Quit $SELECT($$$ISOK(sc): "", 1: $SYSTEM.Status.GetErrorText(sc))
}

}
