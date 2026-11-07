/// A transformation on the route that changes the patient and the document before the operation, as a site's DTL can. A case
/// must show what the operation was given, not what the service received.
Class DocSite.Swap Extends Ens.DataTransform
{
ClassMethod Transform(source As EnsLib.HL7.Message, ByRef target As EnsLib.HL7.Message, aux = "") As %Status
{
    Set target = source.%ConstructClone(1)
    Set index = ""
    Set seg = target.getMutableSegmentByIndex(3)
    Set sc = seg.SetValueAt("DELIVEREDMRN", "3(1).1")
    Quit:$$$ISERR(sc) sc
    Do target.setSegmentByIndex(seg, 3, 0)
    Set txa = target.FindSegment("TXA", .index)
    If $ISOBJECT(txa) {
        Set mine = target.getMutableSegmentByIndex(index)
        Set sc = mine.SetValueAt("DELIVEREDDOC^DMS", "12")
        Quit:$$$ISERR(sc) sc
        Do target.setSegmentByIndex(mine, index, 0)
    }
    Quit target.%Save()
}
}
