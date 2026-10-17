/// An adapterless business service through which the REST API sends requests into the production
/// (a blind-resend preview, for example), so that even the app's own calls show in the trace.
Class Shutter.Service.API Extends Ens.BusinessService
{

Parameter ADAPTER;

/// Seconds to wait for the target.
Property Timeout As %Integer [ InitialExpression = 30 ];

Parameter SETTINGS = "Timeout:Basic";

/// pInput is an Ens.Request whose target is named by the caller through the Target property of
/// this service instance; the response comes back as pOutput.
Property Target As %String(MAXLEN = 128);

/// Set by the caller to send without waiting for the answer (a scenario run); pOutput stays empty.
Property Async As %Boolean [ InitialExpression = 0 ];

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    If ..Target = "" Quit $$$ERROR($$$GeneralError, "No target set on the API service")
    If ..Async Quit ..SendRequestAsync(..Target, pInput)
    Quit ..SendRequestSync(..Target, pInput, .pOutput, ..Timeout)
}

}
