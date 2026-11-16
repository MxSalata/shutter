/// This site's guide (GET /catalogue's atReceivers, CONTRACTS 6.8): what a match of a shipped entry alone settles on at
/// each receiver of the profile in force, checked against the matcher's own result. For E1, E3, E6, E7 and E8, on a
/// receiver of each kind (current state, history of record, orders and results, FHIR R4), the route's answer is what
/// Shutter.Catalogue.Matcher.Match gives on conditions that match that entry alone, with that receiver's facts; for E7,
/// whose alternative names the case's other source system, the answer for a case whose other source is the site's
/// authoritative source too. The profile is put back afterwards.
Class Shutter.Test.SiteGuide Extends %UnitTest.TestCase
{

Parameter BEDS = "UT Guide Beds";

Parameter RECORDS = "UT Guide Records";

Parameter LAB = "UT Guide Lab";

Parameter FHIR = "UT Guide FHIR";

Parameter OTHER = "UT-OTHER";

Property SavedJson As %String(MAXLEN = "");

Property SavedSource As %String(MAXLEN = 500);

Property HadRow As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadRow = $ISOBJECT(row)
    If ..HadRow Set ..SavedJson = row.Json, ..SavedSource = row.Source
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    If ..HadRow {
        Do ##class(Shutter.Store.SiteProfile).Store(..SavedJson, ..SavedSource, "test", "", .v)
    } Else {
        Set row = ##class(Shutter.Store.SiteProfile).Row()
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    }
    Quit $$$OK
}

/// A profile with a receiver of each kind and, when asked, an authoritative source, stored as a person saves it.
Method StoreProfile(authoritative As %String = "")
{
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Set base = p.receivers.%Get(0)
    Set beds = {}.%FromJSON(base.%ToJSON()), beds.name = ..#BEDS, beds.category = "current_state"
    Set records = {}.%FromJSON(base.%ToJSON()), records.name = ..#RECORDS, records.category = "history_of_record"
    Set lab = {}.%FromJSON(base.%ToJSON()), lab.name = ..#LAB, lab.category = "orders_results"
    Do lab.%Remove("api"), lab.%Remove("demo")
    Set fhir = {"name": (..#FHIR), "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "fhir": {"base": "/ut-guide-fhir/r4", "recovery_enabled": true, "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49"}, "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"}, "marker": {"system": "urn:shutter:recovery"}, "location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
    Set p.receivers = [(beds), (records), (lab), (fhir)]
    Set p."authoritative_source" = authoritative
    // The shipped teams name the demo's receivers: this profile names its own
    Do p.%Remove("teams")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "api", "approver", "", .v), "a profile with a receiver of each kind")
}

/// Conditions that match one shipped entry alone: the first allowed value of each condition its pattern names.
ClassMethod ConditionsFor(id As %String) As %DynamicObject
{
    Set pattern = {}, all = ##class(Shutter.Catalogue.Entry).All().%GetIterator()
    While all.%GetNext(, .e) { If e.id = id Set pattern = e.%Get("pattern") Quit }
    Set c = {}, it = pattern.%GetIterator()
    While it.%GetNext(.name, .allowed) { Do c.%Set(name, $SELECT($ISOBJECT(allowed): allowed.%Get(0), 1: allowed)) }
    Quit c
}

/// The shipped entry's atReceivers row for a receiver, from GET /catalogue's shipped list.
ClassMethod Row(shipped As %DynamicArray, id As %String, receiver As %String) As %DynamicObject
{
    Set it = shipped.%GetIterator()
    While it.%GetNext(, .e) {
        Continue:(e.id '= id)
        Set ri = e.atReceivers.%GetIterator()
        While ri.%GetNext(, .r) { Return:(r.receiver = receiver) r }
    }
    Quit ""
}

/// The shipped list as GET /catalogue answers it (SiteEntries.Shipped is what the route writes).
ClassMethod Shipped() As %DynamicArray
{
    Quit ##class(Shutter.API.SiteEntries).Shipped()
}

Method Check(id As %String, receiver As %String, shipped As %DynamicArray, label As %String)
{
    Set row = ..Row(shipped, id, receiver)
    Do $$$AssertTrue($ISOBJECT(row), id _ " has a row for " _ receiver)
    Quit:'$ISOBJECT(row)
    Set m = ##class(Shutter.Catalogue.Matcher).Match(..ConditionsFor(id), ##class(Shutter.Catalogue.Matcher).ReceiverFacts(receiver))
    Do $$$AssertEquals(m.matches.%Size() _ " " _ m.entry, "1 " _ id, "the conditions match " _ id _ " alone")
    Do $$$AssertEquals(row.decides _ " " _ row.outcome _ " " _ row.outcomeRef, m.decision _ " " _ m.outcome _ " " _ m."outcome_ref", id _ " at " _ label _ ": the route says what the matcher decides")
}

/// E1, E3, E6, E7 and E8 at a receiver of each kind, with no authoritative source: every row is the matcher's own result,
/// and E7's alternative, which names the case's other source, is never taken.
Method TestEachEntryAtEachKindIsTheMatchers()
{
    Do ..StoreProfile()
    Set shipped = ..Shipped()
    For id = "E1", "E3", "E6", "E7", "E8" {
        For receiver = ..#BEDS, ..#RECORDS, ..#LAB, ..#FHIR {
            Do ..Check(id, receiver, shipped, receiver)
            Set row = ..Row(shipped, id, receiver)
            Continue:'$ISOBJECT(row)
            Do $$$AssertEquals(row.whenOtherSource.%Size(), 0, id _ " at " _ receiver _ ": nothing depends on the case's other source when the site names none")
        }
    }
    // What the rows come to, as the catalogue says: E1 closes at a current state receiver, and asks for the history to be
    // corrected at a history of record; a FHIR receiver keeps what is current
    Do $$$AssertEquals(..Row(shipped, "E1", ..#BEDS).outcome, "none", "E1 at a current state receiver closes with nothing sent")
    Do $$$AssertEquals(..Row(shipped, "E1", ..#RECORDS).outcome _ " " _ ..Row(shipped, "E1", ..#RECORDS).outcomeRef, "correct_history alternative:1", "E1 at a history of record takes its alternative")
    Do $$$AssertEquals(..Row(shipped, "E6", ..#FHIR).outcome, "none", "a FHIR receiver keeps what is current")
    Do $$$AssertEquals(..Row(shipped, "E3", ..#BEDS).outcomeRef, "preferred", "E3's alternative is the board's choice (always), never a policy")
    Do $$$AssertEquals(..Row(shipped, "E8", ..#BEDS).decides _ " " _ ..Row(shipped, "E8", ..#BEDS).outcome, "person escalate", "E8 always asks a person")
    Do $$$AssertEquals(..Row(shipped, "E7", ..#LAB).kind _ "|" _ ..Row(shipped, "E7", ..#LAB).category _ "|" _ ..Row(shipped, "E7", ..#FHIR).kind, "|orders_results|fhir_r4", "each row names its receiver's kind and category")
}

/// With an authoritative source, E7's alternative depends on the case: the row says what applies otherwise and, apart,
/// what a case whose other source is that system settles on, each the matcher's own result.
Method TestTheOtherSourceIsAConditionNotAGuess()
{
    Do ..StoreProfile(..#OTHER)
    Set shipped = ..Shipped()
    For receiver = ..#BEDS, ..#RECORDS, ..#LAB, ..#FHIR {
        Do ..Check("E7", receiver, shipped, receiver)
        Set row = ..Row(shipped, "E7", receiver)
        Continue:'$ISOBJECT(row)
        Do $$$AssertEquals(row.whenOtherSource.%Size(), 1, "E7 at " _ receiver _ ": one outcome depends on the case's other source")
        Set on = row.whenOtherSource.%Get(0)
        Continue:'$ISOBJECT(on)
        Set facts = ##class(Shutter.Catalogue.Matcher).ReceiverFacts(receiver)
        Set facts."other_source" = ..#OTHER
        Set m = ##class(Shutter.Catalogue.Matcher).Match(..ConditionsFor("E7"), facts)
        Do $$$AssertEquals(on.otherSource _ " " _ on.decides _ " " _ on.outcome _ " " _ on.outcomeRef, ..#OTHER _ " " _ m.decision _ " " _ m.outcome _ " " _ m."outcome_ref", "E7 at " _ receiver _ " on a case whose other source is the authoritative one: the matcher's result")
        Do $$$AssertEquals(on.outcome _ " " _ row.outcome, "none escalate", "the authoritative system's movement stands; otherwise a person")
    }
    // An entry no case-dependent when names keeps no condition
    Do $$$AssertEquals(..Row(shipped, "E1", ..#BEDS).whenOtherSource.%Size(), 0, "E1 depends on no other source")
}

}
