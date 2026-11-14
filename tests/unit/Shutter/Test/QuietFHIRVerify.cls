/// The FHIR verifier with its reads taken in process, for tests that drive it outside the production: the read request
/// is handed to a FHIR Receiver whose adapter is the test FHIR server (<class>Shutter.Test.FakeFhir</class>), so every
/// request of a walk is in that adapter's log. A send with no production under it would be a runtime error.
/// <ul>
/// <li><property>Calls</property> counts the read requests, <property>LastRead</property> is the last one.</li>
/// <li><property>Fail</property>, when set, is the error the read call ends with, with no result.</li>
/// <li><property>Skip</property>, when set, is a Location reference whose read is taken out of the answer: a walk that
/// skipped a read.</li>
/// </ul>
Class Shutter.Test.QuietFHIRVerify Extends Shutter.Operation.FHIRVerify
{

Property Reader As Shutter.Operation.FHIRReceiver;

Property Calls As %Integer [ InitialExpression = 0 ];

Property LastRead As Shutter.Msg.FHIRRead;

Property Fail As %String(MAXLEN = 400);

Property Skip As %String(MAXLEN = 100);

Method ReadParts(read As Shutter.Msg.FHIRRead, Output result As Shutter.Msg.FHIRReadResult) As %Status
{
    Set result = ""
    Set ..Calls = ..Calls + 1, ..LastRead = read
    If ..Fail '= "" Quit $$$ERROR($$$GeneralError, ..Fail)
    Set sc = ..Reader.OnRead(read, .result)
    If $$$ISOK(sc) && (..Skip '= "") && $ISOBJECT(result) && (result.PartsJSON '= "") {
        Set parts = ##class(%DynamicAbstractObject).%FromJSON(result.PartsJSON), kept = []
        Set it = parts.locations.%GetIterator()
        While it.%GetNext(.i, .part) { Do:part.reference'=..Skip kept.%Push(part) }
        Set parts.locations = kept
        Set result.PartsJSON = parts.%ToJSON()
    }
    Quit sc
}

}
