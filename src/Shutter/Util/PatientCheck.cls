/// The patient check before a message is sent again: is anything newer for its patients already at the receiver, or
/// still open with Shutter? Every PID in the message is found by name (an ORU can carry several patients), and every
/// PID-3 repetition is a key: identifier and authority, the authority from PID-3.4.1 then PID-3.4, as
/// Shutter.Util.OperationKey reads it. A key with a blank authority is unknown, and holds that patient.
///
/// The read: in the source namespace, the item's headers newer than the origin that are Queued, Delivered or Completed,
/// whose body shares a key. Only this run's own clones are left out, known by the ledger's NewHeaderId rows
/// (Shutter.Store.ResendRecord); a hand resend's clone reads the same in the engine and counts, which is right: someone
/// else is resending. Then Shutter's unresolved cases for the patient at this receiver: every state but resolved, since
/// blocked, escalated and failed still need a person; the candidate's own case and the cases of the same approved set are
/// left out. A hold on any patient of a message holds the whole message, since Shutter never splits or edits one. More
/// than CAP newer headers holds the patient, and says so.
///
/// Merges (A40, A47) are not read: newer activity under a changed identifier may be missed, and the check does not
/// establish result ownership across merges, unmerges or identifier corrections.
Class Shutter.Util.PatientCheck [ Abstract ]
{

/// The most newer headers read; one more holds the patient.
Parameter CAP = 2000;

/// The check for the stored message of <var>originHeaderId</var> to <var>item</var> in <var>ns</var>, at
/// <var>receiver</var> (a case's Receiver). <var>exclude</var> is a $LIST of case ids left out: the candidate's own and
/// the approved set's. {"hold", "patients": [{"pid", "keys": [{"identifier", "authority"}], "hold", "why", "newer",
/// "cases"}], "why", "read_ms", "headers_read"}.
ClassMethod Check(ns As %String, item As %String, originHeaderId As %String, receiver As %String, exclude As %List = "") As %DynamicObject
{
    Set t0 = $ZHOROLOG
    Set out = {"hold": false, "patients": [], "why": "", "read_ms": 0, "headers_read": 0}
    Set msg = ..Body(ns, originHeaderId)
    If '$ISOBJECT(msg) {
        Do out.%Set("hold", 1, "boolean")
        Set out.why = "the stored message could not be read"
        Quit out
    }
    Set out.patients = ..Patients(msg)
    If out.patients.%Size() = 0 {
        Do out.%Set("hold", 1, "boolean")
        Set out.why = "the message holds no PID, so its patient cannot be checked"
        Quit out
    }
    Set newer = ..Newer(ns, item, originHeaderId, .why)
    Set out."headers_read" = $LISTLENGTH(newer)
    Set iter = out.patients.%GetIterator()
    While iter.%GetNext(, .p) {
        Continue:p.hold
        If why '= "" {
            Do p.%Set("hold", 1, "boolean")
            Set p.why = why
            Continue
        }
        Set hit = ..FirstHit(ns, newer, p.keys)
        If hit '= "" {
            Do p.%Set("hold", 1, "boolean")
            Set p.newer = hit
            Set p.why = "a newer message for " _ ..KeyWords(hit.key) _ " reached the receiver at " _ hit.time _ " (control id " _ hit.control _ ")"
            Continue
        }
        Set cases = ..OpenCases(p.keys, receiver, exclude)
        If cases.%Size() {
            Do p.%Set("hold", 1, "boolean")
            Set p.cases = cases
            Set p.why = "Shutter still has an unresolved case for this patient at this receiver: " _ ..CaseWords(cases)
        }
    }
    Set held = 0
    Set iter = out.patients.%GetIterator()
    While iter.%GetNext(, .p) { Set:p.hold held = held + 1 }
    If held {
        Do out.%Set("hold", 1, "boolean")
        Set out.why = $SELECT(out.patients.%Size() > 1: held _ " of the message's " _ out.patients.%Size() _ " patients held, so the whole message waits: Shutter never splits or edits a message", 1: out.patients.%Get(0).why)
    }
    Set out."read_ms" = $NUMBER(($ZHOROLOG - t0) * 1000, 0)
    Quit out
}

/// Every PID by segment name, with every PID-3 repetition as a key. A patient with a key whose authority is blank is held
/// at once: an identifier with no authority cannot be told apart from another site's.
ClassMethod Patients(msg) As %DynamicArray
{
    Set list = [], n = 0
    For i = 1:1:msg.SegCount {
        Set seg = msg.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        Continue:seg.Name'="PID"
        Set n = n + 1
        Set p = {"pid": (n), "segment": (i), "keys": [], "hold": false, "why": "", "newer": null, "cases": []}
        Do p.%Set("pid", n, "number")
        Set reps = seg.GetValueAt("3(*)"), blank = 0
        For r = 1:1:reps {
            Set id = seg.GetValueAt("3(" _ r _ ").1")
            Continue:id=""
            Set authority = seg.GetValueAt("3(" _ r _ ").4.1")
            Set:authority="" authority = seg.GetValueAt("3(" _ r _ ").4")
            Set:authority="" blank = 1
            Do p.keys.%Push({"identifier": (id), "authority": (authority)})
        }
        If p.keys.%Size() = 0 {
            Do p.%Set("hold", 1, "boolean")
            Set p.why = "patient " _ n _ " of the message has no identifier in PID-3"
        } ElseIf blank {
            Do p.%Set("hold", 1, "boolean")
            Set p.why = "an identifier of patient " _ n _ " has no assigning authority, so it is unknown which patient it is"
        }
        Do list.%Push(p)
    }
    Quit list
}

/// Whether two key lists share a key (identifier and authority, both exactly).
ClassMethod Shares(a As %DynamicArray, b As %DynamicArray, Output key As %DynamicObject) As %Boolean
{
    Set key = ""
    Set ia = a.%GetIterator()
    While ia.%GetNext(, .x) {
        Continue:x.authority=""
        Set ib = b.%GetIterator()
        While ib.%GetNext(, .y) {
            If (x.identifier = y.identifier) && (x.authority = y.authority) Set key = x Return 1
        }
    }
    Quit 0
}

/// The item's headers in ns newer than the origin, Queued (2), Delivered (3) or Completed (9), oldest first, less this
/// run's own clones. why is set, and the list empty, when the read failed or passed CAP.
ClassMethod Newer(ns As %String, item As %String, originHeaderId As %String, Output why As %String) As %List
{
    Set why = "", list = "", count = 0
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP " _ (..#CAP + 1) _ " ID FROM Ens.MessageHeader WHERE TargetConfigName = ? AND ID > ? AND Status IN (2, 3, 9) ORDER BY ID", item, +originHeaderId)
        If rs.%SQLCODE < 0 {
            Set why = "the engine's headers could not be read (" _ rs.%Message _ ")"
        } Else {
            While rs.%Next() {
                Set count = count + 1
                Set list = list _ $LISTBUILD(rs.%Get("ID"))
            }
        }
    } Catch err {
        Set why = "the engine's headers could not be read (" _ err.DisplayString() _ ")"
    }
    If (why = "") && (count > ..#CAP) Set why = "more than " _ ..#CAP _ " newer messages went to this receiver, more than Shutter reads, so this patient is held", list = ""
    Quit:why'="" ""
    // This run's own clones: the ledger lives in Shutter's namespace, the headers in ns.
    Set kept = ""
    For i = 1:1:$LISTLENGTH(list) {
        Set id = $LIST(list, i)
        Continue:##class(Shutter.Store.ResendRecord).IsOwnClone(ns, id)
        Set kept = kept _ $LISTBUILD(id)
    }
    Quit kept
}

/// The first of the newer headers whose body shares a key with <var>keys</var>: {"header", "time", "control", "key"},
/// or "".
ClassMethod FirstHit(ns As %String, headers As %List, keys As %DynamicArray) As %DynamicObject
{
    For i = 1:1:$LISTLENGTH(headers) {
        Set id = $LIST(headers, i)
        Set msg = ..Body(ns, id, .time)
        Continue:'$ISOBJECT(msg)
        Set theirs = []
        Set iter = ..Patients(msg).%GetIterator()
        While iter.%GetNext(, .p) {
            Set ik = p.keys.%GetIterator()
            While ik.%GetNext(, .k) { Do theirs.%Push(k) }
        }
        Continue:'..Shares(keys, theirs, .key)
        Quit
    }
    Quit:'$DATA(key) ""
    Quit:'$ISOBJECT(key) ""
    Quit {"header": (id), "time": (time), "control": (msg.GetValueAt("MSH:10")), "key": (key)}
}

/// Shutter's unresolved cases for any of the keys at the receiver, less <var>exclude</var>: [{"caseId", "state"}].
ClassMethod OpenCases(keys As %DynamicArray, receiver As %String, exclude As %List = "") As %DynamicArray
{
    Set cases = [], seen = ""
    Set iter = keys.%GetIterator()
    While iter.%GetNext(, .k) {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseId, State FROM Shutter_Store.""Case"" WHERE PatientId = ? AND PatientIdAuthority = ? AND Receiver = ? AND State <> 'resolved' ORDER BY ID", k.identifier, k.authority, receiver)
        Continue:rs.%SQLCODE<0
        While rs.%Next() {
            Set id = rs.%Get("CaseId")
            Continue:$LISTFIND(exclude, id)||$LISTFIND(seen, id)
            Set seen = seen _ $LISTBUILD(id)
            Do cases.%Push({"caseId": (id), "state": (rs.%Get("State"))})
        }
    }
    Quit cases
}

/// The stored body of a header in ns, with its creation time (UTC), or "".
ClassMethod Body(ns As %String, headerId As %String, Output time As %String) [ Private ]
{
    New $NAMESPACE
    Set msg = "", time = ""
    Try {
        Set $NAMESPACE = ns
        Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
        If $ISOBJECT(header) && (header.MessageBodyClassName = "EnsLib.HL7.Message") {
            Set msg = ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId), time = header.TimeCreated
        }
    } Catch {
        Set msg = ""
    }
    Quit msg
}

ClassMethod KeyWords(key As %DynamicObject) As %String [ Private ]
{
    Quit "identifier " _ key.identifier _ " (" _ key.authority _ ")"
}

ClassMethod CaseWords(cases As %DynamicArray) As %String [ Private ]
{
    Set text = ""
    Set iter = cases.%GetIterator()
    While iter.%GetNext(, .c) { Set text = text _ $SELECT(text = "": "", 1: ", ") _ c.caseId _ " (" _ c.state _ ")" }
    Quit text
}

}
