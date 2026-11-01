/// The live hospital's feed (CONTRACTS 4.4, v1.34): what the hospital's live player sends. Pure functions over text, so the
/// unit tests run them without a production: fresh synthetic patients (a name, a date of birth, a sex, a hospital number, an
/// encounter and an NHS number in the test range with a valid check digit), a scenario's fixture messages rewritten for
/// those patients at present times (every patient and encounter of the scenario mapped once, the intervals between its
/// messages kept, a fresh control id, the room of every placement set so one play never shares a bed with another), the
/// scenario's fault steps rewritten with them, and the ordinary messages a working hospital sends between stories (an
/// admission to a free bed, a transfer, a discharge that frees the bed, a demographic update).
Class Shutter.Util.LiveFeed
{

Parameter GIVEN = "Ada,Ben,Cara,Dev,Ella,Finn,Grace,Hugo,Isla,Jack,Kira,Leo,Maya,Noah,Orla,Pete,Rhea,Sam,Tess,Uma,Vik,Wren,Yara,Zane,Amir,Bea,Cal,Dina,Eli,Fay,Gus,Hana,Ivor,Jo,Kit,Lara,Milo,Nia,Omar,Pia";

Parameter FAMILY = "Synth,Sample,Mock,Testwell,Fakeman,Dummy,Placebo,Specimen,Exemplar,Fixture,Stubbs,Holder,Draft,Trial,Probe,Model,Pattern,Template,Proxy,Sketch,Rehearse,Preview,Replica,Facsimile,Standin,Decoy,Phantom,Shadow,Mirror,Echo,Ersatz,Proto,Beta,Alpha,Gamma,Delta,Sigma,Theta,Kappa,Omega";

Parameter WARDS = "WARD-A,WARD-B,WARD-C,WARD-D";

/// A fresh synthetic patient and encounter: {mrn, nhs, enc, family, given, dob, sex}. The numbers come from a counter of
/// this namespace from 500000, so no live patient repeats one of the fixtures' (MRN1nnn) or another's.
ClassMethod NewPatient() As %DynamicObject
{
    Set n = 500000 + $INCREMENT(^Hospital.Live("counter"))
    Set p = {}
    Set p.mrn = "MRN" _ n, p.enc = "ENC-" _ n, p.nhs = ..NhsNumber("MRN" _ n)
    Set given = $LISTFROMSTRING(..#GIVEN, ","), family = $LISTFROMSTRING(..#FAMILY, ",")
    Set p.given = $ZCONVERT($LIST(given, 1 + (n # $LISTLENGTH(given))), "U"), p.family = $ZCONVERT($LIST(family, 1 + ((n \ 7) # $LISTLENGTH(family))), "U")
    Set p.sex = $SELECT(n # 2: "F", 1: "M")
    Set year = +$EXTRACT($ZDATE($HOROLOG, 3), 1, 4) - 18 - (n # 78), month = 1 + (n # 12), day = 1 + ((n \ 12) # 28)
    Set p.dob = year _ $TRANSLATE($JUSTIFY(month, 2), " ", "0") _ $TRANSLATE($JUSTIFY(day, 2), " ", "0")
    Quit p
}

/// A synthetic NHS number for a hospital number: 999 (the test range), the number's last four digits, two more digits and
/// a valid modulus 11 check digit, as fixtures/generate.py makes them.
ClassMethod NhsNumber(mrn As %String) As %String
{
    Set digits = $TRANSLATE(mrn, "MRNENC-", ""), last4 = $TRANSLATE($JUSTIFY($EXTRACT(digits, * - 3, *), 4), " ", "0")
    For pair = 0:1:99 {
        Set base = "999" _ last4 _ $TRANSLATE($JUSTIFY(pair, 2), " ", "0"), sum = 0
        For i = 1:1:9 { Set sum = sum + ($EXTRACT(base, i) * (11 - i)) }
        Set check = (11 - (sum # 11)) # 11
        If check '= 10 Quit
    }
    Quit base _ check
}

/// An HL7 DTM (YYYYMMDD[HHMM[SS]]) shifted by seconds, in the same length; anything else unchanged.
ClassMethod Shift(dtm As %String, delta As %Integer) As %String
{
    Set t = $PIECE(dtm, ".", 1)
    If '$MATCH(t, "^[0-9]{8}([0-9]{2}){0,3}$") Quit dtm
    Set len = $LENGTH(t)
    Set iso = $EXTRACT(t, 1, 4) _ "-" _ $EXTRACT(t, 5, 6) _ "-" _ $EXTRACT(t, 7, 8) _ " " _ $SELECT(len >= 10: $EXTRACT(t, 9, 10), 1: "00") _ ":" _ $SELECT(len >= 12: $EXTRACT(t, 11, 12), 1: "00") _ ":" _ $SELECT(len >= 14: $EXTRACT(t, 13, 14), 1: "00")
    Set h = $ZDATETIMEH(iso, 3, 1)
    Set total = ($PIECE(h, ",", 1) * 86400) + $PIECE(h, ",", 2) + delta
    Set out = $TRANSLATE($ZDATE(total \ 86400, 3), "-", "") _ $TRANSLATE($ZTIME(total # 86400, 1), ":", "")
    Quit $EXTRACT(out, 1, len)
}

/// The seconds between the earliest and the latest event time (EVN-6, else EVN-2, else MSH-7) of a scenario's messages,
/// and the earliest as a DTM (Output first).
ClassMethod Span(texts As %DynamicArray, Output first As %String) As %Integer
{
    Set first = "", last = ""
    Set ti = texts.%GetIterator()
    While ti.%GetNext(, .text) {
        Set t = ..EventDtm(text)
        If t = "" Continue
        If (first = "") || (..Seconds(t) < ..Seconds(first)) Set first = t
        If (last = "") || (..Seconds(t) > ..Seconds(last)) Set last = t
    }
    If first = "" Quit 0
    Quit ..Seconds(last) - ..Seconds(first)
}

ClassMethod EventDtm(text As %String) As %String
{
    Set msh = ..Segment(text, "MSH"), evn = ..Segment(text, "EVN")
    Set t = $SELECT(evn '= "": $PIECE($PIECE(evn, "|", 7), ".", 1), 1: "")
    If t = "" && (evn '= "") Set t = $PIECE($PIECE(evn, "|", 3), ".", 1)
    If t = "" && (msh '= "") Set t = $PIECE($PIECE(msh, "|", 7), ".", 1)
    Quit $PIECE(t, "+", 1)
}

ClassMethod Seconds(dtm As %String) As %Integer
{
    Set t = dtm _ $EXTRACT("00000000000000", $LENGTH(dtm) + 1, 14)
    Set h = $ZDATETIMEH($EXTRACT(t, 1, 4) _ "-" _ $EXTRACT(t, 5, 6) _ "-" _ $EXTRACT(t, 7, 8) _ " " _ $EXTRACT(t, 9, 10) _ ":" _ $EXTRACT(t, 11, 12) _ ":" _ $EXTRACT(t, 13, 14), 3, 1)
    Quit ($PIECE(h, ",", 1) * 86400) + $PIECE(h, ",", 2)
}

/// The first segment of a name in an HL7 text (segments separated by CR or LF), or "".
ClassMethod Segment(text As %String, name As %String) As %String
{
    Set text = $TRANSLATE(text, $CHAR(10), $CHAR(13))
    For i = 1:1:$LENGTH(text, $CHAR(13)) {
        Set seg = $PIECE(text, $CHAR(13), i)
        If $PIECE(seg, "|", 1) = name Quit
        Set seg = ""
    }
    Quit seg
}

/// The patients a scenario's messages name: a map from each MRN (PID-3's MR repetition, MRG-1) and each encounter (PV1-19,
/// MRG-5) to a fresh patient's. Several encounters of one MRN share its patient.
ClassMethod MapPatients(texts As %DynamicArray) As %DynamicObject
{
    Set map = {}, byMrn = {}
    Set ti = texts.%GetIterator()
    While ti.%GetNext(, .text) {
        Set text = $TRANSLATE(text, $CHAR(10), $CHAR(13))
        For i = 1:1:$LENGTH(text, $CHAR(13)) {
            Set seg = $PIECE(text, $CHAR(13), i), name = $PIECE(seg, "|", 1)
            If name = "PID" {
                Set mrn = ..MrFrom($PIECE(seg, "|", 4))
                If (mrn '= "") && 'byMrn.%IsDefined(mrn) Do byMrn.%Set(mrn, ..NewPatient())
            } ElseIf name = "MRG" {
                Set mrn = ..MrFrom($PIECE(seg, "|", 2))
                If (mrn '= "") && 'byMrn.%IsDefined(mrn) Do byMrn.%Set(mrn, ..NewPatient())
            }
        }
    }
    Set map.patients = byMrn, map.encounters = {}
    // Encounters: PV1-19 belongs to the message's PID; MRG-5 to the MRG's own MRN.
    Set ti = texts.%GetIterator()
    While ti.%GetNext(, .text) {
        Set text = $TRANSLATE(text, $CHAR(10), $CHAR(13)), mrn = ""
        For i = 1:1:$LENGTH(text, $CHAR(13)) {
            Set seg = $PIECE(text, $CHAR(13), i), name = $PIECE(seg, "|", 1)
            If name = "PID" Set mrn = ..MrFrom($PIECE(seg, "|", 4))
            If (name = "PV1") && ($PIECE($PIECE(seg, "|", 20), "^", 1) '= "") Do ..MapEncounter(map, $PIECE($PIECE(seg, "|", 20), "^", 1), mrn)
            If (name = "MRG") && ($PIECE($PIECE(seg, "|", 6), "^", 1) '= "") Do ..MapEncounter(map, $PIECE($PIECE(seg, "|", 6), "^", 1), ..MrFrom($PIECE(seg, "|", 2)))
        }
    }
    Quit map
}

ClassMethod MapEncounter(map As %DynamicObject, enc As %String, mrn As %String) [ Private ]
{
    Quit:map.encounters.%IsDefined(enc)
    Set p = map.patients.%Get(mrn)
    If '$ISOBJECT(p) Set p = ..NewPatient() Do map.patients.%Set(mrn, p)
    // The patient's first encounter takes its own; a second one of the same patient gets a number of its own.
    Set used = 0, ei = map.encounters.%GetIterator()
    While ei.%GetNext(, .v) { If v = p.enc Set used = 1 }
    Do map.encounters.%Set(enc, $SELECT(used: "ENC-" _ (500000 + $INCREMENT(^Hospital.Live("counter"))), 1: p.enc))
}

/// The MR identifier of a CX field with repetitions, else the first repetition's id.
ClassMethod MrFrom(field As %String) As %String
{
    Set pick = ""
    For r = 1:1:$LENGTH(field, "~") {
        Set rep = $PIECE(field, "~", r)
        If $ZCONVERT($PIECE(rep, "^", 5), "U") = "MR" Set pick = rep Quit
    }
    If pick = "" Set pick = $PIECE(field, "~", 1)
    Quit $PIECE(pick, "^", 1)
}

/// One fixture message rewritten: the patients and encounters mapped, the times shifted by delta, a fresh control id, the
/// room of every placement (PV1-3.2 and PV1-6.2) set to room. Segments stay in their order; unknown ones pass through.
ClassMethod Rewrite(text As %String, map As %DynamicObject, delta As %Integer, room As %String, control As %String) As %String
{
    Set text = $TRANSLATE(text, $CHAR(10), $CHAR(13)), out = "", mrn = ""
    For i = 1:1:$LENGTH(text, $CHAR(13)) {
        Set seg = $PIECE(text, $CHAR(13), i)
        Continue:(seg = "")
        Set name = $PIECE(seg, "|", 1)
        If name = "MSH" {
            Set $PIECE(seg, "|", 7) = ..Shift($PIECE(seg, "|", 7), delta)
            Set $PIECE(seg, "|", 10) = control
        } ElseIf name = "EVN" {
            Set $PIECE(seg, "|", 3) = ..Shift($PIECE(seg, "|", 3), delta), $PIECE(seg, "|", 7) = ..Shift($PIECE(seg, "|", 7), delta)
        } ElseIf name = "PID" {
            Set mrn = ..MrFrom($PIECE(seg, "|", 4)), p = map.patients.%Get(mrn)
            If $ISOBJECT(p) {
                Set $PIECE(seg, "|", 4) = ..Identifiers($PIECE(seg, "|", 4), p)
                Set $PIECE(seg, "|", 6) = p.family _ "^" _ p.given
                Set $PIECE(seg, "|", 8) = p.dob, $PIECE(seg, "|", 9) = p.sex
            }
        } ElseIf name = "PV1" {
            Set visit = $PIECE(seg, "|", 20), enc = $PIECE(visit, "^", 1)
            If (enc '= "") && map.encounters.%IsDefined(enc) {
                Set $PIECE(visit, "^", 1) = map.encounters.%Get(enc), $PIECE(seg, "|", 20) = visit
            }
            For f = 4, 7 {
                Set loc = $PIECE(seg, "|", f)
                If loc '= "" Set $PIECE(loc, "^", 2) = room, $PIECE(seg, "|", f) = loc
            }
            For f = 45, 46 {
                If $PIECE(seg, "|", f) '= "" Set $PIECE(seg, "|", f) = ..Shift($PIECE(seg, "|", f), delta)
            }
        } ElseIf name = "MRG" {
            Set pmrn = ..MrFrom($PIECE(seg, "|", 2)), pp = map.patients.%Get(pmrn)
            If $ISOBJECT(pp) Set $PIECE(seg, "|", 2) = ..Identifiers($PIECE(seg, "|", 2), pp)
            Set prior = $PIECE(seg, "|", 6), penc = $PIECE(prior, "^", 1)
            If (penc '= "") && map.encounters.%IsDefined(penc) {
                Set $PIECE(prior, "^", 1) = map.encounters.%Get(penc), $PIECE(seg, "|", 6) = prior
            }
        }
        Set out = out _ seg _ $CHAR(13)
    }
    Quit out
}

/// A CX field's repetitions with the patient's numbers: the MR repetition takes the MRN, an NH one the NHS number; an
/// unlabelled first repetition is the MRN.
ClassMethod Identifiers(field As %String, p As %DynamicObject) As %String [ Private ]
{
    Set out = ""
    For r = 1:1:$LENGTH(field, "~") {
        Set rep = $PIECE(field, "~", r), type = $ZCONVERT($PIECE(rep, "^", 5), "U")
        If (type = "MR") || ((type = "") && (r = 1)) Set $PIECE(rep, "^", 1) = p.mrn
        If type = "NH" Set $PIECE(rep, "^", 1) = p.nhs
        Set out = out _ $SELECT(r > 1: "~", 1: "") _ rep
    }
    Quit out
}

/// A fault step's operation key (source^authority^mrn^encounter^event^timeZ) for the mapped patient at the shifted time.
/// The fixtures' keys were made with the fixtures' profile (feed zone Europe/London); the live key's time is the shifted
/// message's event time read in the live profile's zone, as Shutter will read it, so the fault lands on the message meant.
/// When no message carries the key's time, the UTC time is shifted by delta with the two zones' offsets.
ClassMethod RewriteKey(key As %String, map As %DynamicObject, delta As %Integer, texts As %DynamicArray = "", fixtureZone As %String = "Europe/London", liveZone As %String = "") As %String
{
    If $LENGTH(key, "^") < 6 Quit key
    Set mrn = $PIECE(key, "^", 3), enc = $PIECE(key, "^", 4), p = map.patients.%Get(mrn)
    If $ISOBJECT(p) Set $PIECE(key, "^", 3) = p.mrn
    If map.encounters.%IsDefined(enc) Set $PIECE(key, "^", 4) = map.encounters.%Get(enc)
    Set t = $PIECE(key, "^", 6)
    If '$MATCH(t, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") Quit key
    Set found = ""
    If $ISOBJECT(texts) {
        Set ti = texts.%GetIterator()
        While ti.%GetNext(, .text) {
            Set local = ..EventDtm(text)
            If local = "" Continue
            If ##class(Shutter.Util.Time).FromHL7(local, fixtureZone) = t Set found = ##class(Shutter.Util.Time).FromHL7(..Shift(local, delta), liveZone) Quit
        }
    }
    If found = "" {
        Set h = $ZDATETIMEH($TRANSLATE($PIECE(t, "Z", 1), "T", " "), 3, 1)
        Set total = ($PIECE(h, ",", 1) * 86400) + $PIECE(h, ",", 2) + delta
        Set local = $TRANSLATE($ZDATE(total \ 86400, 3), "-", "") _ $TRANSLATE($ZTIME(total # 86400, 1), ":", "")
        Set total = total + ..OffsetSeconds(fixtureZone, $PIECE(t, "Z", 1)) - ..OffsetSeconds(liveZone, ..Iso(local))
        Set found = $ZDATE(total \ 86400, 3) _ "T" _ $ZTIME(total # 86400, 1) _ "Z"
    }
    Set $PIECE(key, "^", 6) = found
    Quit key
}

/// A zone's offset at a local ISO time, in seconds (0 for UTC or a zone Shutter does not know).
ClassMethod OffsetSeconds(zone As %String, localIso As %String) As %Integer
{
    Set off = ##class(Shutter.Util.Time).ZoneOffset(zone, localIso)
    If off = "" Quit 0
    Set sign = $SELECT($EXTRACT(off, 1) = "-": -1, 1: 1), digits = $TRANSLATE(off, "+-", "")
    Quit sign * ((+$EXTRACT(digits, 1, 2) * 3600) + (+$EXTRACT(digits, 3, 4) * 60))
}

/// A 14-digit DTM as a local ISO time (yyyy-mm-ddThh:mm:ss).
ClassMethod Iso(dtm As %String) As %String
{
    Set t = dtm _ $EXTRACT("00000000000000", $LENGTH(dtm) + 1, 14)
    Quit $EXTRACT(t, 1, 4) _ "-" _ $EXTRACT(t, 5, 6) _ "-" _ $EXTRACT(t, 7, 8) _ "T" _ $EXTRACT(t, 9, 10) _ ":" _ $EXTRACT(t, 11, 12) _ ":" _ $EXTRACT(t, 13, 14)
}

/// The present time as a DTM in a zone's local clock (the feed's clock: the live profile's feed zone).
ClassMethod LocalNow(zone As %String = "") As %String
{
    Set utc = ##class(Shutter.Util.Time).NowUTC()
    Set dtm = $TRANSLATE($TRANSLATE(utc, "-:T", ""), "Z", "")
    Quit ..Shift(dtm, ..OffsetSeconds(zone, $PIECE(utc, "Z", 1)))
}

/// The shift that puts a scenario's first event at now minus its span (so its last event is about now), in seconds; now is
/// a DTM in the feed's clock (UTC here: the live hospital's profile names UTC as its feed zone).
ClassMethod DeltaFor(texts As %DynamicArray, nowDtm As %String = "") As %Integer
{
    Set span = ..Span(texts, .first)
    If first = "" Quit 0
    If nowDtm = "" Set nowDtm = $TRANSLATE($TRANSLATE(##class(Shutter.Util.Time).NowUTC(), "-:T", ""), "Z", "")
    Quit ..Seconds(nowDtm) - span - ..Seconds(first)
}

// ---- the ordinary feed ----

/// The next ordinary message a working hospital sends, from the live patients this namespace keeps
/// (^Hospital.Live("adm", mrn) = $LB(enc, ward, room, bed, admitDtm)): an admission to a free bed when fewer than
/// Occupancy patients are in, else by turn a transfer, a demographic update or a discharge that frees the bed. Returns the
/// HL7 text, and what it is in Output kind ("admit", "transfer", "update", "discharge").
ClassMethod Ordinary(control As %String, Output kind As %String, occupancy As %Integer = 24, zone As %String = "") As %String
{
    Set now = ..LocalNow(zone)
    Set in = 0, mrn = "" For { Set mrn = $ORDER(^Hospital.Live("adm", mrn)) Quit:mrn=""  Set in = in + 1 }
    Set turn = $INCREMENT(^Hospital.Live("turn"))
    If (in < 4) || ((in < occupancy) && (turn # 3 = 0)) {
        Set kind = "admit", p = ..NewPatient(), bed = ..FreeBed()
        Set ^Hospital.Live("adm", p.mrn) = $LISTBUILD(p.enc, $LIST(bed, 1), $LIST(bed, 2), $LIST(bed, 3), now)
        Set ^Hospital.Live("bed", $LIST(bed, 1), $LIST(bed, 2), $LIST(bed, 3)) = p.mrn
        Quit ..Adt("A01", control, now, p, p.enc, $LIST(bed, 1), $LIST(bed, 2), $LIST(bed, 3), "", now)
    }
    // A patient by turn.
    Set pick = turn # in, mrn = "", k = -1
    For { Set mrn = $ORDER(^Hospital.Live("adm", mrn)) Quit:mrn=""  Set k = k + 1 Quit:k=pick }
    If mrn = "" Set mrn = $ORDER(^Hospital.Live("adm", ""))
    Set adm = ^Hospital.Live("adm", mrn), p = ..PatientNamed(mrn)
    Set enc = $LIST(adm, 1), ward = $LIST(adm, 2), room = $LIST(adm, 3), bedNo = $LIST(adm, 4), admitted = $LIST(adm, 5)
    If turn # 3 = 1 {
        Set kind = "transfer", bed = ..FreeBed(ward)
        Kill ^Hospital.Live("bed", ward, room, bedNo)
        Set ^Hospital.Live("bed", $LIST(bed, 1), $LIST(bed, 2), $LIST(bed, 3)) = mrn
        Set ^Hospital.Live("adm", mrn) = $LISTBUILD(enc, $LIST(bed, 1), $LIST(bed, 2), $LIST(bed, 3), admitted)
        Quit ..Adt("A02", control, now, p, enc, $LIST(bed, 1), $LIST(bed, 2), $LIST(bed, 3), ward _ "^" _ room _ "^" _ bedNo _ "^HOSP", admitted)
    }
    If turn # 3 = 2 {
        Set kind = "update"
        Quit ..Adt("A08", control, now, p, enc, ward, room, bedNo, "", admitted)
    }
    Set kind = "discharge"
    Kill ^Hospital.Live("bed", ward, room, bedNo), ^Hospital.Live("adm", mrn)
    Quit ..Adt("A03", control, now, p, enc, ward, room, bedNo, "", admitted, now)
}

/// The patient behind a live MRN, as the ordinary messages first wrote them (kept beside the admission).
ClassMethod PatientNamed(mrn As %String) As %DynamicObject
{
    Set json = $GET(^Hospital.Live("patient", mrn))
    If json '= "" Quit ##class(%DynamicObject).%FromJSON(json)
    Set p = ..NewPatient()
    Set p.mrn = mrn
    Quit p
}

/// A free bed: the live feed's rooms LIVE1 to LIVE3 of each ward, beds 01 to 08; another ward than avoid when given.
ClassMethod FreeBed(avoid As %String = "") As %List
{
    Set wards = $LISTFROMSTRING(..#WARDS, ",")
    For round = 1:1:3 {
        For w = 1:1:$LISTLENGTH(wards) {
            Set ward = $LIST(wards, w)
            Continue:(ward = avoid)
            For r = 1:1:3 {
                For b = 1:1:8 {
                    Set bed = $TRANSLATE($JUSTIFY(b, 2), " ", "0")
                    If '$DATA(^Hospital.Live("bed", ward, "LIVE" _ r, bed)) Quit
                    Set bed = ""
                }
                Quit:bed'=""
            }
            Quit:bed'=""
        }
        Quit:bed'=""
        Set avoid = ""
    }
    If bed = "" Set ward = $LIST(wards, 1), r = 3, bed = "08"
    Quit $LISTBUILD(ward, "LIVE" _ r, bed)
}

/// One ADT message as the demo's PAS writes them (the fixtures' shape).
ClassMethod Adt(trigger As %String, control As %String, now As %String, p As %DynamicObject, enc As %String, ward As %String, room As %String, bed As %String, prior As %String, admitted As %String, discharged As %String = "") As %String
{
    If '$DATA(^Hospital.Live("patient", p.mrn)) Set ^Hospital.Live("patient", p.mrn) = p.%ToJSON()
    Set cr = $CHAR(13)
    Set msh = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|" _ now _ "||ADT^" _ trigger _ "^ADT_" _ $SELECT(trigger = "A08": "A01", trigger = "A03": "A03", trigger = "A02": "A02", 1: "A01") _ "|" _ control _ "|P|2.5.1"
    Set evn = "EVN|" _ trigger _ "|" _ now _ "||||" _ now
    Set pid = "PID|1||" _ p.mrn _ "^^^HOSP^MR~" _ p.nhs _ "^^^NHS^NH||" _ p.family _ "^" _ p.given _ "||" _ p.dob _ "|" _ p.sex
    Set pv1 = "PV1|1|I|" _ ward _ "^" _ room _ "^" _ bed _ "^HOSP|||" _ prior
    For f = 1:1:13 { Set pv1 = pv1 _ "|" }
    Set pv1 = pv1 _ enc
    For f = 1:1:25 { Set pv1 = pv1 _ "|" }
    Set pv1 = pv1 _ admitted _ $SELECT(discharged '= "": "|" _ discharged, 1: "")
    Quit msh _ cr _ evn _ cr _ pid _ cr _ pv1 _ cr
}

}
