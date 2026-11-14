/// The demo hospital's results route, "Lab In": a feed with no job of its own (PoolSize 0, as the Community licence caps
/// processes) that sends a laboratory result to the results system's connector, "Lab Results Out", so the message's header
/// names this item as its source. The two pathology paths of the Scenarios page play their results through it
/// (Shutter.Scenarios.Runner, a file step with the route "lab"). Demo only: the item is in Hospital.Production, never in a
/// site's production.
Class Hospital.Service.LabFeed Extends Ens.BusinessService
{

/// The item the results go to.
Property TargetConfigName As %String(MAXLEN = 128);

Parameter SETTINGS = "TargetConfigName:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

/// The message goes on to the target, as an inbound HL7 service would send it.
Method OnProcessInput(pInput As %Library.Persistent, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    Quit ..SendRequestAsync(..TargetConfigName, pInput)
}

/// Plays an HL7 file through <var>item</var> in this namespace, with a fresh control id, message time, patient and order
/// numbers (<method>Stamped</method>), so two runs never share a message or a patient. Returns an empty string, or what
/// went wrong; <var>control</var> is the control id the message went with.
ClassMethod Play(item As %String, path As %String, Output control As %String) As %String
{
    Set control = ""
    If '##class(%File).Exists(path) Quit "no file " _ path
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(path)
    Set text = ""
    While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    Set text = ..Stamped(text, $INCREMENT(^Hospital.Lab("played")), .control)
    Set message = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    If $$$ISERR(sc) Quit "could not read " _ path _ ": " _ $SYSTEM.Status.GetErrorText(sc)
    // Typed under the category its MSH-12 names, as an inbound HL7 service types what it takes, so a reader of the
    // stored message finds its fields by name (the control id on the outage's lists, say).
    Set category = ##class(Shutter.Util.Schemas).CategoryOf(message)
    If ##class(Shutter.Util.Schemas).Known(category) {
        Set type = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType(category, message.Name, .tsc)
        If $$$ISOK(tsc) && (type '= "") Do message.PokeDocType(type)
    }
    Set sc = ##class(Ens.Director).CreateBusinessService(item, .service)
    If $$$ISOK(sc) && $ISOBJECT(service) Set sc = service.ProcessInput(message, .out)
    If $$$ISERR(sc) Quit "the item " _ item _ " did not take " _ path _ ": " _ $SYSTEM.Status.GetErrorText(sc)
    Quit ""
}

/// One step on the results route, run as a process of its own in this namespace (Shutter.Scenarios.Runner starts it
/// with JOB): "play" plays <var>path</var> through <var>item</var> (<method>Play</method>), "up" and "down" switch the
/// results system's stand-in on and off (Hospital.Service.LabReceiver, Listen). A process of its own, because a
/// production item's job of another namespace that calls this production's services or Ens.Director here is left
/// registered as that service, and the next update of this production refuses it. The answer goes to
/// ^Hospital.Lab("step", key): "" when it went, or what went wrong.
ClassMethod Step(what As %String, item As %String, path As %String, key As %String)
{
    Set out = ""
    Try {
        If what = "play" {
            Set out = ..Play(item, path, .control)
        } Else {
            Set r = ##class(Hospital.Service.LabReceiver).Listen(what = "up")
            Set:$EXTRACT(r, 1, 6)="error:" out = $EXTRACT(r, 8, *)
        }
    } Catch ex {
        Set out = ex.DisplayString()
    }
    Set ^Hospital.Lab("step", key) = $LISTBUILD(1, out)
}

/// The message's text with MSH-7 set to now, MSH-10 to a fresh control id, the first identifier of PID-3 to a fresh NHS
/// number in the test range (999, with a valid check digit) and the placer and filler numbers of ORC and OBR to fresh
/// ones; every other byte as the fixture has it. <var>n</var> is the play's number.
ClassMethod Stamped(text As %String, n As %Integer, Output control As %String) As %String
{
    Set now = $TRANSLATE($ZDATETIME($HOROLOG, 8, 1), " :", "")
    Set control = "LR" _ $EXTRACT(now, 3, 14) _ $EXTRACT(1000 + (n # 1000), 2, 4)
    Set patient = ##class(Shutter.Util.LiveFeed).NhsNumber("MRN" _ (n # 10000))
    Set cr = $CHAR(13), out = ""
    For i = 1:1:$LENGTH(text, cr) {
        Set seg = $PIECE(text, cr, i), name = $EXTRACT(seg, 1, 3)
        If name = "MSH" {
            Set $PIECE(seg, "|", 7) = now, $PIECE(seg, "|", 10) = control
        } ElseIf name = "PID" {
            Set ids = $PIECE(seg, "|", 4), first = $PIECE(ids, "~", 1)
            Set $PIECE(first, "^", 1) = patient, $PIECE(ids, "~", 1) = first, $PIECE(seg, "|", 4) = ids
        } ElseIf (name = "ORC") || (name = "OBR") {
            // ORC-2 and ORC-3, OBR-2 and OBR-3: the placer and filler numbers.
            Set:$PIECE(seg, "|", 3)'="" $PIECE(seg, "|", 3) = "P" _ control
            Set:$PIECE(seg, "|", 4)'="" $PIECE(seg, "|", 4) = "F" _ control
        }
        Set out = out _ $SELECT(i > 1: cr, 1: "") _ seg
    }
    Quit out
}

}
