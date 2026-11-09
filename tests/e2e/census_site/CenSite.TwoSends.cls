/// One message in, two different messages out to one receiver in one session: the first answered AA and the second AE by the
/// rig's listener, which answers by the control id's prefix. Which of them failed is not something a case naming the session's
/// first header can establish.
Class CenSite.TwoSends Extends Ens.BusinessProcess
{
Method OnRequest(request As EnsLib.HL7.Message, Output response As %Library.Persistent) As %Status
{
    Set response = "", control = request.GetValueAt("MSH:10")
    For code = "AA", "AE" {
        Set one = request.%ConstructClone(1)
        Set sc = one.SetValueAt(code _ "-" _ control, "MSH:10") Quit:$$$ISERR(sc)
        Set sc = one.%Save() Quit:$$$ISERR(sc)
        Set sc = ..SendRequestAsync("Cen Out", one, 0) Quit:$$$ISERR(sc)
    }
    Quit sc
}
}
