/// A feed the demo scenarios play a message through, apart from ADT In (CONTRACTS 4.3 and 8.2): a production item with no
/// job of its own (PoolSize 0, as the Community licence caps processes) that sends an HL7 message to its target, so the
/// message's header names this item as its source. "Other Route In" is S14's route, whose delivery Shutter does not watch:
/// only the index sees it. "Site Feed In" is S26's feed of a site whose schema was never imported. Demo only: neither item
/// goes into a site's production (Shutter.Setup, INSTALLITEMS). <method>Play</method> is how a scenario step uses one.
Class Shutter.Scenarios.Route Extends Ens.BusinessService
{

/// The item the messages go to.
Property TargetConfigName As %String(MAXLEN = 128);

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

/// The message goes on to the target, as an inbound HL7 service with no document type set would send it.
Method OnProcessInput(pInput As %Library.Persistent, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    Quit ..SendRequestAsync(..TargetConfigName, pInput)
}

/// An HL7 file's message, untyped; error says what went wrong.
ClassMethod Message(path As %String, Output error As %String) As EnsLib.HL7.Message
{
    Set error = ""
    If '##class(%File).Exists(path) {
        Set error = "no file " _ path
        Quit ""
    }
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(path)
    Set text = ""
    While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    Set message = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    If $$$ISERR(sc) {
        Set error = "could not read " _ path _ ": " _ $SYSTEM.Status.GetErrorText(sc)
        Quit ""
    }
    Quit message
}

/// Plays an HL7 file through the item. Returns an empty string, or what went wrong.
ClassMethod Play(item As %String, path As %String) As %String
{
    Set message = ..Message(path, .error)
    Quit:error'="" error
    Set sc = ##class(Ens.Director).CreateBusinessService(item, .service)
    If $$$ISOK(sc) && $ISOBJECT(service) Set sc = service.ProcessInput(message, .out)
    If $$$ISERR(sc) Quit "the item " _ item _ " did not take " _ path _ ": " _ $SYSTEM.Status.GetErrorText(sc)
    Quit ""
}

}
