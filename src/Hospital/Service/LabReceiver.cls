/// "Results System In": a stand-in for the demo's results system, an HL7 listener inside the same instance, on a loopback
/// port. It is not a laboratory system and files nothing: it has no target, and it only answers each result. A result whose
/// every OBX-3 code is on its short list (<parameter>KNOWN</parameter>) gets AA; one naming another code gets AE, in the
/// words a receiver would use ("Test code not recognised: ZZUNK"). Every frame it answers is counted in
/// ^Hospital.Lab("heard"), with its control id, its time, the SHA-256 of its text and the code answered, so a check can
/// read what arrived, how often, and byte for byte. The pathology paths switch it off and on as the production
/// (Shutter.Scenarios.Runner, the step lab_receiver), so the receiver goes down and comes back as a real one would.
Class Hospital.Service.LabReceiver Extends EnsLib.HL7.Service.TCPService
{

/// The test codes the stand-in knows: the made-up panel of the pathology fixtures.
Parameter KNOWN = "HB,WBC,PLT,MCV,HCT,TST01,TST02,TST03,TST04,TST05,TST06,TST07,TST08";

/// The answer to each result: AA, or AE naming the first OBX-3 code not on the list. The frame is counted first.
Method OnConstructReply(Output pReplyDoc As EnsLib.EDI.Document, pOriginalDoc As EnsLib.EDI.Document, ByRef pReplyCode As %String, ByRef pSC As %Status, pEarlyAck As %Boolean) As %Status
{
    Set control = pOriginalDoc.GetValueAt("1:10"), unknown = ..UnknownCode(pOriginalDoc)
    Set answer = $SELECT(unknown = "": "AA", 1: "AE")
    Do ..Heard(control, pOriginalDoc.OutputToString(), answer)
    Set pReplyDoc = pOriginalDoc.NewReplyDocument(, ..LocalFacilityApplication)
    Do pReplyDoc.SetValueAt(control, "1:10")
    Set msa = ##class(EnsLib.HL7.Segment).%New($LISTBUILD("", 1))
    Set msa.Separators = pReplyDoc.Separators
    Do msa.SetValueAt("MSA", 0)
    Do msa.SetValueAt(answer, 1)
    Do msa.SetValueAt(control, 2)
    Do:unknown'="" msa.SetValueAt("Test code not recognised: " _ unknown, 3)
    Do pReplyDoc.AppendSegment(msa)
    Set pReplyDoc.IsMutable = 0
    Set pReplyCode = answer
    Quit $$$OK
}

/// The first OBX-3 code of <var>doc</var> that is not on the stand-in's list, or "" when it knows every one.
ClassMethod UnknownCode(doc As EnsLib.EDI.Document) As %String
{
    Set unknown = ""
    For i = 1:1:doc.SegCount {
        Set seg = doc.GetSegmentAt(i)
        Continue:'$ISOBJECT(seg)
        Continue:seg.Name'="OBX"
        Set code = $PIECE(seg.GetValueAt(3), seg.CS, 1)
        If (code '= "") && '$LISTFIND($LISTFROMSTRING(..#KNOWN), code) Set unknown = code Quit
    }
    Quit unknown
}

/// Records one frame: ^Hospital.Lab("heard") counts them, and ^Hospital.Lab("heard", n) is $LISTBUILD(control id, UTC
/// time, SHA-256 of the text in hex, the code answered).
ClassMethod Heard(control As %String, text As %String, answer As %String)
{
    Set digest = $ZCONVERT(##class(%xsd.hexBinary).LogicalToXSD($SYSTEM.Encryption.SHAHash(256, $ZCONVERT(text, "O", "UTF8"))), "L")
    Set n = $INCREMENT(^Hospital.Lab("heard"))
    Set ^Hospital.Lab("heard", n) = $LISTBUILD(control, $ZDATETIME($ZTIMESTAMP, 3, 1, 3), digest, answer)
}

/// The item's name in Hospital.Production.
Parameter ITEM = "Results System In";

/// Whether the stand-in's item is enabled in this namespace's production definition; "" when that can't be read.
ClassMethod Listening() As %String
{
    Set enabled = ""
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Enabled FROM Ens_Config.Item WHERE Production = ? AND Name = ?", "Hospital.Production", ..#ITEM)
        If rs.%Next() Set enabled = ''rs.%Get("Enabled")
    } Catch ex {
        Set enabled = ""
    }
    Quit enabled
}

/// Switches the stand-in on or off in the running production, as the production's own setting (Ens.Director,
/// EnableConfigItem): off, its listener closes and a connection to its port is refused; on, it listens again. Only when it
/// reads otherwise, so a switch that is already so changes nothing. Returns "on", "off", "already on", "already off", or
/// "error: ..." with what went wrong. Called in this namespace.
ClassMethod Listen(on As %Boolean) As %String
{
    Set on = ''on, now = ..Listening()
    If now = "" Quit "error: the item " _ ..#ITEM _ " is not in Hospital.Production here"
    If now = on Quit "already " _ $SELECT(on: "on", 1: "off")
    Try {
        Set sc = ##class(Ens.Director).EnableConfigItem(..#ITEM, on, 1)
        Set out = $SELECT($$$ISOK(sc): $SELECT(on: "on", 1: "off"), 1: "error: " _ $SYSTEM.Status.GetErrorText(sc))
    } Catch ex {
        Set out = "error: " _ ex.DisplayString()
    }
    Quit out
}

/// The SHA-256 (hex) of the HL7 message a header of this namespace carries, as the stand-in digests what it hears: so a
/// check compares what the receiver heard with the stored message, byte for byte. "" when the header or its body is not
/// an HL7 message here. Callable over SQL in the hospital's namespace (SELECT Hospital_Service.LabReceiver_BodyDigest(12)).
ClassMethod BodyDigest(headerId As %String) As %String [ SqlProc ]
{
    Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
    Quit:'$ISOBJECT(header) ""
    Quit:header.MessageBodyClassName'="EnsLib.HL7.Message" ""
    Set doc = ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId)
    Quit:'$ISOBJECT(doc) ""
    Quit $ZCONVERT(##class(%xsd.hexBinary).LogicalToXSD($SYSTEM.Encryption.SHAHash(256, $ZCONVERT(doc.OutputToString(), "O", "UTF8"))), "L")
}

/// What the stand-in heard, oldest first: [{"n", "control", "at", "sha256", "answer"}]. JSON text; callable over SQL in
/// the hospital's namespace (SELECT Hospital_Service.LabReceiver_HeardList()).
ClassMethod HeardList() As %String [ SqlProc ]
{
    Set out = [], n = ""
    For {
        Set n = $ORDER(^Hospital.Lab("heard", n), 1, row)
        Quit:n=""
        Do out.%Push({"n": (+n), "control": ($LISTGET(row, 1)), "at": ($LISTGET(row, 2)), "sha256": ($LISTGET(row, 3)), "answer": ($LISTGET(row, 4))})
    }
    Quit out.%ToJSON()
}

}
