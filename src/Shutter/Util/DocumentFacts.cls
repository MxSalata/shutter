Include EnsHL7

/// What Shutter reads of a document message (docs/CONTRACTS.md 11.2): MDM T01 to T11, by position, needing no schema, from the
/// delivery body. A report carried as an attachment, an ORU, has its own walk below. MSH, every PID-3 repetition, PV1-19 and TXA-12, -13, -17, -18, -19, and nothing else: no OBX, no NTE, no
/// name, no title, no file name. The walk stops at TXA, which comes before the OBX segments in every MDM structure, so a large
/// document's value is not read for the fields. A message with no TXA reads each later segment's first stored piece for its name
/// and no further (a piece is at most the longest string IRIS holds, about 3.6 MB). The size and the digests go through the stored
/// pieces one at a time and keep none. Runs in the watched namespace (the package is mapped there) and in Shutter's, so it reads no Shutter store.
Class Shutter.Util.DocumentFacts
{

/// Characters of a stored OBX read for the rule: past OBX-2, and no further.
Parameter OBXREAD = 64;

/// Characters of another stored segment of an ORU read for its fields.
Parameter SEGREAD = 32000;

/// The triggers of HL7 v2.5.1 chapter 9. T12 is a query, and no failed delivery of a document.
ClassMethod IsTrigger(trigger As %String) As %Boolean
{
    Quit trigger?1"T"2N && (+$EXTRACT(trigger, 2, 3) >= 1) && (+$EXTRACT(trigger, 2, 3) <= 11)
}

/// Whether an HL7 message is an MDM T01 to T11, from its MSH alone.
ClassMethod IsDocument(msg As EnsLib.HL7.Message) As %Boolean
{
    If '$ISOBJECT(msg) Quit 0
    Set seg = msg.GetSegmentAt(1)
    If '$ISOBJECT(seg) Quit 0
    Set cs = seg.CS
    Set type = seg.GetValueAt(9)
    Quit ($PIECE(type, cs, 1) = "MDM") && ..IsTrigger($PIECE(type, cs, 2))
}

/// The same from the message's text.
ClassMethod IsDocumentText(text As %String) As %Boolean
{
    Set text = $EXTRACT($ZSTRIP($EXTRACT(text, 1, 2000), "<WC"), 1, 2000)
    If $EXTRACT(text, 1, 3) '= "MSH" Quit 0
    Set fs = $EXTRACT(text, 4), cs = $EXTRACT(text, 5)
    Set msh = $PIECE($PIECE(text, $CHAR(13), 1), $CHAR(10), 1)
    Set type = $PIECE(msh, fs, 9)
    Quit ($PIECE(type, cs, 1) = "MDM") && ..IsTrigger($PIECE(type, cs, 2))
}

/// Whether an HL7 message is an ORU of any trigger, from its MSH alone. Whether it carries an attachment takes the walk.
ClassMethod IsReportMessage(msg As EnsLib.HL7.Message) As %Boolean
{
    If '$ISOBJECT(msg) Quit 0
    Set seg = msg.GetSegmentAt(1)
    If '$ISOBJECT(seg) Quit 0
    Quit $PIECE(seg.GetValueAt(9), seg.CS, 1) = "ORU"
}

/// The rule for a report carried as an attachment, one OBX at a time: OBX-2 says ED or RP. Answers which, or "" for anything
/// else: base64 sent under TX or ST reads as text.
ClassMethod Attachment(type As %String) As %String
{
    Set type = $ZCONVERT(type, "U")
    Quit $SELECT((type = "ED") || (type = "RP"): type, 1: "")
}

/// Whether a message's text is an ORU with an attachment, and its message type.
ClassMethod IsReportText(text As %String, Output type As %String) As %Boolean
{
    Set facts = ..FromText(text, .sc, 0), type = ""
    If '$ISOBJECT(facts) || (facts.kind '= "report") Quit 0
    Set type = facts."message_type"
    Quit facts.report.attachment '= ""
}

/// One segment of an ORU into what the walk keeps. PID, PV1 and OBR stand until the first attachment, so the identity is that
/// attachment's own. Later segments only count, and every OBR is kept as a pair and a status for the chain's match. An OBX gives
/// its type and the rule's answer, and nothing else of it is held.
ClassMethod ReportLine(name As %String, line As %String, fs As %String, cs As %String, ByRef raw) [ Private ]
{
    If (name = "MSH") {
        For f = 3, 4, 5, 6, 7, 9, 10, 12 { Set raw("MSH", f) = $PIECE(line, fs, f) }
        Set raw("MSH") = 1
    } ElseIf name = "OBX" {
        If '$DATA(raw("at")) {
            Set how = ..Attachment($PIECE(line, fs, 3))
            If how '= "" Set raw("at") = how
        }
    } ElseIf (name = "OBR") {
        Set n = $GET(raw("orders")) + 1, raw("orders") = n
        Set placer = ..EI($PIECE(line, fs, 3), cs), filler = ..EI($PIECE(line, fs, 4), cs), status = $PIECE(line, fs, 26)
        Set raw("orders", n) = $LISTBUILD(placer, filler, status)
        If '$DATA(raw("at")) Set raw("OBR") = $LISTBUILD(placer, filler, status)
    } ElseIf '$DATA(raw("at")) {
        If name = "PID" Set raw("PID", 3) = $PIECE(line, fs, 4), raw("PID") = 1 Kill raw("PV1")
        If name = "PV1" Set raw("PV1", 19) = $PIECE(line, fs, 20), raw("PV1") = 1
    }
}

/// The facts of an ORU from the walk: Build's, with its own identity on them. Its number is the report's, else the order's.
ClassMethod ReportFacts(ByRef raw, rs As %String, cs As %String, ss As %String) As %DynamicObject [ Private ]
{
    // With no attachment, the first OBR stands for the message.
    Set own = $GET(raw("OBR"), $GET(raw("orders", 1), $LISTBUILD("", "", "")))
    Set o = ..Build(.raw, rs, cs, ss), o.kind = "report"
    Do o.document.%Remove("txa_present")
    Set o.document.id = $SELECT($LIST(own, 2) '= "": $LIST(own, 2), 1: $LIST(own, 1))
    Set r = {"placer": ($LIST(own, 1)), "filler": ($LIST(own, 2)), "result_status": ($LIST(own, 3)), "attachment": ($GET(raw("at")))}
    Do r.%Set("orders", +$GET(raw("orders")), "number")
    Set o.report = r
    Quit o
}

/// A stored ORU, walked by the engine's own segment ids: each segment's start is read straight from where it is stored, and an
/// OBX's only as far as the rule needs, so a value of any size is never held. withDigests as in FromMessage.
ClassMethod ReportFromMessage(msg As EnsLib.HL7.Message, Output sc As %Status, withDigests As %Boolean = 1) As %DynamicObject [ Private ]
{
    Set sc = $$$OK, out = ""
    Try {
        Set first = msg.GetSegmentAt(1)
        Set fs = first.FS, cs = first.CS, rs = first.RS, ss = first.SS
        For i = 1:1:msg.SegCount {
            Set id = msg.getSegmentIdByIndex(i)
            Continue:id=""
            Set head = $SELECT(id [ ",": $EXTRACT($$$vaSegment(id), 6, 13), 1: $EXTRACT($$$vaSegmentGbl(id), 6, 13))
            Set name = $PIECE(head, fs, 1), last = 5 + $SELECT(name = "OBX": ..#OBXREAD, 1: ..#SEGREAD)
            Do ..ReportLine(name, $SELECT(id [ ",": $EXTRACT($$$vaSegment(id), 6, last), 1: $EXTRACT($$$vaSegmentGbl(id), 6, last)), fs, cs, .raw)
        }
        Set out = ..ReportFacts(.raw, rs, cs, ss)
        If 'withDigests {
            // The chain's pass: every OBR, to match against. This stays off a case's block.
            Set list = []
            For i = 1:1:+$GET(raw("orders")) { Do list.%Push({"placer": ($LIST(raw("orders", i), 1)), "filler": ($LIST(raw("orders", i), 2)), "result_status": ($LIST(raw("orders", i), 3))}) }
            Set out."all_orders" = list
        } Else {
            Set out.size = ..Size(##class(EnsLib.HL7.Message).GetFullSize(msg.%Id()))
            Set d = ##class(Shutter.Util.DocumentDigest).%New()
            Set osc = msg.OutputToIOStream(d)
            If $$$ISERR(osc) {
                Set out.digests = {"body": "", "content": ""}
            } Else {
                Set body = d.Finish(.content)
                Set out.digests = {"body": (body), "content": (content)}
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus(), out = ""
    }
    Quit out
}

/// The facts of a stored message, with its size and digests, or "" with the status said. withDigests 0 reads the fields only
/// (the chain's first pass over many messages).
ClassMethod FromMessage(msg As EnsLib.HL7.Message, Output sc As %Status, withDigests As %Boolean = 1) As %DynamicObject
{
    Set sc = $$$OK, out = ""
    If ..IsReportMessage(msg) Quit ..ReportFromMessage(msg, .sc, withDigests)
    Try {
        Set index = "", seen = 0
        For {
            Set seg = msg.FindSegment("*", .index)
            Quit:'$ISOBJECT(seg)
            Set name = seg.Name
            If $CASE(name, "MSH": 1, "PID": 1, "PV1": 1, "TXA": 1, : 0) && '$DATA(raw(name)) {
                If name = "MSH" Set rs = seg.RS, cs = seg.CS, ss = seg.SS
                Set fields = ..Fields(name)
                For i = 1:1:$LISTLENGTH(fields) { Set raw(name, $LIST(fields, i)) = seg.GetValueAt($LIST(fields, i)) }
                Set raw(name) = 1
            }
            // The message keeps each segment it hands out, which a chain's walk over many must not.
            Do msg.commitSegmentByIndex(index)
            Quit:name="TXA"
        }
        Set out = ..Build(.raw, $GET(rs, "~"), $GET(cs, "^"), $GET(ss, "&"))
        If withDigests {
            Set out.size = ..Size(##class(EnsLib.HL7.Message).GetFullSize(msg.%Id()))
            Set d = ##class(Shutter.Util.DocumentDigest).%New()
            Set osc = msg.OutputToIOStream(d)
            // A body that can't be written out still opens its case, with no digest to compare.
            If $$$ISERR(osc) {
                Set out.digests = {"body": "", "content": ""}
            } Else {
                Set body = d.Finish(.content)
                Set out.digests = {"body": (body), "content": (content)}
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus(), out = ""
    }
    Quit out
}

/// The facts of a message's text, for the intake's whole-text path: the same fields, by the same positions.
ClassMethod FromText(text As %String, Output sc As %Status, withDigests As %Boolean = 1) As %DynamicObject
{
    Set sc = $$$OK, out = ""
    Try {
        Set text = $REPLACE(text, $CHAR(13, 10), $CHAR(13))
        If '(text [ $CHAR(13)) Set text = $TRANSLATE(text, $CHAR(10), $CHAR(13))
        If $EXTRACT(text, *) '= $CHAR(13) Set text = text _ $CHAR(13)
        Set start = $FIND(text, "MSH")
        If 'start Set sc = $$$ERROR($$$GeneralError, "The message has no MSH") Quit
        Set text = $EXTRACT(text, start - 3, *)
        Set fs = $EXTRACT(text, 4), cs = $EXTRACT(text, 5), rs = $EXTRACT(text, 6), ss = $EXTRACT(text, 8)
        Set report = $PIECE($PIECE($PIECE(text, $CHAR(13), 1), fs, 9), cs, 1) = "ORU"
        For i = 1:1:$LENGTH(text, $CHAR(13)) {
            Set line = $PIECE(text, $CHAR(13), i)
            Set name = $PIECE(line, fs, 1)
            If report {
                Do ..ReportLine(name, $EXTRACT(line, 1, $SELECT(name = "OBX": ..#OBXREAD, 1: ..#SEGREAD)), fs, cs, .raw)
                Continue
            }
            If $CASE(name, "MSH": 1, "PID": 1, "PV1": 1, "TXA": 1, : 0) && '$DATA(raw(name)) {
                Set fields = ..Fields(name)
                For j = 1:1:$LISTLENGTH(fields) { Set raw(name, $LIST(fields, j)) = $PIECE(line, fs, $LIST(fields, j) + $SELECT(name = "MSH": 0, 1: 1)) }
                Set raw(name) = 1
            }
            Quit:name="TXA"
        }
        Set out = $SELECT(report: ..ReportFacts(.raw, rs, cs, ss), 1: ..Build(.raw, rs, cs, ss))
        Quit:'withDigests
        Set out.size = ..Size($LENGTH(text))
        Set body = ##class(Shutter.Util.DocumentDigest).OfText(text, .content)
        Set out.digests = {"body": (body), "content": (content), "basis": "posted_text"}
    } Catch ex {
        Set sc = ex.AsStatus(), out = ""
    }
    Quit out
}

/// The only fields read of each segment.
ClassMethod Fields(segment As %String) As %List [ Private ]
{
    Quit $CASE(segment, "MSH": $LISTBUILD(3, 4, 5, 6, 7, 9, 10, 12), "PID": $LISTBUILD(3), "PV1": $LISTBUILD(19), "TXA": $LISTBUILD(12, 13, 17, 18, 19), : "")
}

/// The stored size against the intake's limit for a whole message.
ClassMethod Size(bytes As %Integer) As %DynamicObject
{
    Set o = {}
    Do o.%Set("stored_bytes", +bytes, "number")
    Do o.%Set("over_intake_limit", +bytes > 2097152, "boolean")
    Quit o
}

/// The facts from the fields read: every value whole, an EI or a CX as the message has it.
ClassMethod Build(ByRef raw, rs As %String, cs As %String, ss As %String) As %DynamicObject [ Private ]
{
    Set o = {}, type = $GET(raw("MSH", 9))
    Set o.trigger = $PIECE(type, cs, 2), o.structure = $PIECE(type, cs, 3), o."message_type" = $PIECE(type, cs, 1) _ "^" _ $PIECE(type, cs, 2)
    Set o."control_id" = $GET(raw("MSH", 10)), o."hl7_version" = $PIECE($GET(raw("MSH", 12)), cs, 1), o."message_time" = $PIECE($GET(raw("MSH", 7)), cs, 1)
    Set o."sending_application" = $GET(raw("MSH", 3)), o."sending_facility" = $GET(raw("MSH", 4))
    Set o."receiving_application" = $GET(raw("MSH", 5)), o."receiving_facility" = $GET(raw("MSH", 6))
    Set doc = {}
    Do doc.%Set("txa_present", ''$DATA(raw("TXA")), "boolean")
    Set doc.id = ..EI($GET(raw("TXA", 12)), cs), doc.parent = ..EI($GET(raw("TXA", 13)), cs)
    Set doc.completion = $GET(raw("TXA", 17)), doc.confidentiality = $GET(raw("TXA", 18)), doc.availability = $GET(raw("TXA", 19))
    Set o.document = doc
    Set keys = [], list = ""
    Set field = $GET(raw("PID", 3))
    If field '= "" {
        For r = 1:1:$LENGTH(field, rs) {
            Set cx = $PIECE(field, rs, r)
            Continue:$PIECE(cx, cs, 1)=""
            Set k = {"id": ($PIECE(cx, cs, 1)), "authority": ($PIECE(cx, cs, 4)), "type": ($PIECE(cx, cs, 5))}
            Do keys.%Push(k)
            Set sorted(k.id _ "^" _ k.authority _ "^" _ k.type) = ""
        }
    }
    Set s = "" For { Set s = $ORDER(sorted(s)) Quit:s=""  Set list = list _ s _ "~" }
    Set o.patient = {"keys": (keys), "binding": ($SELECT(list = "": "", 1: ##class(Shutter.Util.Digest).SHA256Hex(list)))}
    Set o.encounter = $PIECE($GET(raw("PV1", 19)), cs, 1)
    Quit o
}

/// An entity identifier whole, its trailing empty parts dropped, so "X^DMS" and "X^DMS^^" are one number; empty when its first
/// and third parts (the identifier and the universal id) are both empty, as a number that names nothing.
ClassMethod EI(field As %String, cs As %String) As %String
{
    If ($PIECE(field, cs, 1) = "") && ($PIECE(field, cs, 3) = "") Quit ""
    Set text = field
    While $EXTRACT(text, *) = cs { Set text = $EXTRACT(text, 1, *-1) }
    Quit text
}

/// The delivery header of a session at an item: the newest request header to that item with an HL7 body, or "" when the session
/// has none; several different bodies are said, since which one failed is then not known.
ClassMethod DeliveryHeader(session As %String, item As %String, Output ambiguous As %Boolean) As Ens.MessageHeader
{
    Set ambiguous = 0, found = "", bodies = 0
    If (session = "") || (item = "") Quit ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, MessageBodyId, MessageBodyClassName FROM Ens.MessageHeader WHERE SessionId = ? AND TargetConfigName = ? AND Type = 1 ORDER BY ID DESC", session, item)
    While rs.%Next() {
        Set cls = rs.%Get("MessageBodyClassName"), isHL7 = 0
        Continue:cls=""
        Try { Set isHL7 = $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") } Catch inner { Set isHL7 = 0 }
        Continue:'isHL7
        If found = "" Set found = rs.%Get("ID")
        Set body(rs.%Get("MessageBodyId")) = ""
    }
    Set b = "" For { Set b = $ORDER(body(b)) Quit:b=""  Set bodies = bodies + 1 }
    Set ambiguous = (bodies > 1)
    Quit $SELECT(found = "": "", 1: ##class(Ens.MessageHeader).%OpenId(found))
}

/// The engine's own words for a header's status.
ClassMethod StatusWords(header As Ens.MessageHeader) As %String
{
    Quit ##class(Ens.DataType.MessageStatus).LogicalToDisplay(header.Status)
}

}
