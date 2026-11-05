/// What a connector makes of a request nobody answered (CONTRACTS 1.3, v1.42). The adapter's response object has no status
/// then and the connectors store +StatusCode, so "no answer" arrives as 0: a test on an empty status would pass and prove
/// nothing, which is how a timed-out write came to read as refused, with the receiver applying it.
Class Shutter.Test.NoAnswer Extends %UnitTest.TestCase
{

/// The status the adapter gives for a request that timed out, and for a socket that never opened.
ClassMethod TimedOut() As %Status
{
    Quit $$$ERROR(5922)
}

ClassMethod NeverOpened() As %Status
{
    Quit $$$ERROR(6059, "ward", 80)
}

/// A result carrying this status, classified by the given class's Classify.
ClassMethod Classified(class As %String, httpStatus As %String, sc As %Status) As Shutter.Msg.WardResult
{
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = httpStatus
    Do $CLASSMETHOD(class, "Classify", r, sc, {})
    Quit r
}

Method TestAWriteNobodyAnswered()
{
    For class = "Shutter.Operation.Ward", "Hospital.Operation.DownstreamOut" {
        For status = 0, "" {
            Set r = ..Classified(class, status, ..TimedOut())
            Do $$$AssertEquals(r.Outcome, "uncertain", class _ ", status [" _ status _ "]: a timed-out write may have been applied")
            Do $$$AssertTrue(r.Error [ "5922", class _ ": the adapter's words are kept, with no HTTP 0 in them: " _ r.Error)
            Do $$$AssertNotTrue(r.Error [ "HTTP 0", class _ ": no HTTP 0")
            Do $$$AssertTrue(r.Error [ "did not answer; the operation may have been applied", class _ ": a person is told what it means: " _ r.Error)
            Set r = ..Classified(class, status, $$$OK)
            Do $$$AssertEquals(r.Outcome, "uncertain", class _ ", status [" _ status _ "]: no answer and no error is still unknown")
        }
    }
}

Method TestASocketThatNeverOpened()
{
    For class = "Shutter.Operation.Ward", "Hospital.Operation.DownstreamOut" {
        Do $$$AssertEquals(..Classified(class, 0, ..NeverOpened()).Outcome, "unavailable", class _ ": 6059 sent nothing")
        Set refused = $$$ERROR($$$GeneralError, "HTTP Connect failed for ward:8080 - Connection refused")
        Do $$$AssertEquals(..Classified(class, 0, refused).Outcome, "unavailable", class _ ": the wording is the fallback")
        Do $$$AssertNotTrue(..Classified(class, 0, refused).Error [ "may have been applied", class _ ": nothing was sent, so nothing may have been applied")
    }
}

/// A rehearsal's failure says what it shows: the receiver's refusal of the dry run shows the action would not apply, and
/// no answer, or the connector's own refusal with nothing sent, shows nothing.
Method TestARehearsalThatFailed()
{
    Set w = "Shutter.Process.CaseWorkflow", wouldNot = "would not apply", nothing = "shows nothing"
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "would_not_apply", 200) [ wouldNot, "the receiver said would not apply")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "refused", 422) [ wouldNot, "a 422 to the dry run is its answer")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "refused", 409) [ wouldNot, "a 409 to the dry run is its answer")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "version_conflict", 409) [ wouldNot, "so is a version conflict")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "refused", "") [ nothing, "the connector refused: nothing was sent")
    For outcome = "uncertain", "unavailable", "error" {
        Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", outcome, 0) [ nothing, outcome _ ", no answer: shows nothing")
    }
}

/// The words on the audit trail and in the forwarder's log, for a request nobody answered and for one that was answered.
Method TestTheWordsForNoAnswer()
{
    Set w = "Shutter.Process.CaseWorkflow", f = "Shutter.Intake.Forwarder"
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", 0, 0), "encounter no answer, receipt no answer", "neither lookup answered")
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", "", 503), "encounter no answer, receipt HTTP 503", "no status is no answer")
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", 200, 500), "encounter HTTP 200, receipt HTTP 500", "an answer keeps its status")
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", 0, -1), "encounter no answer, receipt not kept by this receiver", "a receiver with no receipts")
    For status = 0, "" {
        Set words = $CLASSMETHOD(f, "RefusalWords", status, ..TimedOut(), "", "/intake")
        Do $$$AssertTrue(words [ "No answer from Shutter at /intake", "status [" _ status _ "]: " _ words)
        Do $$$AssertTrue(words [ "5922", "and the adapter's reason is kept")
        Do $$$AssertNotTrue(words [ "HTTP 0", "with no HTTP 0")
    }
    Do $$$AssertEquals($CLASSMETHOD(f, "RefusalWords", 503, $$$OK, "{}", "/intake"), "HTTP 503 from Shutter: {}", "an answer is quoted")
    Do $$$AssertEquals($CLASSMETHOD(f, "RefusalWords", 500, $$$OK, "", "/intake"), "HTTP 500 from Shutter: empty body", "even an empty one")
}

/// An answer keeps its meaning: nothing above reaches a request that got one.
Method TestAnAnswerIsNotNoAnswer()
{
    For class = "Shutter.Operation.Ward", "Hospital.Operation.DownstreamOut" {
        Do $$$AssertEquals(..Classified(class, 504, $$$OK).Outcome, "uncertain", class _ ": 504, the lost acknowledgment of S3")
        Do $$$AssertEquals(..Classified(class, 503, $$$OK).Outcome, "unavailable", class _ ": 503")
        Do $$$AssertEquals(..Classified(class, 500, $$$OK).Outcome, "uncertain", class _ ": 500")
        Do $$$AssertEquals(..Classified(class, 201, $$$OK).Outcome, "applied", class _ ": 201")
        Do $$$AssertEquals(..Classified(class, 403, $$$OK).Outcome, "error", class _ ": 403")
    }
}

/// A preflight read that got no answer changes nothing at the receiver, so it is unavailable however it failed.
Method TestAReadNobodyAnswered()
{
    Set w = "Shutter.Operation.Ward"
    For status = 0, "" {
        For sc = ..TimedOut(), ..NeverOpened() {
            Set r = ##class(Shutter.Msg.WardResult).%New()
            Set r.HttpStatus = status
            Do $CLASSMETHOD(w, "ClassifyRead", r, sc, {}, "/state")
            Do $$$AssertEquals(r.Outcome, "unavailable", "status [" _ status _ "]: " _ r.Error)
            Do $$$AssertTrue(r.Error '= "", "and says why")
        }
    }
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = 200
    Do $CLASSMETHOD(w, "ClassifyRead", r, $$$OK, {"version": 3, "state": "admitted"}, "/state")
    Do $$$AssertEquals(r.Outcome _ "|" _ r.EncounterVersion, "read|3", "an answer is read")
}

}
