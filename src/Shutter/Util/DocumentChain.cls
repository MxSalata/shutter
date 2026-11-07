/// A document's chain, read from the message store of the namespace it runs in (docs/CONTRACTS.md 11.2): the requests to one
/// receiver, newest first, up to a limit, read by Shutter.Util.DocumentFacts for their document numbers. No index and no copy:
/// a chain read live has no lag, and what it read is reported beside what it found, so a limit reached, a body that cannot be
/// read or a store purged earlier is coverage it cannot claim. Every row is metadata. Runs in the watched namespace.
Class Shutter.Util.DocumentChain
{

/// Messages read per chain at most, unless a receiver's setting says otherwise.
Parameter LIMIT = 5000;

/// Rows a chain holds at most.
Parameter ROWS = 50;

/// The chain of a document at an item: {complete, read, limit, unreadable, since, read_at, rows, namespace, item}.
ClassMethod Read(item As %String, documentId As %String, parentId As %String, limit As %Integer = "") As %DynamicObject
{
    If +limit < 1 Set limit = ..#LIMIT
    Set out = {"namespace": ($NAMESPACE), "item": (item), "read_at": ($ZDATETIME($ZTIMESTAMP, 3, 1, 3))}
    Do out.%Set("limit", +limit, "number")
    Set rows = [], read = 0, unreadable = 0, since = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ (+limit) _ " ID, MessageBodyId, MessageBodyClassName, Status, TimeCreated FROM Ens.MessageHeader WHERE TargetConfigName = ? AND Type = 1 ORDER BY ID DESC", item)
    While rs.%Next() {
        Set read = read + 1, since = rs.%Get("TimeCreated")
        Set cls = rs.%Get("MessageBodyClassName")
        If cls = "" Continue
        Set isHL7 = 0
        Try { Set isHL7 = $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") } Catch inner { Set isHL7 = 0 }
        Continue:'isHL7
        Set msg = $CLASSMETHOD(cls, "%OpenId", rs.%Get("MessageBodyId"))
        If '$ISOBJECT(msg) Set unreadable = unreadable + 1 Continue
        Continue:'##class(Shutter.Util.DocumentFacts).IsDocument(msg)
        Set f = ##class(Shutter.Util.DocumentFacts).FromMessage(msg, .fsc, 0)
        If '$ISOBJECT(f) Set unreadable = unreadable + 1 Continue
        Set id = rs.%Get("ID"), events(id) = $LISTBUILD(f.document.id, f.document.parent, rs.%Get("MessageBodyId"), cls), facts(id) = f.%ToJSON(), status(id) = rs.%Get("Status"), created(id) = rs.%Get("TimeCreated")
    }
    // The chain: the document, its parent and every event linked to them, by number, either way.
    If documentId '= "" Set in(documentId) = ""
    If parentId '= "" Set in(parentId) = ""
    For pass = 1:1:10 {
        Set grew = 0, id = ""
        For {
            Set id = $ORDER(events(id)) Quit:id=""
            Set a = $LIST(events(id), 1), b = $LIST(events(id), 2)
            If (a '= "") && $DATA(in(a)) && (b '= "") && '$DATA(in(b)) Set in(b) = "", grew = 1
            If (b '= "") && $DATA(in(b)) && (a '= "") && '$DATA(in(a)) Set in(a) = "", grew = 1
        }
        Quit:'grew
    }
    Set capped = 0, id = ""
    For {
        Set id = $ORDER(events(id), -1) Quit:id=""
        Set a = $LIST(events(id), 1), b = $LIST(events(id), 2)
        Continue:'(((a '= "") && $DATA(in(a))) || ((b '= "") && $DATA(in(b))))
        If rows.%Size() >= ..#ROWS Set capped = 1 Quit
        Set f = ##class(%DynamicObject).%FromJSON(facts(id))
        Set row = {"header_id": (id), "trigger": (f.trigger), "control_id": (f."control_id"), "document_id": (f.document.id), "parent_id": (f.document.parent), "completion": (f.document.completion), "confidentiality": (f.document.confidentiality), "availability": (f.document.availability), "patient_binding": (f.patient.binding), "patient_keys": (f.patient.keys), "time_created": (created(id))}
        Set row.status = ##class(Ens.DataType.MessageStatus).LogicalToDisplay(status(id))
        // The digests only for the chain's own rows, however many messages were read.
        Set msg = $CLASSMETHOD($LIST(events(id), 4), "%OpenId", $LIST(events(id), 3))
        Set d = ##class(Shutter.Util.DocumentDigest).%New()
        Set osc = $SELECT($ISOBJECT(msg): msg.OutputToIOStream(d), 1: 0)
        If $$$ISERR(osc) { Set unreadable = unreadable + 1, row."body_digest" = "", row."content_digest" = "" } Else { Set row."body_digest" = d.Finish(.content), row."content_digest" = content }
        Do rows.%Push(row)
    }
    Do out.%Set("read", read, "number")
    Do out.%Set("unreadable", unreadable, "number")
    Set out.since = since, out.rows = rows
    Do out.%Set("limit_reached", read >= limit, "boolean")
    Do out.%Set("rows_capped", capped, "boolean")
    Do out.%Set("complete", (read < limit) && (unreadable = 0) && 'capped, "boolean")
    Quit out
}

/// The envelope the forwarder posts: no text of the message, whatever its size. Named fields only.
ClassMethod Envelope(request As Shutter.Intake.Forward, facts As %DynamicObject, header As Ens.MessageHeader, namespace As %String, production As %String, route As %String, receiver As %String, ambiguous As %Boolean, limit As %Integer) As %DynamicObject
{
    Set body = {"kind": "document_failure", "receiver": (receiver)}
    Set body.source = {"namespace": (namespace), "production": (production), "route": (route), "header_id": (header.%Id()), "item": (request.Receiver)}
    Set body.failure = {"kind": (request.FailureKind), "text": (request.FailureText), "outcome": (request.FailureOutcome), "reason_code": (request.FailureReasonCode)}
    If request.FailureHttpStatus '= "" Do body.failure.%Set("http_status", +request.FailureHttpStatus, "number")
    Set body.delivery = {"header_id": (header.%Id()), "status": (##class(Shutter.Util.DocumentFacts).StatusWords(header)), "time_created": (header.TimeCreated), "time_processed": (header.TimeProcessed)}
    Do body.delivery.%Set("ambiguous", ''ambiguous, "boolean")
    Set body.facts = facts
    Set body.chain = ..Read(request.Receiver, facts.document.id, facts.document.parent, limit)
    Quit body
}

}
