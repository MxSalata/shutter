/// The test FHIR server's storage: every version of every resource, kept for good until <method>Reset</method>, in one
/// global, <code>^FHIRFacade.Data</code>.
/// <ul>
/// <li><code>("res", type, id)</code> = <code>$LISTBUILD(current version id, deleted, versions)</code>;</li>
/// <li><code>("res", type, id, "n", n)</code> = <code>$LISTBUILD(version id, method, lastModified)</code> for the n-th
/// version in the order it was written, and <code>("res", type, id, "n", n, "t")</code> its stored text (empty for a
/// delete);</li>
/// <li><code>("res", type, id, "v", version id)</code> = n;</li>
/// <li><code>("order", type, seq)</code> = id, in the order ids were first written (the order a search returns);</li>
/// <li><code>("query", queryId)</code> = <code>$LISTBUILD(type, total, page size, query as sent)</code> and
/// <code>("query", queryId, i)</code> = id: a search's result, kept so its later pages are the same list;</li>
/// <li><code>("clock")</code> = the instant tests fix the clock at;</li>
/// <li><code>("fault")</code> = <code>$LISTBUILD(modes as a comma list, times left)</code>: the fault a test set, gone
/// once it has fired its times;</li>
/// <li><code>("stats", name)</code> = a counter (<code>puts_received</code>, <code>puts_refused</code>).</li>
/// </ul>
/// Version ids are decimal strings from "1", plus one per update and per delete, as IRIS for Health's server gives them.
/// Callers compare them as strings and never as numbers.
Class FHIRFacade.Store
{

/// Whether type/id has ever been written; its current version id and whether that version is a delete.
ClassMethod Current(type As %String, id As %String, Output vid As %String, Output deleted As %Boolean) As %Boolean
{
    Set vid = "", deleted = 0
    Set node = $GET(^FHIRFacade.Data("res", type, id))
    Quit:node="" 0
    Set vid = $LISTGET(node, 1), deleted = +$LISTGET(node, 2)
    Quit 1
}

/// The version id the next write of type/id takes.
ClassMethod NextVid(type As %String, id As %String) As %String
{
    Quit (+$LISTGET($GET(^FHIRFacade.Data("res", type, id)), 3) + 1) _ ""
}

/// Writes one version: <var>method</var> is PUT or DELETE, <var>text</var> the stored JSON (empty for a delete).
/// The caller holds the lock of <method>Lock</method>.
ClassMethod Append(type As %String, id As %String, vid As %String, method As %String, text As %String, lastModified As %String)
{
    Set node = $GET(^FHIRFacade.Data("res", type, id))
    If node = "" {
        Set seq = $INCREMENT(^FHIRFacade.Data("seq"))
        Set ^FHIRFacade.Data("order", type, seq) = id
    }
    Set n = +$LISTGET(node, 3) + 1
    Set ^FHIRFacade.Data("res", type, id, "n", n) = $LISTBUILD(vid, method, lastModified)
    Set ^FHIRFacade.Data("res", type, id, "n", n, "t") = text
    Set ^FHIRFacade.Data("res", type, id, "v", vid) = n
    Set ^FHIRFacade.Data("res", type, id) = $LISTBUILD(vid, (method = "DELETE"), n)
}

/// One version by its id: whether it exists, its method, lastModified and stored text.
ClassMethod Version(type As %String, id As %String, vid As %String, Output method As %String, Output lastModified As %String, Output text As %String) As %Boolean
{
    Set method = "", lastModified = "", text = ""
    Quit:vid="" 0
    Set n = $GET(^FHIRFacade.Data("res", type, id, "v", vid))
    Quit:n="" 0
    Quit ..Nth(type, id, n, , .method, .lastModified, .text)
}

/// How many versions type/id has.
ClassMethod Count(type As %String, id As %String) As %Integer
{
    Quit +$LISTGET($GET(^FHIRFacade.Data("res", type, id)), 3)
}

/// The n-th version written, from 1.
ClassMethod Nth(type As %String, id As %String, n As %Integer, Output vid As %String, Output method As %String, Output lastModified As %String, Output text As %String) As %Boolean
{
    Set vid = "", method = "", lastModified = "", text = ""
    Set node = $GET(^FHIRFacade.Data("res", type, id, "n", n))
    Quit:node="" 0
    Set vid = $LISTGET(node, 1), method = $LISTGET(node, 2), lastModified = $LISTGET(node, 3)
    Set text = $GET(^FHIRFacade.Data("res", type, id, "n", n, "t"))
    Quit 1
}

/// The ids of a type in the order they were first written.
ClassMethod Ids(type As %String) As %DynamicArray
{
    Set ids = [], seq = ""
    For {
        Set seq = $ORDER(^FHIRFacade.Data("order", type, seq), 1, id)
        Quit:seq=""
        Do ids.%Push(id)
    }
    Quit ids
}

/// Keeps a search's ids for its later pages; returns the query id.
ClassMethod SaveQuery(type As %String, ids As %DynamicArray, pageSize As %Integer, query As %String) As %String
{
    Set qid = $ZCONVERT($SYSTEM.Util.CreateGUID(), "L")
    Set ^FHIRFacade.Data("query", qid) = $LISTBUILD(type, ids.%Size(), pageSize, query)
    For i = 0:1:ids.%Size() - 1 {
        Set ^FHIRFacade.Data("query", qid, i + 1) = ids.%Get(i)
    }
    Quit qid
}

/// A kept search: whether it exists, its type, page size and ids.
ClassMethod Query(qid As %String, Output type As %String, Output pageSize As %Integer, Output ids As %DynamicArray) As %Boolean
{
    Set type = "", pageSize = 0, ids = []
    Quit:qid="" 0
    Set node = $GET(^FHIRFacade.Data("query", qid))
    Quit:node="" 0
    Set type = $LISTGET(node, 1), pageSize = $LISTGET(node, 3)
    For i = 1:1:$LISTGET(node, 2) {
        Do ids.%Push($GET(^FHIRFacade.Data("query", qid, i)))
    }
    Quit 1
}

/// Takes the lock on one resource, for a read of its current version and the write that depends on it.
ClassMethod Lock(type As %String, id As %String) As %Boolean
{
    Lock +^FHIRFacade.Data("res", type, id):10
    Quit $TEST
}

ClassMethod Unlock(type As %String, id As %String)
{
    Lock -^FHIRFacade.Data("res", type, id)
}

/// Every resource, version and kept search gone, and with them the fault and the counters; version ids start again
/// from "1". The clock is kept. The whole global is locked for it, so a reset waits for a write that is under way (up
/// to 10 seconds) and no write starts in the middle of one; 0, with nothing cleared, when the lock was not given.
ClassMethod Reset() As %Boolean
{
    Lock +^FHIRFacade.Data:10
    Quit:'$TEST 0
    Set clock = $GET(^FHIRFacade.Data("clock"))
    Kill ^FHIRFacade.Data
    Set:clock'="" ^FHIRFacade.Data("clock") = clock
    Lock -^FHIRFacade.Data
    Quit 1
}

/// Sets the fault: <var>modes</var> a comma list, fired <var>times</var> times. An empty list or no times clears it.
ClassMethod SetFault(modes As %String, times As %Integer)
{
    Lock +^FHIRFacade.Data("fault"):10
    If (modes = "") || (times < 1) {
        Kill ^FHIRFacade.Data("fault")
    } Else {
        Set ^FHIRFacade.Data("fault") = $LISTBUILD(modes, times \ 1)
    }
    Lock -^FHIRFacade.Data("fault")
}

/// The fault as it stands: its modes and how many times it still fires.
ClassMethod Fault(Output modes As %String, Output left As %Integer)
{
    Set node = $GET(^FHIRFacade.Data("fault"))
    Set modes = $LISTGET(node, 1), left = +$LISTGET(node, 2)
}

/// Fires the fault once: its modes, or "" when none is set. The last firing clears it. Two requests never take the
/// same firing.
ClassMethod TakeFault() As %String
{
    Quit:'$DATA(^FHIRFacade.Data("fault")) ""
    Lock +^FHIRFacade.Data("fault"):10
    Quit:'$TEST ""
    Do ..Fault(.modes, .left)
    If left > 1 {
        Set ^FHIRFacade.Data("fault") = $LISTBUILD(modes, left - 1)
    } Else {
        Kill ^FHIRFacade.Data("fault")
        Set:left<1 modes = ""
    }
    Lock -^FHIRFacade.Data("fault")
    Quit modes
}

/// Adds one to a counter.
ClassMethod Tally(name As %String)
{
    Do $INCREMENT(^FHIRFacade.Data("stats", name))
}

/// A counter's value, 0 when nothing was counted.
ClassMethod Tallied(name As %String) As %Integer
{
    Quit +$GET(^FHIRFacade.Data("stats", name))
}

/// The instant the clock is fixed at, or empty for the real time.
ClassMethod Clock() As %String
{
    Quit $GET(^FHIRFacade.Data("clock"))
}

ClassMethod SetClock(instant As %String)
{
    If instant = "" {
        Kill ^FHIRFacade.Data("clock")
    } Else {
        Set ^FHIRFacade.Data("clock") = instant
    }
}

}
