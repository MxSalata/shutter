/// Another visit's in-patient movement that a read after the snapshot finds and the snapshot did not show (CONTRACTS 6.5). A
/// site whose profile says show (further_messages.in_patient_movement) lets such a movement through on the plan, so a person
/// approves the plan with it in view; a movement that reached the engine after the snapshot was never in view. The gate at
/// dispatch and the connector compare what they read with the snapshot's further messages, by control id and visit, and a
/// row the snapshot did not show doesn't pass: the gate answers unknown (FURTHER_MOVEMENT_NEW), so the workflow collects the
/// evidence again, the new snapshot shows the row, its material digest changes and the approval is void. Pure, so a test
/// runs it on rows alone.
Class Shutter.Util.FurtherNew
{

/// The rows of fresh's shows, of another visit's movement (why other_visit), that prior's shows don't hold by control id
/// and visit. fresh and prior are Shutter.Util.FurtherMessages.Find's shape; a prior that isn't an object holds nothing.
ClassMethod Rows(fresh, prior) As %DynamicArray
{
    Set out = [], json = "Shutter.Util.Json"
    If '$ISOBJECT(fresh) Quit out
    Set shows = fresh.%Get("shows")
    If '$ISOBJECT(shows) Quit out
    Set before = $SELECT($ISOBJECT(prior): prior.%Get("shows"), 1: "")
    If $ISOBJECT(before) {
        Set bi = before.%GetIterator()
        While bi.%GetNext(, .b) {
            Continue:'$ISOBJECT(b)
            Set held(..Key(b)) = ""
        }
    }
    Set si = shows.%GetIterator()
    While si.%GetNext(, .r) {
        Continue:'$ISOBJECT(r)
        Continue:($CLASSMETHOD(json, "Str", r, "why") '= "other_visit")
        Continue:$DATA(held(..Key(r)))
        Do out.%Push(r)
    }
    Quit out
}

/// A row's control id and visit; a row with no control id adds its event and time, so two such rows on one visit differ.
ClassMethod Key(r As %DynamicObject) As %String [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set control = $CLASSMETHOD(json, "Str", r, "control_id")
    Set k = "c" _ control _ "|v" _ $CLASSMETHOD(json, "Str", r, "visit_number")
    If control = "" Set k = k _ "|e" _ $CLASSMETHOD(json, "Str", r, "event") _ "|t" _ $CLASSMETHOD(json, "Str", r, "event_time")
    Quit k
}

/// The snapshot's further messages for a case: what its plan showed, or "" when it has no snapshot.
ClassMethod Prior(case As Shutter.Store.Case) As %DynamicObject
{
    If '$ISOBJECT(case) Quit ""
    Set snap = case.CurrentSnapshot
    If '$ISOBJECT(snap) Quit ""
    Set summary = snap.SummaryObject()
    Quit $SELECT($ISOBJECT(summary): summary.%Get("further_messages"), 1: "")
}

/// For a person: the first new row, beside the case's own visit, and how many more; "" when there is none.
ClassMethod Describe(case As Shutter.Store.Case, fresh, prior) As %String
{
    Set rows = ..Rows(fresh, prior)
    If rows.%Size() = 0 Quit ""
    Quit ##class(Shutter.Util.FurtherMessages).Line(case, rows.%Get(0)) _ $SELECT(rows.%Size() > 1: ", and " _ (rows.%Size() - 1) _ " more", 1: "") _ ". It reached the engine after the plan was made, so the plan did not show it"
}

}
