/// A function a routing rule can call, standing where a site's own or Shutter's function set would. It answers 1 when
/// ^V11Rig.Hold(item, the message's first PID-3.1) is set, and counts every call in ^V11Rig.Calls, so a check can see the rule
/// really ran it.
Class V11Rig.RuleFn Extends Ens.Rule.FunctionSet
{

ClassMethod RigHold(msg As EnsLib.HL7.Message, item As %String) As %Boolean [ Final ]
{
    Set answer = 0
    Try {
        Set ^V11Rig.Calls = $GET(^V11Rig.Calls) + 1
        Set answer = ''$DATA(^V11Rig.Hold(item, $PIECE($PIECE(msg.FindSegment("PID").GetValueAt(3), "~"), "^")))
    } Catch {
        Set answer = 0
    }
    Quit answer
}

}
