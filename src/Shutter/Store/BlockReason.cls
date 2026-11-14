/// The catalogue of blocked reasons: for each reason code the gate or the workflow can produce,
/// what is missing, the next permitted action, who owns it and what triggers a re-evaluation. The
/// texts come from knowledge/block-reasons.json; the app renders them beside a blocked case.
Class Shutter.Store.BlockReason Extends (%Persistent, %JSON.Adaptor)
{

Property Code As %String(%JSONFIELDNAME = "code", MAXLEN = 64) [ Required ];

Index CodeIdx On Code [ Unique ];

Property Title As %String(%JSONFIELDNAME = "title", MAXLEN = 200);

Property Prerequisite As %String(%JSONFIELDNAME = "prerequisite", MAXLEN = 1000);

Property NextAction As %String(%JSONFIELDNAME = "nextAction", MAXLEN = 1000);

Property Owner As %String(%JSONFIELDNAME = "owner", MAXLEN = 100);

Property ReevaluateWhen As %String(%JSONFIELDNAME = "reevaluateWhen", MAXLEN = 1000);

Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = 4000);

ClassMethod ByCode(code As %String) As Shutter.Store.BlockReason
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Store.BlockReason WHERE Code = :code)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// The reason as a person reads it for one case: ForReceiver's, and for an order or a result (a message Shutter does not
/// model, or one to an orders and results receiver) its own words where the catalogue's speak of a mapping that failed, a
/// category not modelled or a receiver's record that could not be read (one with no API has none to read); and for a
/// case of a FHIR receiver its own words where the catalogue's promise a wait (<method>ForFHIR</method>). The stored row
/// is never changed.
ClassMethod ForCase(code As %String, case As Shutter.Store.Case) As Shutter.Store.BlockReason
{
    Set r = ..ForReceiver(code, case.Receiver)
    If '$ISOBJECT(r) Quit r
    If ((code = "ENGINE_STILL_TRYING") || (code = "NEWER_MESSAGE_PENDING")) && (##class(Shutter.Store.SiteProfile).ReceiverKind(case.Receiver) = "fhir_r4") Quit ..ForFHIR(r, code)
    If '..OrderOrResult(case) Quit r
    If '((code = "UNMAPPABLE") || (code = "RECEIVER_NOT_MODELLED") || ((code = "RECEIVER_UNREADABLE") && ##class(Shutter.Operation.Gate).NoRecordToRead(case.Receiver))) Quit r
    Set r.Title = "Shutter does not resend one order or result by itself"
    Set r.Prerequisite = "A person's decision on this order or result"
    Set r.NextAction = "Check the source's Message Viewer: an operation that retries may still deliver it. If it will not go by itself, send the case to the receiver's team, or mark it handled once it has been sent again or entered at the receiver by hand."
    Set r.Owner = "Operator"
    Set r.ReevaluateWhen = "The message is delivered, sent again by hand or entered at the receiver"
    Set r.Text = "This is an order or a result. Shutter sends nothing for one such message on its own, and the message itself may be sound: a person decides, starting from the source's Message Viewer."
    Quit r
}

/// The two reasons that elsewhere hold a case until something has finished, as a person reads them for a case of a
/// FHIR receiver. Such a case is held for nothing and is never judged again by itself, so the words say to
/// reinvestigate. A copy: the stored row is never changed.
ClassMethod ForFHIR(stored As Shutter.Store.BlockReason, code As %String) As Shutter.Store.BlockReason [ Private ]
{
    Set r = stored.%ConstructClone()
    If code = "ENGINE_STILL_TRYING" {
        Set r.NextAction = "Read the message in the Message Viewer. Over FHIR the case does not wait for the engine: once the engine has finished with the message, reinvestigate the case, which reads fresh evidence and judges it again."
        Set r.ReevaluateWhen = "A person reinvestigates the case, once the engine has finished with the message"
        Set r.Text = "The message is Queued or Delivered at a stock HL7 TCP operation, or that operation is retrying, or a copy of it is in hand. The engine may still deliver it when the receiver returns, so an update over FHIR now could be followed by the same move over HL7. Nothing is written, and the case stops for a person."
    } Else {
        Set r.NextAction = "Over FHIR the case does not wait for the newer message. Once it has been delivered, reinvestigate the case: it is planned again on fresh evidence, and a newer movement usually means nothing needs writing."
        Set r.ReevaluateWhen = "A person reinvestigates the case, once the newer message is delivered or its delivery has failed"
        Set r.Text = "A newer message for the same patient arrived from the source system and has not yet reached the receiver. Writing first would be pointless at best, and wrong behind a cancellation or a merge, so nothing is written and the case stops for a person."
    }
    Quit r
}

/// Whether a case is an order or a result: not a document case, and either an order or result message Shutter does not
/// model ("This message is ORU, not ADT: ...", every such structure starting with O) or one to an orders and results
/// receiver.
ClassMethod OrderOrResult(case As Shutter.Store.Case) As %Boolean
{
    If case.DocumentJSON '= "" Quit 0
    If case.NotModelled() && ($EXTRACT($PIECE(case.FailureText, " ", 4)) = "O") Quit 1
    Quit ##class(Shutter.Store.SiteProfile).ReceiverCategory(case.Receiver) = "orders_results"
}

/// The reason as a person reads it for a case's receiver: the catalogue's own, except that a receiver unreadable because
/// its site profile entry is still the onboarding's draft (declared with no API) says so, with filling in that entry as
/// the next action. The stored row is never changed.
ClassMethod ForReceiver(code As %String, receiver As %String) As Shutter.Store.BlockReason
{
    Set r = ..ByCode(code)
    If '$ISOBJECT(r) || (code '= "RECEIVER_UNREADABLE") Quit r
    Set detail = ##class(Shutter.Store.SiteProfile).DraftDetail(receiver)
    If detail = "" Quit r
    Set r.Text = detail _ ". Until then nothing about it can be judged, so nothing is eligible."
    Set r.NextAction = ##class(Shutter.Store.SiteProfile).DraftNextAction(receiver)
    Set r.Owner = "Integration team", r.ReevaluateWhen = "A person saves the receiver's entry without draft"
    Quit r
}

/// Load the catalogue from a JSON file: an array of objects with code, title, prerequisite,
/// next_action, owner, reevaluate_when and text. Existing codes are replaced. Returns the count.
ClassMethod SeedFromFile(path As %String, Output count As %Integer) As %Status
{
    Set count = 0
    If '##class(%File).Exists(path) Quit $$$OK
    Set json = ##class(Shutter.Knowledge.Text).ReadFile(path)
    Set arr = ##class(Shutter.Util.Json).Parse(json, .sc)
    Quit:$$$ISERR(sc) sc
    If '$ISOBJECT(arr) Quit $$$OK
    If arr.%IsA("%Library.DynamicObject") && $ISOBJECT(arr.%Get("reasons")) Set arr = arr.%Get("reasons")
    Set iter = arr.%GetIterator()
    While iter.%GetNext(.i, .d) {
        Set code = ##class(Shutter.Util.Json).Str(d, "code")
        Continue:(code="")
        Set r = ..ByCode(code)
        If '$ISOBJECT(r) Set r = ..%New(), r.Code = code
        Set r.Title = ##class(Shutter.Util.Json).Str(d, "title")
        Set r.Prerequisite = ##class(Shutter.Util.Json).Str(d, "prerequisite")
        Set r.NextAction = ##class(Shutter.Util.Json).Str(d, "next_action", ##class(Shutter.Util.Json).Str(d, "nextAction"))
        Set r.Owner = ##class(Shutter.Util.Json).Str(d, "owner")
        Set r.ReevaluateWhen = ##class(Shutter.Util.Json).Str(d, "reevaluate_when", ##class(Shutter.Util.Json).Str(d, "reevaluateWhen"))
        Set r.Text = ##class(Shutter.Util.Json).Str(d, "text")
        Set sc = r.%Save()
        Quit:$$$ISERR(sc)
        Set count = count + 1
    }
    Quit sc
}

Storage Default
{
<Data name="BlockReasonDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Code</Value>
</Value>
<Value name="3">
<Value>Title</Value>
</Value>
<Value name="4">
<Value>Prerequisite</Value>
</Value>
<Value name="5">
<Value>NextAction</Value>
</Value>
<Value name="6">
<Value>Owner</Value>
</Value>
<Value name="7">
<Value>ReevaluateWhen</Value>
</Value>
<Value name="8">
<Value>Text</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.BlockReasonD</DataLocation>
<DefaultData>BlockReasonDefaultData</DefaultData>
<IdLocation>^Shutter.Store.BlockReasonD</IdLocation>
<IndexLocation>^Shutter.Store.BlockReasonI</IndexLocation>
<StreamLocation>^Shutter.Store.BlockReasonS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
