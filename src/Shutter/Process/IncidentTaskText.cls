/// The words of an incident's approval task (CONTRACTS 7.3). EnsLib.Workflow.TaskRequest.%Message holds 2,000 characters,
/// so the text lists as many whole chains as fit, says how many more there are, and points to the incident page for the
/// rest. The digest is never cut: it is what the approver pastes, and it binds every chain, listed here or not.
Class Shutter.Process.IncidentTaskText
{

/// EnsLib.Workflow.TaskRequest's %Message and TaskResponse's (MAXLEN read on 2026.2, 2026.3 and 2027.1).
Parameter MESSAGELIMIT = 2000;

/// How much of the catalogue's version the text carries; the plan records it whole.
Parameter CATALOGUEWORDS = 240;

/// How much of an approver's comment an outcome carries (Shutter.Store.Chain.Outcome holds 2,000 with its words round
/// it); the approval's own record keeps 2,000.
Parameter COMMENTWORDS = 500;

/// The task's message over the lines AskApproval made of the chains (one per chain, one per item, each starting with a
/// line break): every line when they fit, otherwise the first whole chains and what is left out.
ClassMethod Message(incident As Shutter.Store.Incident, count As %Integer, failures As %Integer, lines As %String) As %String
{
    Set nl = $CHAR(10)
    Set head = "Incident " _ incident.IncidentId _ ": " _ failures _ " failures to " _ incident.Receiver _ " since " _ incident.OpenedAt _ "."
    Set catalogue = incident.CatalogueVersion
    If $LENGTH(catalogue) > ..#CATALOGUEWORDS Set catalogue = $EXTRACT(catalogue, 1, ..#CATALOGUEWORDS) _ " (the rest in the plan)"
    Set tail = nl _ nl _ "Approving binds: resend these, in this order. Each one is rehearsed, gated and verified just before it goes; items after the first go at exactly the version the previous item's verified receipt reports; each operation goes only under the catalogue entry and outcome listed for it, and one whose fresh evidence reads differently stops its chain; the chain stops at the first surprise, and the rest comes back to you." _ nl
    Set tail = tail _ "Plan digest: " _ incident.PlanDigest _ nl _ "Catalogue " _ catalogue _ ", site profile v" _ incident.ProfileVersion _ ", gate policy " _ incident.PolicyVersion _ nl
    Set tail = tail _ "To approve from the Workflow inbox, paste the plan digest above into the PlanDigest field: an approval with no digest, or another one, binds nothing and rejects these chains."
    If ($LENGTH(head) + $LENGTH(lines) + $LENGTH(tail)) <= ..#MESSAGELIMIT Quit head _ lines _ tail
    // A long list: what is left out is said once, before what the approval binds.
    Set total = $LENGTH(lines, nl) - 1, chains = $LENGTH(lines, nl _ "Chain ") - 1, items = total - chains
    Set reserve = 260
    Set end = ..FirstLines(lines, ..#MESSAGELIMIT - $LENGTH(head) - $LENGTH(tail) - reserve, .shownChains, .shownItems)
    Set part = (shownChains = 0) && (end > 0), more = count - shownChains - part
    Set note = nl _ "Listed here: " _ $SELECT(shownChains: "the first " _ shownChains _ " of " _ count _ " chains", part: "part of the first chain", 1: "no chain") _ ", " _ shownItems _ " of " _ items _ " operations. "
    Set note = note _ "Approving binds " _ $SELECT(count = 1: "the whole chain", 1: "all " _ count _ " chains") _ ", listed here or not. "
    Set note = note _ $SELECT(more > 0: more _ " more chain" _ $SELECT(more = 1: "", 1: "s") _ " and every operation are", 1: "Every operation is") _ " on the incident page: /shutter/incidents/" _ incident.IncidentId
    Quit head _ $EXTRACT(lines, 1, end) _ note _ tail
}

/// Where the first lines that fit in room end, at the last whole chain when one fits, otherwise inside the first chain;
/// and how many chains (whole ones) and items that takes in.
ClassMethod FirstLines(lines As %String, room As %Integer, Output chains As %Integer, Output items As %Integer) As %Integer
{
    Set nl = $CHAR(10), at = 1, end = 0, seen = 0, kept = 0
    Set chains = 0, items = 0, wholeEnd = 0, wholeChains = 0, wholeItems = 0
    While at <= $LENGTH(lines) {
        Set next = $FIND(lines, nl, at + 1)
        Set stop = $SELECT(next: next - 2, 1: $LENGTH(lines))
        If stop > room Quit
        If $EXTRACT(lines, at + 1, at + 6) = "Chain " {
            If seen Set wholeEnd = end, wholeChains = seen, wholeItems = kept
            Set seen = seen + 1
        } Else {
            Set kept = kept + 1
        }
        Set end = stop, at = stop + 1
    }
    If at > $LENGTH(lines) Set wholeEnd = end, wholeChains = seen, wholeItems = kept
    If wholeChains Set chains = wholeChains, items = wholeItems Quit wholeEnd
    // Not even the first chain's items all fit: its line and the items that do, still counted as not whole.
    Set items = kept
    Quit end
}

/// What a person reads when no task could be raised: the incident, what did and did not happen, and what to do.
ClassMethod NotRaised(incidentId As %String, seq As %String, error As %String) As %String
{
    Set what = $SELECT(seq '= "": "chain " _ seq _ " of incident " _ incidentId, 1: "incident " _ incidentId)
    Quit "No approval task could be raised for " _ what _ ": nothing was released and no case failed, and the chains wait for a person. The error: " _ $EXTRACT(error, 1, 300) _ ". Shutter tries again every 5 minutes, so clear the cause (the Workflow item, its role, the Event Log) and the task follows; to give the incident up, abandon it."
}

/// A chain's Entries, which hold 200 characters: all of them, or the first and how many more ("E4,E4,+118"). Each item
/// keeps its own entry, in the store and in the plan.
ClassMethod ClipEntries(entries As %String) As %String
{
    If $LENGTH(entries) <= 200 Quit entries
    Set total = $LENGTH(entries, ","), head = "", n = 0
    For i = 1:1:total {
        Set e = $PIECE(entries, ",", i)
        Quit:(($LENGTH(head) + $LENGTH(e) + 8) > 200)
        Set head = head _ $SELECT(n: ",", 1: "") _ e, n = n + 1
    }
    Quit head _ ",+" _ (total - n)
}

}
