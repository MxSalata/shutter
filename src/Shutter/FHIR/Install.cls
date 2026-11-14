/// The four production items of a FHIR R4 receiver, placed by a call and never shipped in Shutter.Production: an
/// install whose site never made the call has no FHIR item, no job for one and nothing new in the Doctor's item check.
/// PlaceItems records the server in ^Shutter.Config("fhirItems") = $LISTBUILD(host, port, credential, ssl), and
/// RestoreItems puts the items back from that record after a load or an upgrade rewrote the production from the
/// package. FHIR Receiver reads and FHIR Out writes, so the two always get the same server: a second call rewrites
/// both.
Class Shutter.FHIR.Install [ Abstract ]
{

/// The four adapter settings that name the server, in the order of the record.
Parameter ENDPOINT = "HTTPServer,HTTPPort,Credentials,SSLConfig";

/// The class of one of the four items, or "" for any other name.
ClassMethod ItemClass(name As %String) As %String
{
    Quit $CASE(name, "FHIR Receiver": "Shutter.Operation.FHIRReceiver", "FHIR Out": "Shutter.Operation.FHIRExecute", "FHIR Gate": "Shutter.Operation.FHIRGate", "FHIR Verifier": "Shutter.Operation.FHIRVerify", : "")
}

/// Whether the item calls the server: the reader and the writer do, the gate and the verifier ask the reader.
ClassMethod CallsTheServer(name As %String) As %Boolean [ Private ]
{
    Quit (name = "FHIR Receiver") || (name = "FHIR Out")
}

/// Records the server and places the four items in Shutter's production. An empty port is the instance's own web
/// port. Answers {"ok", "added", "updated", "warnings", "error"}: added counts the items that were missing, updated
/// the items whose server settings were rewritten.
ClassMethod PlaceItems(host As %String = "127.0.0.1", port As %String = "", credential As %String = "", ssl As %String = "") As %DynamicObject
{
    Set out = {"added": 0, "updated": 0, "warnings": [], "error": ""}
    Do out.%Set("ok", 0, "boolean")
    Try {
        Set host = $ZSTRIP($TRANSLATE($GET(host), $CHAR(0)), "<>W"), port = $ZSTRIP($TRANSLATE($GET(port), $CHAR(0)), "<>W"), credential = $ZSTRIP($TRANSLATE($GET(credential), $CHAR(0)), "<>W"), ssl = $ZSTRIP($TRANSLATE($GET(ssl), $CHAR(0)), "<>W")
        If host = "" Set host = "127.0.0.1"
        If port = "" Set port = ##class(Shutter.Util.Onboard).WebPort()
        If (port '? 1.5N) || (+port < 1) || (+port > 65535) Set out.error = "The port must be a number from 1 to 65535. Nothing was changed" Quit
        // An item of a class that is not here would stop the production's update half way: asked before any change.
        Set names = $PARAMETER("Shutter.FHIR.Profile", "ITEMS"), absent = ""
        For n = 1:1:$LENGTH(names, ",") {
            Set class = ..ItemClass($PIECE(names, ",", n))
            If '##class(%Dictionary.CompiledClass).%ExistsId(class) Set absent = absent _ $SELECT(absent = "": "", 1: ", ") _ class
        }
        If absent '= "" Set out.error = "This install has no compiled class " _ absent _ ". Nothing was changed" Quit
        Set ^Shutter.Config("fhirItems") = $LISTBUILD(host, +port, credential, ssl)
        Set sc = ..Apply("", .added, .updated)
        Set out.added = added, out.updated = updated
        // The record stays: what was saved of the definition follows it, and the next call or load finishes the rest.
        If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc) _ ". The server is on record, so the next call or load tries again" Quit
        If credential = "" {
            Do out.warnings.%Push("No credential named: the server is called with no login")
        } ElseIf '##class(Ens.Config.Credentials).%ExistsId(credential) {
            Do out.warnings.%Push("No credential " _ credential _ " in " _ $NAMESPACE _ ": set it (Ens.Config.Credentials.SetCredential), or the server cannot be read")
        }
        If ..Receivers().%Size() = 0 Do out.warnings.%Push("The site profile has no receiver entry with a fhir block yet: the items have nothing to do until it has one")
        Set problem = ..Problem()
        If problem '= "" Do out.warnings.%Push(problem)
        Do out.%Set("ok", 1, "boolean")
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out
}

/// The recorded items put into the production (Shutter's own by default) when it lacks them, and the server settings
/// of FHIR Receiver and FHIR Out rewritten from the record when the two are there already. Nothing without the
/// record. The install runs this after it compiled the production.
ClassMethod RestoreItems(Output added As %Integer, production As %String = "") As %Status
{
    Quit ..Apply(production, .added, .updated)
}

/// RestoreItems, which also counts the items whose server settings changed.
ClassMethod Apply(production As %String, Output added As %Integer, Output updated As %Integer) As %Status [ Private ]
{
    Set sc = $$$OK, added = 0, updated = 0
    Try {
        Quit:$DATA(^Shutter.Config("fhirItems"), was)=0
        If production = "" Set production = ##class(Shutter.Setup).ProductionName()
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        If '$ISOBJECT(prod) Set sc = $$$ERROR($$$GeneralError, "No production " _ production) Quit
        For n = 1:1:$LISTLENGTH($LISTFROMSTRING(..#ENDPOINT)) Set value($PIECE(..#ENDPOINT, ",", n)) = $LISTGET(was, n)
        For i = 1:1:prod.Items.Count() Set have(prod.Items.GetAt(i).Name) = i
        Set names = $PARAMETER("Shutter.FHIR.Profile", "ITEMS")
        For n = 1:1:$LENGTH(names, ",") {
            Set name = $PIECE(names, ",", n)
            If '$DATA(have(name)) {
                Set new = ##class(Ens.Config.Item).%New()
                Set new.Name = name, new.ClassName = ..ItemClass(name), new.PoolSize = 1, new.Enabled = 1, new.Category = "Recovery", new.Production = prod
                If ..CallsTheServer(name) {
                    For set = $LISTBUILD("Adapter", "HTTPServer", value("HTTPServer")), $LISTBUILD("Adapter", "HTTPPort", value("HTTPPort")), $LISTBUILD("Adapter", "Credentials", value("Credentials")), $LISTBUILD("Adapter", "SSLConfig", value("SSLConfig")), $LISTBUILD("Adapter", "ResponseTimeout", "15"), $LISTBUILD("Adapter", "ConnectTimeout", "5"), $LISTBUILD("Host", "FailureTimeout", "0") {
                        Continue:($LIST(set, 3) = "")
                        Do new.Settings.Insert(..Setting($LIST(set, 1), $LIST(set, 2), $LIST(set, 3)))
                    }
                }
                Do prod.Items.Insert(new)
                Set added = added + 1
                Continue
            }
            Continue:'..CallsTheServer(name)
            Set item = prod.Items.GetAt(have(name))
            // A site's own item under one of the names, on its own class, is the site's: not rewritten.
            Continue:item.ClassName'=..ItemClass(name)
            Set changed = 0
            For s = 1:1:$LENGTH(..#ENDPOINT, ",") {
                Set setting = $PIECE(..#ENDPOINT, ",", s), found = 0
                For j = item.Settings.Count():-1:1 {
                    Set one = item.Settings.GetAt(j)
                    Continue:(one.Target'="Adapter")||(one.Name'=setting)
                    If 'found && (one.Value = value(setting)) && (value(setting) '= "") Set found = 1 Continue
                    // Another value, an empty one, or a second row of the same setting: the row goes.
                    Do item.Settings.RemoveAt(j)
                    Set changed = 1
                }
                If 'found && (value(setting) '= "") Do item.Settings.Insert(..Setting("Adapter", setting, value(setting))) Set changed = 1
            }
            If changed Set updated = updated + 1
        }
        Quit:(added+updated)=0
        Set sc = ..Saved(prod, production)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

ClassMethod Setting(target As %String, name As %String, value As %String) As Ens.Config.Setting [ Private ]
{
    Set s = ##class(Ens.Config.Setting).%New()
    Set s.Target = target, s.Name = name, s.Value = value
    Quit s
}

/// The changed definition saved, written to its class, and applied when that production is the one running.
ClassMethod Saved(prod As Ens.Config.Production, production As %String) As %Status [ Private ]
{
    Set sc = prod.%Save() Quit:$$$ISERR(sc) sc
    Set sc = prod.SaveToClass() Quit:$$$ISERR(sc) sc
    Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state) Quit:$$$ISERR(sc) sc
    If ($GET(running) = production) && ($GET(state) = 1) Set sc = ##class(Ens.Director).UpdateProduction(30, 0)
    Quit sc
}

/// What the production holds of the four: items(name) = $LISTBUILD(enabled, class) and items(name, setting) = the
/// value of each of the four server settings. Answers 0 when there is no such production.
ClassMethod Read(production As %String, Output items) As %Boolean [ Private ]
{
    Kill items
    Set prod = ##class(Ens.Config.Production).%OpenId(production, 0)
    Quit:'$ISOBJECT(prod) 0
    For i = 1:1:prod.Items.Count() {
        Set item = prod.Items.GetAt(i)
        Continue:..ItemClass(item.Name)=""
        Continue:$DATA(items(item.Name))
        Set items(item.Name) = $LISTBUILD(''item.Enabled, item.ClassName)
        For j = 1:1:item.Settings.Count() {
            Set one = item.Settings.GetAt(j)
            If (one.Target = "Adapter") && ((("," _ ..#ENDPOINT _ ",")) [ ("," _ one.Name _ ",")) Set items(item.Name, one.Name) = one.Value
        }
    }
    Quit 1
}

/// Whether FHIR Receiver and FHIR Out are both there and name the same server, port, TLS configuration and credential.
ClassMethod SameServer(ByRef items) As %Boolean [ Private ]
{
    If '$DATA(items("FHIR Receiver")) || '$DATA(items("FHIR Out")) Quit 0
    For s = 1:1:$LENGTH(..#ENDPOINT, ",") {
        Set setting = $PIECE(..#ENDPOINT, ",", s)
        Set a = $GET(items("FHIR Receiver", setting)), b = $GET(items("FHIR Out", setting))
        If setting = "HTTPPort" Set a = +a, b = +b
        If a '= b Return 0
    }
    Quit 1
}

/// "" when all four items are in the production (Shutter's own by default), on their classes and enabled, and FHIR
/// Receiver and FHIR Out name the same server; else a sentence naming what is missing or disabled, or "FHIR Receiver
/// and FHIR Out name different servers".
ClassMethod Problem(production As %String = "") As %String
{
    Set out = ""
    Try {
        If production = "" Set production = ##class(Shutter.Setup).ProductionName()
        If '..Read(production, .items) Set out = "No production " _ production Quit
        Set names = $PARAMETER("Shutter.FHIR.Profile", "ITEMS"), missing = "", disabled = "", other = ""
        For n = 1:1:$LENGTH(names, ",") {
            Set name = $PIECE(names, ",", n)
            If '$DATA(items(name), row) Set missing = missing _ $SELECT(missing = "": "", 1: ", ") _ name Continue
            If $LIST(row, 2) '= ..ItemClass(name) Set other = other _ $SELECT(other = "": "", 1: ", ") _ name _ " (" _ $LIST(row, 2) _ ")" Continue
            If '$LIST(row, 1) Set disabled = disabled _ $SELECT(disabled = "": "", 1: ", ") _ name
        }
        If missing '= "" Set out = "Missing from " _ production _ ": " _ missing
        If other '= "" Set out = out _ $SELECT(out = "": "", 1: ". ") _ "Not on Shutter's class: " _ other
        If disabled '= "" Set out = out _ $SELECT(out = "": "", 1: ". ") _ "Disabled: " _ disabled
        If $DATA(items("FHIR Receiver")) && $DATA(items("FHIR Out")) && '..SameServer(.items) Set out = out _ $SELECT(out = "": "", 1: ". ") _ "FHIR Receiver and FHIR Out name different servers"
    } Catch ex {
        Set out = "The FHIR items could not be read: " _ ex.DisplayString()
    }
    Quit out
}

/// Takes the four items out of the production (Shutter's own by default): only an item on Shutter's class for its
/// name, so a site's own item under one of the names stays. From Shutter's own production the record goes too, so
/// the next load does not place them again.
ClassMethod RemoveItems(production As %String = "") As %Status
{
    Set sc = $$$OK
    Try {
        Set own = ##class(Shutter.Setup).ProductionName()
        If production = "" Set production = own
        If production = own Kill ^Shutter.Config("fhirItems")
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        Quit:'$ISOBJECT(prod)
        Set taken = 0
        For i = prod.Items.Count():-1:1 {
            Set item = prod.Items.GetAt(i)
            Continue:(..ItemClass(item.Name)="")||(item.ClassName'=..ItemClass(item.Name))
            Set id = item.%Id()
            Do prod.Items.RemoveAt(i)
            If id '= "" Do ##class(Ens.Config.Item).%DeleteId(id)
            Set taken = taken + 1
        }
        Quit:taken=0
        Set sc = ..Saved(prod, production)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Empties the three stores that hang on a case, for the demo's whole-store purge. The proof of a receiver is not a
/// case's and stays.
ClassMethod KillStores()
{
    For cls = "Shutter.Store.FHIRAttempt", "Shutter.Store.FHIRSealedRead", "Shutter.Store.FHIRBinding" {
        Try {
            If ##class(%Dictionary.CompiledClass).%ExistsId(cls) Do $CLASSMETHOD(cls, "%KillExtent")
        } Catch ex {
        }
    }
}

/// The names of the stored profile's receiver entries that have a fhir block.
ClassMethod Receivers() As %DynamicArray [ Private ]
{
    Set out = []
    Set list = ##class(Shutter.Store.SiteProfile).Current().%Get("receivers")
    Quit:'$ISOBJECT(list) out
    Set li = list.%GetIterator()
    While li.%GetNext(, .r) {
        Continue:'$ISOBJECT(r)
        If $ISOBJECT(r.%Get("fhir")) Do out.%Push(##class(Shutter.Util.Json).Str(r, "name"))
    }
    Quit out
}

/// The software the server last named of itself, as the newest case of the receiver holds it in its current evidence
/// (summary.fhir.capability.software); both "" when no read of the server's statement is on record.
ClassMethod LastSoftware(receiver As %String, Output name As %String, Output version As %String) [ Private ]
{
    Set name = "", version = ""
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 CurrentSnapshot->Summary AS Summary FROM Shutter_Store.""Case"" WHERE Receiver = ? AND CurrentSnapshot IS NOT NULL ORDER BY ID DESC", receiver)
        Quit:'rs.%Next()
        Set summary = ##class(Shutter.Util.Json).Parse(rs.%Get("Summary"), .sc)
        Quit:$$$ISERR(sc)||'$ISOBJECT(summary)
        Set fhir = summary.%Get("fhir") Quit:'$ISOBJECT(fhir)
        Set capability = fhir.%Get("capability") Quit:'$ISOBJECT(capability)
        Set software = capability.%Get("software") Quit:'$ISOBJECT(software)
        Set name = ##class(Shutter.Util.Json).Str(software, "name"), version = ##class(Shutter.Util.Json).Str(software, "version")
    } Catch ex {
        Set name = "", version = ""
    }
}

/// One word for a receiver's recorded conformance run: "none" with no run on record; "other_software" when the server
/// has since named software that is not the software measured; else "matches". With no read of the server on record,
/// "matches" says only that a run is on record: the gate compares it with the server's own statement at every decision.
ClassMethod ProofWord(proof As Shutter.Store.FHIRProof, softwareName As %String, softwareVersion As %String) As %String
{
    If '$ISOBJECT(proof) Quit "none"
    If (softwareName = "") && (softwareVersion = "") Quit "matches"
    Quit $SELECT(proof.Matches(softwareName, softwareVersion): "matches", 1: "other_software")
}

/// The FHIR part of the Doctor. {"receivers": []} when the stored profile has no entry with a fhir block; else
/// {"policy_version", "items_problem", "endpoints_agree", "receivers": [{"receiver", "recovery_enabled", "proof",
/// "proof_measured_at", "credential"}]}. It reads what is stored and calls no server.
ClassMethod Doctor() As %DynamicObject
{
    Set r = {"receivers": []}
    Try {
        Set names = ..Receivers()
        Quit:names.%Size()=0
        Set production = ##class(Shutter.Setup).ProductionName()
        Set r = {}
        Set r."policy_version" = $PARAMETER("Shutter.FHIR.Profile", "POLICYVERSION")
        Set r."items_problem" = ..Problem(production)
        Set agree = ..Read(production, .items) && ..SameServer(.items)
        Do r.%Set("endpoints_agree", agree, "boolean")
        // The credential the reader is set to use; before the items are placed, the one on record.
        Set credential = $SELECT($DATA(items("FHIR Receiver")): $GET(items("FHIR Receiver", "Credentials")), 1: $LISTGET($GET(^Shutter.Config("fhirItems")), 3))
        Set r.receivers = []
        Set ni = names.%GetIterator()
        While ni.%GetNext(, .name) {
            Set row = {"receiver": (name)}
            Do row.%Set("recovery_enabled", ##class(Shutter.FHIR.Profile).Enabled(name), "boolean")
            Set proof = ##class(Shutter.Store.FHIRProof).For(name)
            Do ..LastSoftware(name, .softwareName, .softwareVersion)
            Set row.proof = ..ProofWord(proof, softwareName, softwareVersion)
            Set row."proof_measured_at" = $SELECT($ISOBJECT(proof): proof.MeasuredAt, 1: "")
            Do row.%Set("credential", (credential '= "") && ##class(Ens.Config.Credentials).%ExistsId(credential), "boolean")
            Do r.receivers.%Push(row)
        }
    } Catch ex {
        Set r = {"receivers": [], "error": (ex.DisplayString())}
    }
    Quit r
}

}
