/// The live hospital's PAS (CONTRACTS 4.4, v1.34): a service of the HOSPITAL production, on when the install was told
/// `live`, that plays one of Shutter's scenarios every EveryMinutes with fresh patients at present times, applying the
/// scenario's faults to the receivers so the errors are real, and between stories sends one ordinary message a minute so
/// the feed looks like a working hospital. It writes the messages into the hospital's own inbound folder, where PAS In
/// picks them up: the path a real hospital has. It never resets anything, and it records what it played for the Doctor and
/// the web app's banner (^Hospital.Live("status")). The text work is Shutter.Util.LiveFeed's, which the unit tests cover.
/// While a story plays, ^Hospital.Live("playing") holds its id and start (the scenario runner's reset leaves the bed map
/// alone then), and ^Hospital.Live("faulted", receiver) the receivers it faulted, so that a job cut off mid-story (a
/// production restart, SetLive(0)) leaves no fault behind: the next job's OnInit turns them off.
Class Hospital.LivePlayer Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Property Adapter As Ens.InboundAdapter;

/// Minutes between stories.
Property EveryMinutes As %Integer [ InitialExpression = 7 ];

/// The rotation as shipped (v1.38): S11, the incident, is out of it, since its board chain would convene a board every
/// round; the storm shows an incident on demand, and S11 can still be run as a scenario.
Parameter DEFAULTSCENARIOS = "S2,S8,S1,S23a,S3,S24,S15";

/// The scenarios, in order, round robin; empty means every scenario of fixtures/scenarios.json but S13, S20 and S21. The
/// build's SHUTTER_LIVE_SCENARIOS (Shutter.Setup.ApplyEnvironment into ^Hospital.Config("liveScenarios")) overrides it.
Property Scenarios As %String(MAXLEN = 500) [ InitialExpression = {..#DEFAULTSCENARIOS} ];

/// Whether the scenarios' fault steps are applied to the receivers (the errors are then real).
Property Faults As %Boolean [ InitialExpression = 1 ];

/// Whether one ordinary message goes out every task between stories.
Property OrdinaryFeed As %Boolean [ InitialExpression = 1 ];

/// The longest pause a scenario's wait step is given, in seconds.
Property MaxWait As %Integer [ InitialExpression = 30 ];

/// Shutter's namespace: the fixtures' root and the receivers' faults are there.
Property ShutterNamespace As %String(MAXLEN = 64) [ InitialExpression = "SHUTTER" ];

/// Seconds between ordinary messages (the adapter calls every 5 s since v1.35, so that a storm is picked up quickly).
Property OrdinaryEverySeconds As %Integer [ InitialExpression = 60 ];

/// How long the storm keeps the receiver down, in seconds (v1.35; CONTRACTS 4.4).
Property StormReceiverDownSeconds As %Integer [ InitialExpression = {..#STORMDOWNSECONDS} ];

/// The storm's receiver outage, as the route announces it.
Parameter STORMDOWNSECONDS = 60;

/// The storm's whole span: done at the latest this many minutes after the press.
Parameter STORMMINUTES = 10;

Parameter SETTINGS = "EveryMinutes:Live,Scenarios:Live,Faults:Live,OrdinaryFeed:Live,OrdinaryEverySeconds:Live,MaxWait:Live,ShutterNamespace:Live,StormReceiverDownSeconds:Live";

/// A story the last job was playing when it stopped left its faults on the receivers (they are persistent in Shutter's
/// namespace, and Play turns them off only at its end) and its playing mark set: both go when the next job starts. The
/// storm's own fault is not touched while its record says sending or waiting_receiver (StormWatch turns it off at
/// receiverDownUntil).
Method OnInit() As %Status
{
    Set cleared = ..ClearFaultsLeft(..ShutterNamespace)
    If cleared '= "" $$$LOGINFO("A story was cut off: the fault(s) it left on " _ cleared _ " turned off")
    Kill ^Hospital.Live("playing")
    Quit $$$OK
}

/// Turns off the faults a story left in ^Hospital.Live("faulted", receiver), in Shutter's namespace, and forgets them;
/// returns the receivers cleared, comma separated ("" for none). Left as they are while a storm is sending or waiting for
/// its receiver: its outage is meant to last until receiverDownUntil.
ClassMethod ClearFaultsLeft(shutterNs As %String = "SHUTTER") As %String
{
    Set state = ..StormState(.json)
    If (state = "sending") || (state = "waiting_receiver") Quit ""
    Set cleared = "", name = ""
    For {
        Set name = $ORDER(^Hospital.Live("faulted", name))
        Quit:name=""
        Do ..FaultOff(name, shutterNs)
        Set cleared = cleared _ $SELECT(cleared = "": "", 1: ",") _ name
    }
    Kill ^Hospital.Live("faulted")
    Quit cleared
}

/// A receiver's fault turned off in Shutter's namespace, in a method of its own so that the namespace is back on return (a
/// New $NAMESPACE lasts to the end of the method, not of the block).
ClassMethod FaultOff(receiver As %String, shutterNs As %String)
{
    Try {
        New $NAMESPACE
        Set $NAMESPACE = shutterNs
        Do ##class(Shutter.Scenarios.Runner).InReceiver(receiver, "SetFault", {"mode": "off"}, .status)
    } Catch ex {
    }
}

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    If '$GET(^Hospital.Config("live")) Quit $$$OK
    // Shutter's production starts beside this one, and on the first start with SHUTTER_LIVE its OnStart switches this item
    // on before its own items are up. A story played then fails, Shutter's intake answers 503 and logs the service as not
    // registered, and that failure never becomes a case. So nothing plays until Shutter can hear it.
    If '..ShutterListening(..ShutterNamespace) {
        $$$TRACE("Waiting for Shutter's production to take messages")
        Quit $$$OK
    }
    Set now = ##class(Shutter.Util.Time).EpochSeconds()
    // The storm first (v1.35): a press is picked up within one call, and nothing else plays under it; the rotation and the
    // ordinary feed wait until it is done.
    Set storm = ..StormState(.json)
    If ..StormPickup() Set storm = "requested"
    If storm = "requested" {
        Set sc = ..PlayStorm()
        If $$$ISERR(sc) $$$LOGWARNING("The storm failed: " _ $SYSTEM.Status.GetErrorText(sc))
        Do ..WriteStatus()
        Quit $$$OK
    }
    If (storm '= "") && (storm '= "done") && (storm '= "failed") {
        Do ..StormWatch()
        Do ..WriteStatus()
        Quit $$$OK
    }
    Set last = +$GET(^Hospital.Live("last_story_at"))
    If (now - last) >= (..EveryMinutes * 60) {
        Set sc = ..PlayNext()
        If $$$ISERR(sc) $$$LOGWARNING("The live story failed: " _ $SYSTEM.Status.GetErrorText(sc))
    } ElseIf ..OrdinaryFeed && ((now - +$GET(^Hospital.Live("last_ordinary_at"))) >= ..OrdinaryEverySeconds) {
        Set ^Hospital.Live("last_ordinary_at") = now
        Set sc = ..Ordinary()
        If $$$ISERR(sc) $$$LOGWARNING("The ordinary message failed: " _ $SYSTEM.Status.GetErrorText(sc))
    }
    Do ..WriteStatus()
    Quit $$$OK
}

/// Whether Shutter's API service is registered in its namespace: what Ens.Director.CreateBusinessService reads before it
/// logs ErrBusinessDispatchNameNotRegistered, and what the intake needs to take a failure.
ClassMethod ShutterListening(shutterNs As %String = "SHUTTER") As %Boolean
{
    Set listening = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = shutterNs
        Set listening = ($GET($$$DispatchNameToConfigName("Shutter API")) '= "")
    } Catch ex {
    }
    Quit listening
}

/// The storm's state ("" when none has ever been pressed) and its record.
ClassMethod StormState(Output json As %DynamicObject) As %String
{
    Set json = ""
    Set text = $GET(^Hospital.Live("storm"))
    If text = "" Quit ""
    Try { Set json = ##class(%DynamicObject).%FromJSON(text) } Catch ex { Set json = "" }
    If '$ISOBJECT(json) Quit ""
    Quit json.%Get("state")
}

ClassMethod StormSave(json As %DynamicObject)
{
    Set ^Hospital.Live("storm") = json.%ToJSON()
}

/// A press waiting in Shutter's namespace (the route writes ^Shutter.Live("storm","request") there, since the API's users
/// write nothing in this database) becomes this namespace's record, state requested; true when one was taken.
Method StormPickup() As %Boolean
{
    Set ns = ..ShutterNamespace
    Set text = $GET(^|ns|Shutter.Live("storm", "request"))
    If text = "" Quit 0
    Set ^Hospital.Live("storm") = text
    Kill ^|ns|Shutter.Live("storm", "request")
    $$$TRACE("Storm requested: " _ text)
    Quit 1
}

/// The storm's plan (CONTRACTS 4.4, v1.35): four fresh patients, each admitted to a free bed and then moved to another
/// ward; eight movements, admissions first, control ids STORM<n>-01 to -08. The beds are taken as the ordinary feed takes
/// them, so the storm never collides with a story that is playing, and the ordinary feed knows the patients afterwards.
/// The texts are written at send time (PlayStorm), so each movement carries the time it went out.
ClassMethod StormPlan(n As %Integer, zone As %String = "") As %DynamicObject
{
    Set now = ##class(Shutter.Util.LiveFeed).LocalNow(zone)
    Set plan = {"patients": [], "movements": []}
    Set k = 0
    For i = 1:1:4 {
        Set p = ##class(Shutter.Util.LiveFeed).NewPatient(), bed = ##class(Shutter.Util.LiveFeed).FreeBed()
        Set ward = $LIST(bed, 1), room = $LIST(bed, 2), bedNo = $LIST(bed, 3)
        Set ^Hospital.Live("adm", p.mrn) = $LISTBUILD(p.enc, ward, room, bedNo, now)
        Set ^Hospital.Live("bed", ward, room, bedNo) = p.mrn
        If '$DATA(^Hospital.Live("patient", p.mrn)) Set ^Hospital.Live("patient", p.mrn) = p.%ToJSON()
        Set k = k + 1
        Do plan.movements.%Push({"control": ("STORM" _ n _ "-" _ $TRANSLATE($JUSTIFY(k, 2), " ", "0")), "event": "admit", "mrn": (p.mrn), "encounterId": (p.enc), "ward": (ward), "room": (room), "bed": (bedNo), "prior": ""})
        Do plan.patients.%Push({"mrn": (p.mrn), "encounterId": (p.enc), "ward": (ward), "toWard": "", "movements": 2})
    }
    For i = 1:1:4 {
        Set pat = plan.patients.%Get(i - 1)
        Set adm = ^Hospital.Live("adm", pat.mrn), ward = $LIST(adm, 2), room = $LIST(adm, 3), bedNo = $LIST(adm, 4)
        Set to = ##class(Shutter.Util.LiveFeed).FreeBed(ward)
        Kill ^Hospital.Live("bed", ward, room, bedNo)
        Set ^Hospital.Live("bed", $LIST(to, 1), $LIST(to, 2), $LIST(to, 3)) = pat.mrn
        Set ^Hospital.Live("adm", pat.mrn) = $LISTBUILD(pat.encounterId, $LIST(to, 1), $LIST(to, 2), $LIST(to, 3), $LIST(adm, 5))
        Set pat.toWard = $LIST(to, 1)
        Set k = k + 1
        Do plan.movements.%Push({"control": ("STORM" _ n _ "-" _ $TRANSLATE($JUSTIFY(k, 2), " ", "0")), "event": "transfer", "mrn": (pat.mrn), "encounterId": (pat.encounterId), "ward": ($LIST(to, 1)), "room": ($LIST(to, 2)), "bed": ($LIST(to, 3)), "prior": (ward _ "^" _ room _ "^" _ bedNo _ "^HOSP")})
    }
    Quit plan
}

/// The storm (CONTRACTS 4.4, v1.35): the receiver goes down (fail_before_accept on Downstream Out), eight movements for
/// four fresh patients go out about three seconds apart and fail, and each is handed to Shutter by the hospital's own
/// process; the state moves requested, sending, waiting_receiver. StormWatch brings the receiver back and ends the storm.
Method PlayStorm() As %Status
{
    Set state = ..StormState(.json)
    If '$ISOBJECT(json) Quit $$$ERROR($$$GeneralError, "No storm requested")
    Set folder = $GET(^Hospital.Config("dir", "in"))
    If folder = "" {
        Set json.state = "failed", json.error = "The hospital's inbound folder is not recorded"
        Do ..StormSave(json)
        Quit $$$ERROR($$$GeneralError, json.error)
    }
    Set n = +$EXTRACT(json.%Get("stormId"), 4, *), zone = ..LiveZone(), sc = $$$OK
    Set json.state = "sending", json.sent = 0
    Set json.receiverDownUntil = ##class(Shutter.Util.Time).FromNow(..StormReceiverDownSeconds)
    Set plan = ..StormPlan(n, zone)
    Set json.patients = plan.patients, json.movements = plan.movements.%Size()
    Do ..StormSave(json)
    Do ..Stamp("storm")
    Try {
        Do ..Fault("Downstream Out", {"mode": "fail_before_accept"})
        Set mi = plan.movements.%GetIterator(), k = 0
        While mi.%GetNext(, .m) {
            Set k = k + 1
            Set now = ##class(Shutter.Util.LiveFeed).LocalNow(zone)
            Set p = ##class(Shutter.Util.LiveFeed).PatientNamed(m.mrn)
            Set adm = $GET(^Hospital.Live("adm", m.mrn))
            If m.event = "admit" {
                Set admitted = now
                If adm '= "" Set $LIST(adm, 5) = now, ^Hospital.Live("adm", m.mrn) = adm
            } Else {
                Set admitted = $SELECT(adm '= "": $LIST(adm, 5), 1: now)
            }
            Set text = ##class(Shutter.Util.LiveFeed).Adt($SELECT(m.event = "admit": "A01", 1: "A02"), m.control, now, p, m.encounterId, m.ward, m.room, m.bed, m.prior, admitted)
            Set path = folder _ "live-storm-" _ $TRANSLATE($JUSTIFY(n, 4), " ", "0") _ "-" _ $TRANSLATE($JUSTIFY(k, 2), " ", "0") _ ".hl7"
            Do ..WriteFile(path, text)
            Set deadline = $ZHOROLOG + 15
            While ##class(%File).Exists(path) && ($ZHOROLOG < deadline) { Hang 0.2 }
            Hang 1.5
            Set json.sent = k
            Do ..StormSave(json)
        }
        Set json.state = "waiting_receiver"
    } Catch ex {
        Set sc = ex.AsStatus(), json.state = "failed", json.error = ex.DisplayString()
        Do ..Fault("Downstream Out", {"mode": "off"})
    }
    Do ..StormSave(json)
    $$$TRACE("Storm " _ json.stormId _ ": " _ json.sent _ " movement(s) sent, state " _ json.state)
    Quit sc
}

/// The storm's later moves: the receiver comes back when its outage is over (releasing), and the storm is done when
/// Shutter's incident has closed or the storm's span is over; then the rotation starts again from now.
Method StormWatch() As %Status
{
    Set state = ..StormState(.json)
    If '$ISOBJECT(json) Quit $$$OK
    Set now = ##class(Shutter.Util.Time).NowUTC()
    If ((state = "sending") || (state = "waiting_receiver")) && (json.%Get("receiverDownUntil") '= "") && (##class(Shutter.Util.Time).SecondsBetween(json.receiverDownUntil, now) >= 0) {
        Do ..Fault("Downstream Out", {"mode": "off"})
        Set json.state = "releasing", json.receiverUpAt = now
        Do ..StormSave(json)
        $$$TRACE("Storm " _ json.stormId _ ": the receiver answers again")
        Quit $$$OK
    }
    If state = "releasing" {
        Set inc = ..StormIncident(json.%Get("startedAt"))
        If $ISOBJECT(inc) Set json.incidentId = inc.incidentId, json.incidentState = inc.state
        Set over = (json.%Get("endsAt") '= "") && (##class(Shutter.Util.Time).SecondsBetween(json.endsAt, now) >= 0)
        If $ISOBJECT(inc) && (inc.state = "closed") Set over = 1
        If over {
            Set json.state = "done", json.endedAt = now
            Set ^Hospital.Live("last_story_at") = ##class(Shutter.Util.Time).EpochSeconds()
            $$$TRACE("Storm " _ json.stormId _ " done")
        }
        Do ..StormSave(json)
    }
    Quit $$$OK
}

/// The incident the storm's cases joined in Shutter (one the detector opened for them, or one already open for the
/// receiver), read in Shutter's namespace; "" when none yet.
Method StormIncident(startedAt As %String) As %DynamicObject
{
    Set out = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ..ShutterNamespace
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 i.IncidentId, i.State FROM Shutter_Store.""Case"" c JOIN Shutter_Store.Incident i ON c.Incident = i.ID WHERE c.Scenario = 'storm' AND c.OpenedAt >= ? ORDER BY c.ID DESC", startedAt)
        If rs.%Next() Set out = {"incidentId": (rs.%Get("IncidentId")), "state": (rs.%Get("State"))}
    } Catch ex {
    }
    Quit out
}

/// The scenario list as the build's SHUTTER_LIVE_SCENARIOS says (^Hospital.Config("liveScenarios"), v1.38), else as the
/// setting says, or every playable scenario of the file.
Method ScenarioList() As %List
{
    Set list = "", names = $GET(^Hospital.Config("liveScenarios"), ..Scenarios)
    For i = 1:1:$LENGTH(names, ",") { Set s = $ZSTRIP($PIECE(names, ",", i), "<>W") If s '= "" Set list = list _ $LISTBUILD(s) }
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
    Set ^Hospital.Live("last_story_at") = ##class(Shutter.Util.Time).EpochSeconds()
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
    // The scenario runner's reset reads the mark: the bed map stays while this story plays (its patients are read below
    // without $GET), and a mark older than its longest story is a job that died, which the next job's OnInit clears too.
    Set ^Hospital.Live("playing") = $LISTBUILD(id, ##class(Shutter.Util.Time).EpochSeconds())
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
                    // Recorded before it is applied, so a job cut off between the two leaves nothing unrecorded.
                    Set ^Hospital.Live("faulted", name) = 1
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
    Kill ^Hospital.Live("faulted"), ^Hospital.Live("playing")
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
    // The storm (v1.35), when one has ever been pressed: Shutter's LiveStatus adds the incident and the case counts.
    Set state = ..StormState(.storm)
    If $ISOBJECT(storm) Set s.storm = storm
    Set ^Hospital.Live("status") = s.%ToJSON()
}

}
