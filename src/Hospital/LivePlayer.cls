/// The live hospital's PAS (CONTRACTS 4.4, v1.34): a service of the HOSPITAL production, on when the install was told
/// `live`, that plays one of Shutter's scenarios every EveryMinutes with fresh patients at present times, applying the
/// scenario's faults to the receivers so the errors are real, and between stories sends one ordinary message a minute so
/// the feed looks like a working hospital. It writes the messages into the hospital's own inbound folder, where PAS In
/// picks them up: the path a real hospital has. It never resets anything, and it records what it played for the Doctor and
/// the web app's banner (^Hospital.Live("status")). The text work is Shutter.Util.LiveFeed's, which the unit tests cover.
Class Hospital.LivePlayer Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Property Adapter As Ens.InboundAdapter;

/// Minutes between stories.
Property EveryMinutes As %Integer [ InitialExpression = 7 ];

/// The scenarios, in order, round robin; empty means every scenario of fixtures/scenarios.json but S13, S20 and S21.
Property Scenarios As %String(MAXLEN = 500) [ InitialExpression = "S2,S8,S1,S23a,S3,S24,S15,S11" ];

/// Whether the scenarios' fault steps are applied to the receivers (the errors are then real).
Property Faults As %Boolean [ InitialExpression = 1 ];

/// Whether one ordinary message goes out every task between stories.
Property OrdinaryFeed As %Boolean [ InitialExpression = 1 ];

/// The longest pause a scenario's wait step is given, in seconds.
Property MaxWait As %Integer [ InitialExpression = 30 ];

/// Shutter's namespace: the fixtures' root and the receivers' faults are there.
Property ShutterNamespace As %String(MAXLEN = 64) [ InitialExpression = "SHUTTER" ];

Parameter SETTINGS = "EveryMinutes:Live,Scenarios:Live,Faults:Live,OrdinaryFeed:Live,MaxWait:Live,ShutterNamespace:Live";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    If '$GET(^Hospital.Config("live")) Quit $$$OK
    Set now = $PIECE($HOROLOG, ",", 1) * 86400 + $PIECE($HOROLOG, ",", 2)
    Set last = +$GET(^Hospital.Live("last_story_at"))
    If (now - last) >= (..EveryMinutes * 60) {
        Set sc = ..PlayNext()
        If $$$ISERR(sc) $$$LOGWARNING("The live story failed: " _ $SYSTEM.Status.GetErrorText(sc))
    } ElseIf ..OrdinaryFeed {
        Set sc = ..Ordinary()
        If $$$ISERR(sc) $$$LOGWARNING("The ordinary message failed: " _ $SYSTEM.Status.GetErrorText(sc))
    }
    Do ..WriteStatus()
    Quit $$$OK
}

/// The scenario list as the setting says, or every playable scenario of the file.
Method ScenarioList() As %List
{
    Set list = ""
    For i = 1:1:$LENGTH(..Scenarios, ",") { Set s = $ZSTRIP($PIECE(..Scenarios, ",", i), "<>W") If s '= "" Set list = list _ $LISTBUILD(s) }
    If list '= "" Quit list
    Set all = ..ScenariosFile()
    If '$ISOBJECT(all) Quit ""
    Set ai = all.%GetIterator()
    While ai.%GetNext(, .s) { Set id = s.%Get("id") If (id '= "") && '$LISTFIND($LISTBUILD("S13", "S20", "S21"), id) Set list = list _ $LISTBUILD(id) }
    Quit list
}

Method Root() As %String
{
    Set ns = ..ShutterNamespace
    Quit $GET(^|ns|Shutter.Config("root"))
}

Method ScenariosFile() As %DynamicArray
{
    Set path = ..Root() _ "fixtures/scenarios.json"
    If '##class(%File).Exists(path) Quit ""
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set stream.TranslateTable = "UTF8"
    Quit:$$$ISERR(stream.LinkToFile(path)) ""
    Quit ##class(%DynamicArray).%FromJSON(stream)
}

/// The next story of the rotation.
Method PlayNext() As %Status
{
    Set list = ..ScenarioList()
    If list = "" Quit $$$ERROR($$$GeneralError, "No scenario to play")
    Set n = $INCREMENT(^Hospital.Live("plays"))
    Set id = $LIST(list, 1 + ((n - 1) # $LISTLENGTH(list)))
    Set ^Hospital.Live("last_story_at") = $PIECE($HOROLOG, ",", 1) * 86400 + $PIECE($HOROLOG, ",", 2)
    Set ^Hospital.Live("next") = $LIST(list, 1 + (n # $LISTLENGTH(list)))
    Quit ..Play(id, n)
}

/// One scenario: its steps read from the file, its messages rewritten for fresh patients at present times and dropped into
/// the hospital's inbound folder in order, its waits paused for, its faults applied to the receivers in Shutter's namespace,
/// every fault turned off at the end whatever happened.
Method Play(id As %String, n As %Integer) As %Status
{
    Set all = ..ScenariosFile()
    If '$ISOBJECT(all) Quit $$$ERROR($$$GeneralError, "fixtures/scenarios.json is not readable under " _ ..Root())
    Set scenario = "", ai = all.%GetIterator()
    While ai.%GetNext(, .s) { If s.%Get("id") = id Set scenario = s Quit }
    If '$ISOBJECT(scenario) Quit $$$ERROR($$$GeneralError, "No scenario " _ id _ " in the file")
    Set folder = $GET(^Hospital.Config("dir", "in"))
    If folder = "" Quit $$$ERROR($$$GeneralError, "The hospital's inbound folder is not recorded")
    // Every message first, so the patients and the span are known before anything goes out.
    Set texts = [], steps = scenario.%Get("steps"), si = steps.%GetIterator()
    While si.%GetNext(, .step) {
        Continue:'step.%IsDefined("file")
        Set text = ..ReadFile(..Root() _ "fixtures/" _ id _ "/" _ step.%Get("file"))
        Do texts.%Push(text)
    }
    Set map = ##class(Shutter.Util.LiveFeed).MapPatients(texts), zone = ..LiveZone()
    Set delta = ##class(Shutter.Util.LiveFeed).DeltaFor(texts, ##class(Shutter.Util.LiveFeed).LocalNow(zone))
    // A room of this play's own: the stories' patients are never discharged, so a repeated room would find its bed taken.
    Set room = "BAY" _ (100 + n), used = "", k = 0, sc = $$$OK
    // Cases opened while the story plays carry its scenario id, as the scenario runner's do (Shutter.Store.Case reads the
    // stamp when a case opens); the ordinary feed clears it a minute later, so a case of an ordinary message carries none.
    Do ..Stamp(id)
    Try {
        Set si = steps.%GetIterator(), t = 0
        While si.%GetNext(, .step) {
            If step.%IsDefined("file") {
                Set k = k + 1, t = t + 1
                Set text = ##class(Shutter.Util.LiveFeed).Rewrite(texts.%Get(t - 1), map, delta, room, "LIVE" _ n _ "-" _ $TRANSLATE($JUSTIFY(k, 2), " ", "0"))
                Set path = folder _ "live-" _ $TRANSLATE($JUSTIFY(n, 5), " ", "0") _ "-" _ $TRANSLATE($JUSTIFY(k, 2), " ", "0") _ ".hl7"
                Do ..WriteFile(path, text)
                // The next step (a fault, above all) must not land before this message has been delivered: wait until PAS
                // In has taken the file (it moves it to the archive), then a moment for the delivery, as the scenario runner
                // does; a file still there after 15 s is left to the production and the story goes on.
                Set deadline = $ZHOROLOG + 15
                While ##class(%File).Exists(path) && ($ZHOROLOG < deadline) { Hang 0.2 }
                Hang 1.5
            } ElseIf step.%IsDefined("wait") {
                Hang $SELECT(+step.%Get("wait") > ..MaxWait: ..MaxWait, 1: +step.%Get("wait"))
            } ElseIf step.%IsDefined("fault") && ..Faults {
                Set request = ##class(%DynamicObject).%FromJSON(step.%ToJSON())
                Do request.%Remove("receivers"), request.%Remove("expect")
                Set request.mode = step.%Get("fault")
                Do request.%Remove("fault")
                If request.%IsDefined("operation_key") Set request."operation_key" = ##class(Shutter.Util.LiveFeed).RewriteKey(request."operation_key", map, delta, texts, "Europe/London", zone)
                Set receivers = step.%Get("receivers")
                If '$ISOBJECT(receivers) Set receivers = ["Downstream Out"]
                Set ri = receivers.%GetIterator()
                While ri.%GetNext(, .name) {
                    Do ..Fault(name, request)
                    If '$LISTFIND(used, name) Set used = used _ $LISTBUILD(name)
                }
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    // Whatever happened, no fault outlives its story.
    For i = 1:1:$LISTLENGTH(used) { Do ..Fault($LIST(used, i), {"mode": "off"}) }
    Set played = {}
    Set played.scenario = id, played.title = scenario.%Get("title"), played.at = ##class(Shutter.Util.Time).NowUTC(), played.n = n
    Set patients = [], pi = map.patients.%GetIterator()
    While pi.%GetNext(, .p) { Do patients.%Push(p.mrn _ " " _ p.given _ " " _ p.family) }
    Set played.patients = patients, played.messages = k
    If $$$ISERR(sc) Set played.error = $SYSTEM.Status.GetErrorText(sc)
    Set ^Hospital.Live("played", n) = played.%ToJSON()
    $$$TRACE("Live story " _ n _ ": " _ id _ " with " _ k _ " message(s) for " _ patients.%Size() _ " patient(s)" _ $SELECT($$$ISERR(sc): "; failed: " _ $SYSTEM.Status.GetErrorText(sc), 1: ""))
    Quit sc
}

/// The scenario stamp new cases take in Shutter's namespace (the scenario runner's own; "" for none).
Method Stamp(id As %String)
{
    Set ns = ..ShutterNamespace
    Set ^|ns|Shutter.Config("scenario") = id
}

/// The feed's zone: the copy of Shutter's profile zone the hospital install keeps here, else Shutter's own ("" is UTC).
Method LiveZone() As %String
{
    Set zone = $GET(^Shutter.Config("feedZone"))
    If zone '= "" Quit zone
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ..ShutterNamespace
        Set zone = ##class(Shutter.Store.SiteProfile).FeedTimeZone()
    } Catch ex {
    }
    Quit zone
}

/// A receiver's fault, applied in Shutter's namespace through the scenario runner's own helper.
Method Fault(receiver As %String, request As %DynamicObject)
{
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ..ShutterNamespace
        Set answer = ##class(Shutter.Scenarios.Runner).InReceiver(receiver, "SetFault", request, .status)
        If status '= 200 $$$LOGWARNING("The receiver " _ receiver _ " refused the fault " _ request.%ToJSON() _ ": HTTP " _ status)
    } Catch ex {
        $$$LOGWARNING("The fault on " _ receiver _ " could not be set: " _ ex.DisplayString())
    }
}

/// One ordinary message into the inbound folder.
Method Ordinary() As %Status
{
    Set folder = $GET(^Hospital.Config("dir", "in"))
    If folder = "" Quit $$$ERROR($$$GeneralError, "The hospital's inbound folder is not recorded")
    Set n = $INCREMENT(^Hospital.Live("ordinary"))
    Do ..Stamp("")
    Set text = ##class(Shutter.Util.LiveFeed).Ordinary("LIVEO-" _ n, .kind, 24, ..LiveZone())
    Do ..WriteFile(folder _ "live-o" _ $TRANSLATE($JUSTIFY(n, 6), " ", "0") _ ".hl7", text)
    Set ^Hospital.Live("last_ordinary") = kind _ " at " _ ##class(Shutter.Util.Time).NowUTC()
    Quit $$$OK
}

ClassMethod ReadFile(path As %String) As %String
{
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set stream.TranslateTable = "UTF8"
    If $$$ISERR(stream.LinkToFile(path)) Quit ""
    Set text = ""
    While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    Quit text
}

ClassMethod WriteFile(path As %String, text As %String)
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.TranslateTable = "UTF8"
    Do f.LinkToFile(path _ ".part")
    Do f.Write(text)
    Do f.%Save()
    Do ##class(%File).Rename(path _ ".part", path)
}

/// The status the Doctor and the web app read: {enabled, every_minutes, scenarios, last_played, next, last_ordinary}.
Method WriteStatus()
{
    Set s = {}
    Do s.%Set("enabled", ''$GET(^Hospital.Config("live")), "boolean")
    Set s."every_minutes" = ..EveryMinutes, s.scenarios = $LISTTOSTRING(..ScenarioList(), ",")
    Set n = +$GET(^Hospital.Live("plays"))
    If n > 0 Set s."last_played" = ##class(%DynamicObject).%FromJSON($GET(^Hospital.Live("played", n), "{}"))
    Set lastAt = +$GET(^Hospital.Live("last_story_at"))
    If lastAt > 0 {
        Set due = lastAt + (..EveryMinutes * 60)
        Set s.next = {}
        Set s.next.scenario = $GET(^Hospital.Live("next")), s.next.at = $ZDATE(due \ 86400, 3) _ "T" _ $ZTIME(due # 86400, 1) _ "Z"
    }
    Set s."last_ordinary" = $GET(^Hospital.Live("last_ordinary"))
    Set ^Hospital.Live("status") = s.%ToJSON()
}

}
