/// What a model may see of a case (Shutter.Util.ModelView): the names of the message become tokens from two letters,
/// matched whatever their case from three letters and as written below that, and the view fails closed when the case's message cannot be read. The test case and
/// its message are saved under their own ids, outside the case counter, and removed afterwards.
Class Shutter.Test.ModelView Extends %UnitTest.TestCase
{

Property CaseRowId As %String;

Property HeaderId As %String;

Property BodyId As %String;

/// A transfer for a patient whose surname has two letters (LI), with a given name and an initial, and a second name
/// (LEWIS^ANNE).
Parameter MESSAGE = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015082000||ADT^A02^ADT_A02|UTMV1|P|2.5.1<CR>EVN|A02|20261015082000||||20261015082000<CR>PID|1||MRN9003^^^HOSP^MR||LI^AN^J~LEWIS^ANNE||19800101|F<CR>PV1|1|I|WARD-B^BAY1^01^HOSP||||||||||||||||ENC-9003";

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString($REPLACE(..#MESSAGE, "<CR>", $CHAR(13)), .sc)
    Quit:$$$ISERR(sc) sc
    Do msg.PokeDocType("2.5.1:ADT_A02")
    Set sc = msg.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..BodyId = msg.%Id()
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = msg.%Id()
    Set sc = h.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..HeaderId = h.%Id()
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "UT-MODELVIEW", c.OperationKey = "PAS^HOSP^MRN9003^ENC-9003^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9003", c.PatientId = "MRN9003", c.PatientIdAuthority = "HOSP"
    Set c.FailureKind = "rejected", c.SourceHeaderId = h.%Id()
    Set sc = c.%Save()
    Set ..CaseRowId = c.%Id()
    Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set id = ..CaseRowId
    &sql(DELETE FROM Shutter_Store.CaseToken WHERE "Case" = :id)
    &sql(DELETE FROM Shutter_Store.CaseEvent WHERE "Case" = :id)
    Kill ^Shutter.Counter("event", id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
    Do ##class(Ens.MessageHeader).%DeleteId(..HeaderId)
    Quit ##class(EnsLib.HL7.Message).%DeleteId(..BodyId)
}

Method Case() As Shutter.Store.Case
{
    Quit ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
}

Method TestTwoLetterNamesAndAnyCase()
{
    Set c = ..Case()
    Do $$$AssertStatusOK(##class(Shutter.Util.ModelView).Learn(c, {}), "the map is learnt")
    // A 422 echo that names the patient as the message does, and by the second name in another case.
    Set echo = "422 Unprocessable: patient LI, AN (mrn9003), also Lewis, Anne, is not on enc-9003; see J"
    Set out = ##class(Shutter.Util.ModelView).Tokenise(c, echo)
    Do $$$AssertNotTrue(out [ "LI,", "the two-letter surname is replaced: " _ out)
    Do $$$AssertNotTrue(out [ " AN ", "so is the two-letter given name")
    Do $$$AssertNotTrue($ZCONVERT(out, "U") [ "LEWIS", "a longer name is replaced whatever its case")
    Do $$$AssertNotTrue($ZCONVERT(out, "U") [ "ANNE", "and so is its given name")
    Do $$$AssertNotTrue($ZCONVERT(out, "U") [ "MRN9003", "the hospital number, written in lower case")
    Do $$$AssertNotTrue($ZCONVERT(out, "U") [ "ENC-9003", "the visit, in lower case")
    Do $$$AssertTrue(out [ "see J", "a single initial is left: as a token it would replace every standalone letter")
    Do $$$AssertTrue(out [ "MRN-T1", "the patient's token")
    Do $$$AssertTrue(out [ "ENC-T1", "the encounter's token")
}

Method TestShortNamesLeaveShortWords()
{
    Set c = ..Case()
    Do $$$AssertStatusOK(##class(Shutter.Util.ModelView).Learn(c, {}), "the map is learnt")
    // The summary's own words that a two-letter name part could be taken for, in lower case.
    Set view = ##class(Shutter.Util.ModelView).Reduce(c, {"catalogue": {"conditions": {"conditional_writes": "no", "simultaneous_sources": "no"}, "why": "an update to the ward, as li is written"}})
    Set json = view.%ToJSON()
    Do $$$AssertTrue(json [ """conditional_writes"":""no""", "a condition value is left: " _ json)
    Do $$$AssertTrue(json [ "an update to the ward, as li is written", "and so is the prose")
}

Method TestTokensAreDeterministic()
{
    Set c = ..Case()
    Do $$$AssertStatusOK(##class(Shutter.Util.ModelView).Learn(c, {}), "learnt once")
    Set first = ##class(Shutter.Store.CaseToken).ForCase(c).%ToJSON()
    Do $$$AssertStatusOK(##class(Shutter.Util.ModelView).Learn(c, {}), "learnt again")
    Do $$$AssertEquals(##class(Shutter.Store.CaseToken).ForCase(c).%ToJSON(), first, "the same map")
    Do $$$AssertTrue(first [ """value"":""LI""", "the surname has a token")
    Do $$$AssertTrue(first [ """value"":""AN""", "the given name has a token")
    Do $$$AssertNotTrue(first [ """value"":""J""", "the initial has none")
    Do $$$AssertTrue(first [ """value"":""LEWIS""", "the second name has one")
}

Method TestFailsClosedWhenTheMessageCannotBeRead()
{
    Set c = ..Case()
    Set c.SourceHeaderId = "999999999"
    Set sc = ##class(Shutter.Util.ModelView).Learn(c, {})
    Do $$$AssertStatusNotOK(sc, "learning fails when the case's message cannot be read")
    Set m = ##class(Shutter.Store.BoardMember).%New()
    Set m.Code = "ut", m.Name = "UT", m.Role = "specialist", m.TerminalTool = "SubmitFindings"
    Set req = ##class(Shutter.Process.CaseWorkflow).BuildAgentRequest(c, m, {"operation": {"patient_id": "MRN9003"}}.%ToJSON(), "", 0, .bsc)
    Do $$$AssertNotTrue($ISOBJECT(req), "no request is built, so nothing is sent")
    Do $$$AssertStatusNotOK(bsc, "and the status says why")
    Set view = ##class(Shutter.Util.ModelView).Reduce(c, {"failure": {"kind": "rejected", "text": "MRN9003"}})
    Do $$$AssertTrue(view.%IsDefined("error"), "a case with no tokens gets no view: " _ view.%ToJSON())
    Do $$$AssertNotTrue(view.%ToJSON() [ "MRN9003", "and no identifier")
}

}
