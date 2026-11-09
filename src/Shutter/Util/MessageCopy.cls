/// A stored HL7 message of another namespace, copied whole into this process as a transient message (never saved).
///
/// A message opened while switched to a watched namespace and used after switching back reads its segments lazily from the
/// namespace the process is in by then: the same ids in Shutter's own namespace are another message, or none (found on the
/// Pathology rig on 9 Nov 2026: a patient check read the wrong patient). So every segment is read as text while switched,
/// with stock calls only, and the copy is built from that text back here, segment by segment, which keeps the characters
/// as stored: no character set is applied, and MSH-18 is not read as an instruction to decode.
Class Shutter.Util.MessageCopy [ Abstract ]
{

/// The stored body of the header <var>headerId</var> in <var>ns</var>, as a transient EnsLib.HL7.Message with its DocType,
/// or "" when the header, its body or a segment can't be read. <var>time</var> is the header's TimeCreated (UTC).
ClassMethod Of(ns As %String, headerId As %String, Output time As %String) As EnsLib.HL7.Message
{
    Set time = ""
    Quit:(ns="")||(headerId="") ""
    Set seps = "", docType = "", segs = 0, here = $NAMESPACE
    Try {
        // Switched only for the reads; back before anything is built, so the copy and its segments belong here.
        Set $NAMESPACE = ns
        // The header by SQL: %OpenId would hand back an object of the same id already in this process's memory, which
        // may be another namespace's.
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MessageBodyClassName, MessageBodyId, TimeCreated FROM Ens.MessageHeader WHERE ID = ?", headerId)
        Quit:'rs.%Next()
        Quit:rs.%Get("MessageBodyClassName")'="EnsLib.HL7.Message"
        Set time = rs.%Get("TimeCreated"), bodyId = rs.%Get("MessageBodyId")
        Kill rs
        Set msg = ##class(EnsLib.HL7.Message).%OpenId(bodyId, 0)
        Quit:'$ISOBJECT(msg)
        Set seps = msg.Separators, docType = msg.DocType
        For i = 1:1:msg.SegCount {
            Set seg = msg.GetSegmentAt(i)
            If '$ISOBJECT(seg) Set segs = -1 Quit
            // OutputToString ends a segment with its terminator, which is no part of the last field.
            Set segs = segs + 1, segs(segs) = $ZSTRIP(seg.OutputToString(seps), ">", $CHAR(13, 10))
        }
        Kill msg
    } Catch {
        Set segs = -1
    }
    Set $NAMESPACE = here
    Quit:segs<1 ""
    Quit ..Build(seps, docType, .segs)
}

/// A transient message from segment texts segs(1) to segs(segs), in this namespace.
ClassMethod Build(seps As %String, docType As %String, ByRef segs) As EnsLib.HL7.Message
{
    Set copy = ##class(EnsLib.HL7.Message).%New()
    Set:seps'="" copy.Separators = seps
    For i = 1:1:segs {
        Set seg = ##class(EnsLib.HL7.Segment).ImportFromString(segs(i), .sc, copy.Separators)
        Quit:'$ISOBJECT(seg)
        // A new message holds one empty segment already: the first takes its place, the rest follow it.
        Set sc = $SELECT(i = 1: copy.SetSegmentAt(seg, 1), 1: copy.AppendSegment(seg))
        Quit:$$$ISERR(sc)
    }
    Quit:copy.SegCount'=segs ""
    Set:docType'="" copy.DocType = docType
    Quit copy
}

}
