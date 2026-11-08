/// Another visit's in-patient movement that the site profile shows instead of stopping (further_messages.in_patient_movement
/// show; Shutter.Util.FurtherMessages) goes on the plan for a person to read. Nothing reads it where a write goes with no
/// person: at an automatic tier, or under an incident's approval, whose task lists the chains and not these lines. So a case
/// whose snapshot shows one is asked of a person on its own (Shutter.Process.CaseWorkflow PolicyPath), and an incident's
/// chain with such an item leaves the shared approval for each case's own path (Shutter.Store.IncidentDetector Classify).
/// An out-patient or emergency attendance (why "shown") is not another visit's movement and is left as it was.
Class Shutter.Util.ShownVisit
{

/// Whether a snapshot's summary shows another visit's movement.
ClassMethod In(summary As %DynamicObject) As %Boolean
{
    If '$ISOBJECT(summary) Quit 0
    Set found = summary.%Get("further_messages")
    If '$ISOBJECT(found) Quit 0
    Set shows = found.%Get("shows")
    If '$ISOBJECT(shows) || 'shows.%IsA("%Library.DynamicArray") Quit 0
    Set si = shows.%GetIterator()
    While si.%GetNext(, .item) {
        If $ISOBJECT(item) && (##class(Shutter.Util.Json).Str(item, "why") = "other_visit") Return 1
    }
    Quit 0
}

/// Whether the case's current snapshot shows another visit's movement.
ClassMethod OfCase(case As Shutter.Store.Case) As %Boolean
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit 0
    Quit ..In(case.CurrentSnapshot.SummaryObject())
}

/// The first case of the chain, in order, whose snapshot shows another visit's movement, or "".
ClassMethod InChain(chain As Shutter.Store.Chain) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.ChainItem WHERE Chain = ? ORDER BY Position", chain.%Id())
    While rs.%Next() {
        Set it = ##class(Shutter.Store.ChainItem).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(it)
        If ..OfCase(it.Case) Return it.Case.CaseId
    }
    Quit ""
}

}
