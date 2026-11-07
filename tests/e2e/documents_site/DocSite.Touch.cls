/// A transformation on the route that changes what is sent and leaves the document's number, the control id and the patient
/// alone, so the operation's bytes differ from the service's and the message is still the same message.
Class DocSite.Touch Extends Ens.DataTransform
{
ClassMethod Transform(source As EnsLib.HL7.Message, ByRef target As EnsLib.HL7.Message, aux = "") As %Status
{
    Set target = source.%ConstructClone(1)
    Set index = ""
    Set seg = target.FindSegment("OBX", .index)
    If $ISOBJECT(seg) {
        Set mine = target.getMutableSegmentByIndex(index)
        Set sc = mine.SetValueAt("Reworded on the route", "5")
        Quit:$$$ISERR(sc) sc
        Do target.setSegmentByIndex(mine, index, 0)
    }
    Quit target.%Save()
}
}
