/// The patient check before a message is sent again: is anything newer for its patients, or for its orders, already at the
/// receiver, or still open with Shutter? Every PID in the message is found by name (an ORU can carry several patients), and
/// every PID-3 repetition is a key: identifier and authority, the authority from PID-3.4.1 then PID-3.4, as
/// Shutter.Util.OperationKey reads it. A key with a blank authority is unknown, and holds that patient.
///
/// Two scopes (docs/design-1.4.0.md, part 1). The patient-wide rule (scope patient) is for ADT and every other message, an
/// order or result with no order number, and any message at a receiver whose category is not orders_results: in the source
/// namespace, the item's headers newer than the origin that are Queued, Delivered or Completed, whose body shares a key, hold
/// the message; so does a newer body that can't be read. Only this run's own clones are left out, known by the ledger's
/// NewHeaderId rows (Shutter.Store.ResendRecord); a hand resend's clone reads the same in the engine and counts, which is
/// right: someone else is resending. Then Shutter's unresolved cases for the patient at this receiver: every state but
/// resolved, since blocked, escalated and failed still need a person; the candidate's own case and the cases of the same
/// approved set are left out.
///
/// The order rule (scope order) is for an ORM, OML, OMG, OMI, ORU or OUL at an orders_results receiver with an order number
/// (Orders): a newer message on the same or a linked order holds it, whatever its patient and its status (N1); a newer
/// message for the same patient that can't be shown to be about other orders, or that replaces an order, holds it (N2); a
/// merge or an identity change of the patient after its creation holds it (N3, Identities); and Shutter's unresolved case
/// at the receiver holds it unless its message is about other orders (N4). What can't be read holds (N5).
///
/// A hold on any patient of a message holds the whole message, since Shutter never splits or edits one. More than CAP newer
/// headers holds the patient, and says so. The patient check reads merges and identity changes only where they pass through
/// this namespace; one made elsewhere is not seen.
Class Shutter.Util.PatientCheck [ Abstract ]
{

/// The most newer headers read; one more holds the patient.
Parameter CAP = 2000;

/// The most ADT bodies the merge read takes after a message; one more holds every candidate.
Parameter IDENTITYCAP = 5000;

/// The message types the order rule takes (MSH-9.1).
Parameter ORDERTYPES = ",ORM,OML,OMG,OMI,ORU,OUL,";

/// The ADT events that merge or change a patient's identifiers (MSH-9.2).
Parameter IDENTITYEVENTS = ",A18,A24,A30,A34,A35,A36,A37,A39,A40,A41,A42,A44,A45,A46,A47,A48,A49,A50,A51,";

/// The order control codes (ORC-1) of a replacement, which may carry new order numbers.
Parameter REPLACEMENTS = ",RP,RU,RO,RQ,RR,XO,XR,XX,";

/// The check for the stored message of <var>originHeaderId</var> to <var>item</var> in <var>ns</var>, at
/// <var>receiver</var> (a case's Receiver). <var>exclude</var> is a $LIST of case ids left out: the candidate's own and
/// the approved set's. <var>members</var> is a $LIST of the set's (or the run's) header ids, which the order rule leaves
/// out of its newer read, since the set's header id order already keeps them. {"hold", "scope", "patients": [{"pid",
/// "keys": [{"identifier", "authority"}], "hold", "rule", "why", "newer", "cases"}], "why", "older", "read_ms",
/// "headers_read"}. older is the control id of a newer result of another order for the same patient that reached the
/// receiver and did not hold it, or "".
ClassMethod Check(ns As %String, item As %String, originHeaderId As %String, receiver As %String, exclude As %List = "", members As %List = "") As %DynamicObject
{
    Set t0 = $ZHOROLOG
    Set out = {"hold": false, "scope": "patient", "patients": [], "why": "", "older": "", "read_ms": 0, "headers_read": 0}
    Set msg = ..Body(ns, originHeaderId, .created)
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
    Set mine = ..Orders(msg)
    Set byOrder = ..OrderScope(msg, receiver, mine)
    Set:byOrder out.scope = "order"
    Set newer = ..Newer(ns, item, originHeaderId, .why, byOrder, members)
    Set out."headers_read" = $LISTLENGTH(newer)
    // Each newer body read once for the pass: its patients' keys, its orders and its control id.
    Kill info
    If why = "" Do ..ReadNewer(ns, newer, .info)
    // The order rule's message-wide reads: N1 (a newer message on the same or a linked order, any patient, any status) and
    // the merge read (N3), once.
    Set whole = ""
    If (why = "") && byOrder Set whole = ..SameOrder(.info, mine)
    Set identity = ""
    If (why = "") && byOrder && (whole = "") Set identity = ..IdentityRead(ns, originHeaderId)
    Set iter = out.patients.%GetIterator()
    While iter.%GetNext(, .p) {
        Continue:p.hold
        If why '= "" {
            Do ..Held(p, $SELECT(why [ "more than": "cap", 1: "unreadable"), why)
            Continue
        }
        If $ISOBJECT(whole) {
            Do ..Held(p, whole.rule, whole.why)
            Set p.newer = whole.newer
            Continue
        }
        If byOrder {
            Do ..OrderPatient(p, .info, mine, identity, created, receiver, exclude, out)
        } Else {
            Do ..PatientWide(p, .info, receiver, exclude)
        }
    }
    Set held = 0
    Set iter = out.patients.%GetIterator()
    While iter.%GetNext(, .p) { Set:p.hold held = held + 1 }
    If held {
        Do out.%Set("hold", 1, "boolean")
        Set out.why = $SELECT(out.patients.%Size() > 1: held _ " of the message's " _ out.patients.%Size() _ " patients held, so the whole message waits: Shutter never splits or edits a message", 1: out.patients.%Get(0).why)
        If $ISOBJECT(whole) Set out.why = whole.why
        Set out.older = ""
    }
    Set out."read_ms" = $NUMBER(($ZHOROLOG - t0) * 1000, 0)
    Quit out
}

/// Today's patient-wide rule for one patient, with the unreadable tightening: the first newer header (Queued, Delivered or
/// Completed) whose body can't be read or shares a key holds it; then Shutter's unresolved cases at the receiver.
ClassMethod PatientWide(p As %DynamicObject, ByRef info, receiver As %String, exclude As %List)
{
    For i = 1:1:+$GET(info) {
        Continue:'..Reached(info(i, "status"))
        If info(i, "unreadable") {
            Do ..Held(p, "unreadable", "the newer message in header " _ info(i, "id") _ " could not be read, so it can't be shown to be for another patient")
            Quit
        }
        If ..Shares(p.keys, info(i, "keys"), .key) {
            Do ..Held(p, "same_patient", "a newer message for " _ ..KeyWords(key) _ " reached the receiver at " _ info(i, "time") _ " (control id " _ info(i, "control") _ ")")
            Set p.newer = {"header": (info(i, "id")), "time": (info(i, "time")), "control": (info(i, "control")), "key": (key)}
            Quit
        }
    }
    Quit:p.hold
    Set cases = ..OpenCases(p.keys, receiver, exclude)
    If cases.%Size() {
        Do ..Held(p, "open_case", "Shutter still has an unresolved case for this patient at this receiver: " _ ..CaseWords(cases))
        Set p.cases = cases
    }
}

/// The order rule for one patient, after N1: N2 (a newer message for the patient, reached, not proven about other orders,
/// or a replacement), N3 (a merge or an identity change), N4 (an unresolved case not proven about other orders).
ClassMethod OrderPatient(p As %DynamicObject, ByRef info, mine As %DynamicArray, identity As %DynamicObject, created As %String, receiver As %String, exclude As %List, out As %DynamicObject)
{
    // N2.
    For i = 1:1:+$GET(info) {
        Continue:'..Reached(info(i, "status"))
        Continue:(info(i, "unreadable"))
        Continue:'..Shares(p.keys, info(i, "keys"), .key)
        Set theirs = info(i, "orders"), lead = "a newer message for " _ ..KeyWords(key)
        Set rp = ..Replacement(theirs)
        If rp '= "" {
            Do ..Held(p, "replacement", lead _ " replaces an order (ORC-1 " _ rp _ "), and a replacement may carry new order numbers")
            Set p.newer = {"header": (info(i, "id")), "time": (info(i, "time")), "control": (info(i, "control")), "key": (key)}
            Quit
        }
        If ..OtherOrders(mine, theirs) {
            Set:out.older="" out.older = info(i, "control")
            Continue
        }
        Do ..Held(p, "same_patient", lead _ " reached the receiver at " _ ..Clock(info(i, "time")) _ " (control id " _ info(i, "control") _ "), and " _ ..NotOtherWords(mine, theirs))
        Set p.newer = {"header": (info(i, "id")), "time": (info(i, "time")), "control": (info(i, "control")), "key": (key)}
        Quit
    }
    Quit:p.hold
    // N3: the merge read of the namespace, then Shutter's own cases on a merge or an identity change.
    If '$ISOBJECT(identity) {
        Do ..Held(p, "unreadable", "the merge read could not be made, so a merge of this patient can't be ruled out")
        Quit
    }
    If identity.why '= "" {
        Do ..Held(p, $SELECT(identity.cap: "cap", 1: "unreadable"), identity.why)
        Quit
    }
    Set ei = identity.events.%GetIterator()
    While ei.%GetNext(, .e) {
        If ..Shares(p.keys, e.keys, .key) {
            Do ..Held(p, "identity", "an ADT^" _ e.event _ " at " _ ..Clock(e.time) _ " (" _ $SELECT(e.header '= "": "header " _ e.header, 1: "body " _ e.body) _ ") merges or changes " _ ..KeyWords(key) _ ", after this message was created: the receiver may hold the patient under another identifier")
            Quit
        }
    }
    Quit:p.hold
    Set merge = ..IdentityCase(p.keys, created)
    If merge '= "" {
        Do ..Held(p, "identity", "Shutter's case " _ $LIST(merge, 1) _ " is a merge naming " _ $LIST(merge, 2) _ ", opened after this message was created")
        Quit
    }
    // N4.
    Set cases = ..OpenCases(p.keys, receiver, exclude, 1)
    Set kept = [], same = 0, unread = 0
    Set ci = cases.%GetIterator()
    While ci.%GetNext(, .c) {
        Set copy = ##class(Shutter.Util.MessageCopy).Of($NAMESPACE, c.sourceHeaderId)
        If '$ISOBJECT(copy) {
            Set unread = 1
            Do kept.%Push({"caseId": (c.caseId), "state": (c.state)})
            Continue
        }
        Set theirs = ..Orders(copy)
        If (..Replacement(theirs) = "") && ..OtherOrders(mine, theirs) Continue
        Set:..SameOrder1(mine, theirs)'="" same = 1
        Do kept.%Push({"caseId": (c.caseId), "state": (c.state)})
    }
    If kept.%Size() {
        Set p.cases = kept
        If same {
            Do ..Held(p, "open_case", "Shutter still has an unresolved case on the same order at this receiver: " _ ..CaseWords(kept))
        } ElseIf unread {
            Do ..Held(p, "unreadable", "Shutter still has an unresolved case for this patient at this receiver whose stored copy could not be read, so it can't be shown to be about another order: " _ ..CaseWords(kept))
        } Else {
            Do ..Held(p, "open_case", "Shutter still has an unresolved case for this patient at this receiver, whose message can't be shown to be about another order: " _ ..CaseWords(kept))
        }
    }
}

/// N1 over the newer bodies, pure on what was read: the first newer header whose body can't be read, or that carries an
/// order group related to one of mine, as {"rule", "why", "newer"}, or "".
ClassMethod SameOrder(ByRef info, mine As %DynamicArray) As %DynamicObject
{
    For i = 1:1:+$GET(info) {
        If info(i, "unreadable") Return {"rule": "unreadable", "why": ("the newer message in header " _ info(i, "id") _ " could not be read, so it can't be shown to be about another order"), "newer": {"header": (info(i, "id"))}}
        Set m = ..SameOrder1(mine, info(i, "orders"))
        Continue:m=""
        Set what = $SELECT($LIST(m, 2): "an order linked to this one (" _ $LIST(m, 1) _ ")", 1: "the same order (" _ $LIST(m, 1) _ ")")
        Set newer = {"header": (info(i, "id")), "time": (info(i, "time")), "control": (info(i, "control"))}
        If ..Reached(info(i, "status")) Return {"rule": ($SELECT($LIST(m, 2): "linked_order", 1: "same_order")), "why": ("a newer message on " _ what _ " reached the receiver at " _ ..Clock(info(i, "time")) _ " (control id " _ info(i, "control") _ ")"), "newer": (newer)}
        Return {"rule": ($SELECT($LIST(m, 2): "linked_order", 1: "same_order")), "why": ("a newer message on " _ what _ ", header " _ info(i, "id") _ ", reads " _ ..StatusWord(info(i, "status")) _ ": a person decides the order's messages together"), "newer": (newer)}
    }
    Quit ""
}

/// The first related pair of two messages' order groups: $LISTBUILD(words, linked), or "".
ClassMethod SameOrder1(mine As %DynamicArray, theirs As %DynamicArray) As %List
{
    Set ia = mine.%GetIterator()
    While ia.%GetNext(, .a) {
        Set ib = theirs.%GetIterator()
        While ib.%GetNext(, .b) {
            Set m = ..Related(a, b)
            Return:m'="" m
        }
    }
    Quit ""
}

/// Whether the order rule applies: the receiver's category is orders_results, MSH-9.1 an order or result type, and an
/// order group carries a number.
ClassMethod OrderScope(msg As EnsLib.HL7.Message, receiver As %String, orders As %DynamicArray) As %Boolean
{
    Quit:..Category(receiver)'="orders_results" 0
    Set type = $ZCONVERT(msg.GetValueAt("MSH:9.1"), "U")
    Quit:(type="")||'(..#ORDERTYPES [ ("," _ type _ ",")) 0
    Set iter = orders.%GetIterator()
    While iter.%GetNext(, .g) { Return:$ISOBJECT(g.placer)||$ISOBJECT(g.filler) 1 }
    Quit 0
}

/// The receiver's category in the site profile, or "".
ClassMethod Category(receiver As %String) As %String
{
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(receiver)
    Quit ##class(Shutter.Util.Json).Str(entry, "category")
}

/// Every order group of a message, read by segment name: an ORC starts a group and the OBR after it joins it, and an OBR
/// with no ORC before it in its group starts its own. Each group: {"placer", "filler" (each {"id", "ns"}, or null),
/// "parents": [{"kind": "placer|filler", "id", "ns"}], "control" (ORC-1), "status" (OBR-25)}; placer is ORC-2, else
/// OBR-2, filler ORC-3, else OBR-3, and the parents those of ORC-8 and OBR-29.
ClassMethod Orders(msg As EnsLib.HL7.Message) As %DynamicArray
{
    Set out = [], g = "", hasObr = 0
    Set cs = $EXTRACT(msg.Separators, 2), ss = $EXTRACT(msg.Separators, 5)
    Set:cs="" cs = "^"
    Set:ss="" ss = "&"
    For i = 1:1:msg.SegCount {
        Set seg = msg.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        Set name = seg.Name
        Continue:(name'="ORC")&&(name'="OBR")
        If (name = "ORC") || '$ISOBJECT(g) || hasObr {
            Set g = {"placer": null, "filler": null, "parents": [], "control": "", "status": ""}, hasObr = 0
            Do out.%Push(g)
        }
        If name = "ORC" {
            Set g.control = $ZCONVERT($ZSTRIP(seg.GetValueAt(1), "<>W"), "U")
            Do ..Number(g, "placer", seg.GetValueAt(2), cs)
            Do ..Number(g, "filler", seg.GetValueAt(3), cs)
            Do ..Parent(g, seg.GetValueAt(8), cs, ss)
        } Else {
            Set hasObr = 1
            Do:'$ISOBJECT(g.placer) ..Number(g, "placer", seg.GetValueAt(2), cs)
            Do:'$ISOBJECT(g.filler) ..Number(g, "filler", seg.GetValueAt(3), cs)
            Do ..Parent(g, seg.GetValueAt(29), cs, ss)
            Set g.status = $ZCONVERT($ZSTRIP(seg.GetValueAt(25), "<>W"), "U")
        }
    }
    Quit out
}

/// An EI (identifier ^ namespace) into g's placer or filler, when it carries an identifier.
ClassMethod Number(g As %DynamicObject, kind As %String, value As %String, cs As %String) [ Private ]
{
    Set id = $ZSTRIP($PIECE(value, cs, 1), "<>W")
    Quit:id=""
    Do g.%Set(kind, {"id": (id), "ns": ($ZSTRIP($PIECE(value, cs, 2), "<>W"))})
}

/// An EIP (placer as .1 with subcomponents, filler as .2) into g's parents.
ClassMethod Parent(g As %DynamicObject, value As %String, cs As %String, ss As %String) [ Private ]
{
    Quit:value=""
    For k = 1, 2 {
        Set part = $PIECE(value, cs, k)
        Set id = $ZSTRIP($PIECE(part, ss, 1), "<>W")
        Continue:id=""
        Do g.parents.%Push({"kind": ($SELECT(k = 1: "placer", 1: "filler")), "id": (id), "ns": ($ZSTRIP($PIECE(part, ss, 2), "<>W"))})
    }
}

/// Two numbers are the same: identifiers equal, and namespaces equal or either blank.
ClassMethod Same(a As %DynamicObject, b As %DynamicObject) As %Boolean
{
    Quit:'$ISOBJECT(a)||'$ISOBJECT(b) 0
    Quit:(a.id="")||(a.id'=b.id) 0
    Quit (a.ns = b.ns) || (a.ns = "") || (b.ns = "")
}

/// Whether two order groups are related, pure: any of their numbers or parents the same, own to own, own to parent, parent
/// to own or parent to parent, a placer only with a placer and a filler only with a filler. $LISTBUILD(words, linked) for
/// the first match ("placer ORD1", "parent placer ORD1"), linked when a parent took part; "" when not related.
ClassMethod Related(a As %DynamicObject, b As %DynamicObject) As %List
{
    For kind = "placer", "filler" {
        If ..Same(a.%Get(kind), b.%Get(kind)) Return $LISTBUILD(kind _ " " _ a.%Get(kind).id, 0)
    }
    Set ia = a.parents.%GetIterator()
    While ia.%GetNext(, .pa) {
        If ..Same(pa, b.%Get(pa.kind)) Return $LISTBUILD("parent " _ pa.kind _ " " _ pa.id, 1)
        Set ib = b.parents.%GetIterator()
        While ib.%GetNext(, .pb) {
            If (pa.kind = pb.kind) && ..Same(pa, pb) Return $LISTBUILD("parent " _ pa.kind _ " " _ pa.id, 1)
        }
    }
    Set ib = b.parents.%GetIterator()
    While ib.%GetNext(, .pb) {
        If ..Same(pb, a.%Get(pb.kind)) Return $LISTBUILD("parent " _ pb.kind _ " " _ pb.id, 1)
    }
    Quit ""
}

/// Whether two order groups are proven distinct, pure: not related, and both carry a placer or both a filler.
ClassMethod Distinct(a As %DynamicObject, b As %DynamicObject) As %Boolean
{
    Quit:..Related(a, b)'="" 0
    Quit ($ISOBJECT(a.placer) && $ISOBJECT(b.placer)) || ($ISOBJECT(a.filler) && $ISOBJECT(b.filler))
}

/// Whether two messages are about other orders, pure: each has an order group and every pair, one from each, is proven
/// distinct.
ClassMethod OtherOrders(mine As %DynamicArray, theirs As %DynamicArray) As %Boolean
{
    Quit:(mine.%Size()=0)||(theirs.%Size()=0) 0
    Set ia = mine.%GetIterator()
    While ia.%GetNext(, .a) {
        Set ib = theirs.%GetIterator()
        While ib.%GetNext(, .b) { Return:'..Distinct(a, b) 0 }
    }
    Quit 1
}

/// The first replacement code (ORC-1) among a message's order groups, or "".
ClassMethod Replacement(orders As %DynamicArray) As %String
{
    Set iter = orders.%GetIterator()
    While iter.%GetNext(, .g) { Return:(g.control'="")&&(..#REPLACEMENTS [ ("," _ g.control _ ",")) g.control }
    Quit ""
}

/// Why a newer message for the patient can't be shown to be about other orders, as the end of a sentence.
ClassMethod NotOtherWords(mine As %DynamicArray, theirs As %DynamicArray) As %String [ Private ]
{
    Set numbered = 0
    Set iter = theirs.%GetIterator()
    While iter.%GetNext(, .g) { Set:$ISOBJECT(g.placer)||$ISOBJECT(g.filler) numbered = 1 }
    Quit:'numbered "it names no order, so it can't be shown to be about another order"
    Set mp = ..Kinds(mine), tp = ..Kinds(theirs)
    If (mp = "placer") && (tp = "filler") Quit "it carries only a filler number where this one has only a placer number"
    If (mp = "filler") && (tp = "placer") Quit "it carries only a placer number where this one has only a filler number"
    Quit "it can't be shown to be about another order"
}

/// "placer", "filler", "both" or "" for the kinds of number a message's groups carry.
ClassMethod Kinds(orders As %DynamicArray) As %String [ Private ]
{
    Set p = 0, f = 0
    Set iter = orders.%GetIterator()
    While iter.%GetNext(, .g) { Set:$ISOBJECT(g.placer) p = 1  Set:$ISOBJECT(g.filler) f = 1 }
    Quit $SELECT(p && f: "both", p: "placer", f: "filler", 1: "")
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
        Set p = {"pid": (n), "segment": (i), "keys": [], "hold": false, "rule": "", "why": "", "newer": null, "cases": []}
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
            Do ..Held(p, "unreadable", "patient " _ n _ " of the message has no identifier in PID-3")
        } ElseIf blank {
            Do ..Held(p, "unreadable", "an identifier of patient " _ n _ " has no assigning authority, so it is unknown which patient it is")
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

/// The item's headers in ns newer than the origin, oldest first, less this run's own clones and the set's members: Queued
/// (2), Delivered (3) or Completed (9) for the patient-wide rule, every status for the order rule. Each entry is
/// $LISTBUILD(id, status). why is set, and the list empty, when the read failed or passed CAP.
ClassMethod Newer(ns As %String, item As %String, originHeaderId As %String, Output why As %String, allStatuses As %Boolean = 0, members As %List = "") As %List
{
    Set why = "", list = "", count = 0, here = $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP " _ (..#CAP + 1) _ " ID, Status FROM Ens.MessageHeader WHERE TargetConfigName = ? AND ID > ?" _ $SELECT(allStatuses: "", 1: " AND Status IN (2, 3, 9)") _ " ORDER BY ID", item, +originHeaderId)
        If rs.%SQLCODE < 0 {
            Set why = "the engine's headers could not be read (" _ rs.%Message _ ")"
        } Else {
            While rs.%Next() {
                Continue:$LISTFIND(members, rs.%Get("ID"))
                Set count = count + 1
                Set list = list _ $LISTBUILD($LISTBUILD(rs.%Get("ID"), rs.%Get("Status")))
            }
        }
    } Catch err {
        Set why = "the engine's headers could not be read (" _ err.DisplayString() _ ")"
    }
    // Back in Shutter's namespace, where the ledger is.
    Set $NAMESPACE = here
    If (why = "") && (count > ..#CAP) Set why = "more than " _ ..#CAP _ " newer messages went to this receiver, more than Shutter reads, so this patient is held", list = ""
    Quit:why'="" ""
    // This run's own clones: the ledger lives in Shutter's namespace, the headers in ns.
    Set kept = ""
    For i = 1:1:$LISTLENGTH(list) {
        Set one = $LIST(list, i)
        Continue:##class(Shutter.Store.ResendRecord).IsOwnClone(ns, $LIST(one, 1))
        Set kept = kept _ $LISTBUILD(one)
    }
    Quit kept
}

/// Each newer header's body read once: info(i, "id"), "status", "time", "control", "unreadable", "keys" (every PID-3 key
/// of every PID) and "orders" (Orders).
ClassMethod ReadNewer(ns As %String, newer As %List, ByRef info) [ Private ]
{
    Set info = $LISTLENGTH(newer)
    For i = 1:1:info {
        Set one = $LIST(newer, i), id = $LIST(one, 1)
        Set info(i, "id") = id, info(i, "status") = $LIST(one, 2)
        Set msg = ..Body(ns, id, .time)
        Set info(i, "time") = time, info(i, "unreadable") = '$ISOBJECT(msg)
        Set info(i, "keys") = [], info(i, "orders") = [], info(i, "control") = ""
        Continue:'$ISOBJECT(msg)
        Set info(i, "control") = msg.GetValueAt("MSH:10")
        Set iter = ..Patients(msg).%GetIterator()
        While iter.%GetNext(, .p) {
            Set ik = p.keys.%GetIterator()
            While ik.%GetNext(, .k) { Do info(i, "keys").%Push(k) }
        }
        Set info(i, "orders") = ..Orders(msg)
    }
}

/// The merge read for one candidate: Identities from its body on. {"why", "cap", "events"}.
ClassMethod IdentityRead(ns As %String, originHeaderId As %String) As %DynamicObject [ Private ]
{
    Set bodyId = ..BodyIdOf(ns, originHeaderId)
    If bodyId = "" Quit {"why": "the stored message's body id could not be read, so a merge of its patient can't be ruled out", "cap": false, "events": []}
    Quit ..Identities(ns, bodyId)
}

/// Every HL7 body of ns newer than <var>fromBodyId</var>, to any item, whose DocType names an ADT structure or is blank,
/// read for an event that merges or changes identifiers (IDENTITYEVENTS): {"why", "cap", "events": [{"body", "header",
/// "event", "time", "keys"}]}, keys every PID-3 and MRG-1 identifier with its authority. More than IDENTITYCAP such
/// bodies, or a failed read, sets why. Inside a pass (Pass) what was read is kept, and only what arrived since is read.
ClassMethod Identities(ns As %String, fromBodyId As %String) As %DynamicObject
{
    Set out = {"why": "", "cap": false, "events": []}
    Set fromBodyId = +fromBodyId
    Set cached = $DATA(^||ShutterPatientCheck("pass")) && $DATA(^||ShutterPatientCheck("ns", ns, "from"))
    If cached && (fromBodyId >= ^||ShutterPatientCheck("ns", ns, "from")) {
        // Only what arrived since the last read.
        Set ok = ..ReadIdentities(ns, ^||ShutterPatientCheck("ns", ns, "to"), .why, .rows)
    } Else {
        Kill:cached ^||ShutterPatientCheck("ns", ns)
        Set cached = 0
        Set ok = ..ReadIdentities(ns, fromBodyId, .why, .rows)
    }
    If 'ok {
        Set out.why = why
        Do out.%Set("cap", why [ "more than", "boolean")
        Quit out
    }
    // rows(id) = $LISTBUILD(event, keys JSON, time, header) for an identity event, "" for another ADT body.
    Set id = "", to = $GET(^||ShutterPatientCheck("ns", ns, "to"), fromBodyId)
    For {
        Set id = $ORDER(rows(id), 1, v) Quit:id=""
        Set ^||ShutterPatientCheck("ns", ns, "adt", id) = v
        Set:id>to to = id
    }
    Set ^||ShutterPatientCheck("ns", ns, "to") = $SELECT(to > fromBodyId: to, 1: fromBodyId)
    Set:'cached ^||ShutterPatientCheck("ns", ns, "from") = fromBodyId
    Set count = 0, id = fromBodyId
    For {
        Set id = $ORDER(^||ShutterPatientCheck("ns", ns, "adt", id), 1, v) Quit:id=""
        Set count = count + 1
        If count > ..#IDENTITYCAP {
            Set out.why = "more than " _ ..#IDENTITYCAP _ " ADT messages passed through this namespace since this one, more than Shutter reads for merges"
            Do out.%Set("cap", 1, "boolean")
            Quit
        }
        Continue:v=""
        Do out.events.%Push({"body": (id), "event": ($LIST(v, 1)), "keys": ([].%FromJSON($LIST(v, 2))), "time": ($LIST(v, 3)), "header": ($LIST(v, 4))})
    }
    // Outside a pass nothing is kept.
    Kill:'$DATA(^||ShutterPatientCheck("pass")) ^||ShutterPatientCheck("ns", ns)
    Quit out
}

/// Starts (on 1) or ends (on 0) a pass, inside which the merge read keeps what it read: a set's computation, an Engine
/// Resend run.
ClassMethod Pass(on As %Boolean)
{
    Kill ^||ShutterPatientCheck
    Set:on ^||ShutterPatientCheck("pass") = 1
}

/// The ADT bodies of ns above <var>after</var>: rows(id) as Identities keeps them. 0 with why when the read failed or
/// passed IDENTITYCAP.
ClassMethod ReadIdentities(ns As %String, after As %String, Output why As %String, Output rows) As %Boolean [ Private ]
{
    Kill rows
    Set why = "", here = $NAMESPACE, n = 0
    Try {
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP " _ (..#IDENTITYCAP + 1) _ " ID, TimeCreated FROM EnsLib_HL7.Message WHERE ID > ? AND (DocType IS NULL OR DocType = '' OR DocType [ ':ADT') ORDER BY ID", +after)
        If rs.%SQLCODE < 0 {
            Set why = "the namespace's HL7 messages could not be read for merges (" _ rs.%Message _ ")"
        } Else {
            While rs.%Next() {
                Set n = n + 1
                If n > ..#IDENTITYCAP Set why = "more than " _ ..#IDENTITYCAP _ " ADT messages passed through this namespace since this one, more than Shutter reads for merges" Quit
                Set id = rs.%Get("ID")
                Set rows(id) = ..IdentityOf(id, rs.%Get("TimeCreated"))
            }
        }
    } Catch err {
        Set why = "the namespace's HL7 messages could not be read for merges (" _ err.DisplayString() _ ")"
    }
    Set $NAMESPACE = here
    Kill:why'="" rows
    Quit why = ""
}

/// One body, read while switched to its namespace (Shutter.Util.MessageCopy's rule: nothing read here is used after the
/// switch back but strings): "" for a body that is not an identity event, else $LISTBUILD(event, keys JSON, time, header).
ClassMethod IdentityOf(bodyId As %String, time As %String) As %String [ Private ]
{
    Set msg = ##class(EnsLib.HL7.Message).%OpenId(bodyId, 0)
    Quit:'$ISOBJECT(msg) ""
    Set seps = msg.Separators, fs = $EXTRACT(seps, 1), cs = $EXTRACT(seps, 2), rs = $EXTRACT(seps, 3), ss = $EXTRACT(seps, 5)
    Set:fs="" fs = "|"
    Set:cs="" cs = "^"
    Set:rs="" rs = "~"
    Set:ss="" ss = "&"
    Set msh = msg.GetSegmentAt(1)
    Set mshText = $SELECT($ISOBJECT(msh): msh.OutputToString(seps), 1: "")
    // MSH-9 is the ninth piece of the segment's text, since MSH-1 is the field separator itself.
    Set type = $PIECE(mshText, fs, 9)
    Set structure = $ZCONVERT($PIECE(type, cs, 1), "U"), event = $ZCONVERT($PIECE(type, cs, 2), "U")
    If (structure '= "ADT") || '(..#IDENTITYEVENTS [ ("," _ event _ ",")) Kill msg Quit ""
    Set keys = []
    For i = 2:1:msg.SegCount {
        Set seg = msg.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        Set name = seg.Name
        Continue:(name'="PID")&&(name'="MRG")
        Set text = $ZSTRIP(seg.OutputToString(seps), ">", $CHAR(13, 10))
        Set field = $PIECE(text, fs, $SELECT(name = "PID": 4, 1: 2))
        For r = 1:1:$LENGTH(field, rs) {
            Set rep = $PIECE(field, rs, r), id = $PIECE(rep, cs, 1)
            Continue:id=""
            Set auth = $PIECE($PIECE(rep, cs, 4), ss, 1)
            Set:auth="" auth = $PIECE(rep, cs, 4)
            Do keys.%Push({"identifier": (id), "authority": (auth)})
        }
    }
    Kill msg
    Set header = ""
    Set hr = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.HL7.Message' AND MessageBodyId = ? ORDER BY ID", bodyId)
    If hr.%SQLCODE >= 0, hr.%Next() Set header = hr.%Get("ID")
    Quit $LISTBUILD(event, keys.%ToJSON(), time, header)
}

/// Shutter's own case on a merge or an identity change, any state and any receiver, opened after <var>created</var> (the
/// candidate's TimeCreated) and naming one of the keys as its patient or its prior patient: $LISTBUILD(caseId, the key in
/// words), or "".
ClassMethod IdentityCase(keys As %DynamicArray, created As %String) As %List
{
    Set after = ..Iso(created)
    Set iter = keys.%GetIterator()
    While iter.%GetNext(, .k) {
        Continue:k.authority=""
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseId, Event, OpenedAt FROM Shutter_Store.""Case"" WHERE ((PatientId = ? AND PatientIdAuthority = ?) OR (PriorPatientId = ? AND PriorPatientIdAuthority = ?)) ORDER BY ID", k.identifier, k.authority, k.identifier, k.authority)
        Continue:rs.%SQLCODE<0
        While rs.%Next() {
            Set event = $ZCONVERT(rs.%Get("Event"), "U")
            Continue:(event'="MERGE")&&'(..#IDENTITYEVENTS [ ("," _ event _ ","))
            Continue:(after'="")&&'($EXTRACT(rs.%Get("OpenedAt"), 1, 19) ] $EXTRACT(after, 1, 19))
            Return $LISTBUILD(rs.%Get("CaseId"), ..KeyWords(k))
        }
    }
    Quit ""
}

/// Shutter's unresolved cases for any of the keys at the receiver, less <var>exclude</var>: [{"caseId", "state"}], with
/// <var>withCopy</var> each with its "sourceHeaderId" (Shutter's stored copy of the message) too.
ClassMethod OpenCases(keys As %DynamicArray, receiver As %String, exclude As %List = "", withCopy As %Boolean = 0) As %DynamicArray
{
    Set cases = [], seen = ""
    Set iter = keys.%GetIterator()
    While iter.%GetNext(, .k) {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseId, State, SourceHeaderId FROM Shutter_Store.""Case"" WHERE PatientId = ? AND PatientIdAuthority = ? AND Receiver = ? AND State <> 'resolved' ORDER BY ID", k.identifier, k.authority, receiver)
        Continue:rs.%SQLCODE<0
        While rs.%Next() {
            Set id = rs.%Get("CaseId")
            Continue:$LISTFIND(exclude, id)||$LISTFIND(seen, id)
            Set seen = seen _ $LISTBUILD(id)
            Set c = {"caseId": (id), "state": (rs.%Get("State"))}
            Set:withCopy c.sourceHeaderId = rs.%Get("SourceHeaderId")
            Do cases.%Push(c)
        }
    }
    Quit cases
}

/// The stored body of a header in ns, copied here (Shutter.Util.MessageCopy), with its creation time (UTC), or "".
ClassMethod Body(ns As %String, headerId As %String, Output time As %String) [ Private ]
{
    Quit ##class(Shutter.Util.MessageCopy).Of(ns, headerId, .time)
}

/// The body id of a header in ns, or "".
ClassMethod BodyIdOf(ns As %String, headerId As %String) As %String [ Private ]
{
    Set here = $NAMESPACE, id = ""
    Try {
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE ID = ? AND MessageBodyClassName = 'EnsLib.HL7.Message'", headerId)
        If rs.%Next() Set id = rs.%Get("MessageBodyId")
    } Catch {
        Set id = ""
    }
    Set $NAMESPACE = here
    Quit id
}

ClassMethod Held(p As %DynamicObject, rule As %String, why As %String) [ Private ]
{
    Do p.%Set("hold", 1, "boolean")
    Set p.rule = rule, p.why = why
}

/// Queued (2), Delivered (3) or Completed (9): the message reached the receiver, or the engine still has it.
ClassMethod Reached(status As %String) As %Boolean [ Private ]
{
    Quit (status = 2) || (status = 3) || (status = 9)
}

ClassMethod StatusWord(status As %String) As %String [ Private ]
{
    Quit ##class(Shutter.Util.EngineRead).StatusWord(status)
}

/// HH:MM of an engine time ("2026-11-09 03:12:01.123"), or the time as given.
ClassMethod Clock(time As %String) As %String [ Private ]
{
    Set t = $PIECE($TRANSLATE(time, "T", " "), " ", 2)
    Quit $SELECT(t '= "": $EXTRACT(t, 1, 5), 1: time)
}

/// An engine time as ISO 8601 UTC ("2026-11-09T03:12:01"), or "".
ClassMethod Iso(time As %String) As %String [ Private ]
{
    Quit:time="" ""
    Quit $TRANSLATE($EXTRACT(time, 1, 19), " ", "T")
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
