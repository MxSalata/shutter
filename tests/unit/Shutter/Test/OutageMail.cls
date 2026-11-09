/// Shutter.Operation.OutageMail: which events mail, how often, and an email that names no patient, control id or result.
Class Shutter.Test.OutageMail Extends %UnitTest.TestCase
{

/// The events that are states mail.on can name, and no others.
Method TestStateOf()
{
    Set c = "Shutter.Operation.OutageMail"
    Do $$$AssertEquals($CLASSMETHOD(c, "StateOf", "opened"), "open", "opened")
    Do $$$AssertEquals($CLASSMETHOD(c, "StateOf", "needs_person"), "needs_person", "needs_person")
    Do $$$AssertEquals($CLASSMETHOD(c, "StateOf", "closed"), "closed", "closed")
    For kind = "closing", "draining", "offered", "paused", "read_again", "overdue", "" { Do $$$AssertEquals($CLASSMETHOD(c, "StateOf", kind), "", "no email for " _ kind) }
}

/// Only a state on names, and at most one email every 10 minutes per receiver.
Method TestDue()
{
    Set c = "Shutter.Operation.OutageMail", on = ["open", "closed"]
    Do $$$AssertTrue($CLASSMETHOD(c, "Due", "open", on, "", "2026-11-09T04:00:00Z"), "open, never mailed")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Due", "needs_person", on, "", "2026-11-09T04:00:00Z"), "a state on does not name")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Due", "closed", on, "2026-11-09T03:55:00Z", "2026-11-09T04:00:00Z"), "5 minutes after the last")
    Do $$$AssertTrue($CLASSMETHOD(c, "Due", "closed", on, "2026-11-09T03:50:00Z", "2026-11-09T04:00:00Z"), "10 minutes after the last")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Due", "open", "", "", "2026-11-09T04:00:00Z"), "no on, no email")
}

/// The email: the receiver, the reading, the counts, the Do and Call lines and the page; none of the lists' rows.
Method TestComposeNamesNoPatient()
{
    Set row = {"headerId": "41", "controlId": "CTL-SECRET-41", "status": "Error", "attempts": "never_opened", "reason": "", "patient": {"id": "MRN-SECRET-9", "authority": "HOSP"}}
    Set o = {"id": "7", "receiver": "Results Out", "item": "Results Out", "namespace": "LABSITE", "state": "offered", "readings": {"reading": "cant_tell"}, "settled": {"completed": 3, "error": 2, "suspended": 1, "other": 0}, "lists": {"offered": [(row)], "queued": [], "reached": [], "refused": [(row)]}, "words": {"first": "Header 41 failed.", "do": "Do: start the listener.", "call": "Call: the lab on 01632 960998.", "critical": null}}
    Set m = ##class(Shutter.Operation.OutageMail).Compose(o, "needs_person", "https://shutter.example/shutter/index.html#/incidents")
    Do $$$AssertEquals(m.subject, "Shutter: Results Out, a person is needed", "the subject")
    For text = "Receiver: Results Out (Results Out in LABSITE)", "it reads offered", "The engine's reading: cant tell.", "Settled so far: 3 Completed, 2 Error, 1 Suspended, 0 set aside.", "1 message never reached the receiver and is listed on the page for a person. Shutter will not send them.", "Do: start the listener.", "Call: the lab on 01632 960998.", "https://shutter.example/shutter/index.html#/incidents" {
        Do $$$AssertTrue(m.body [ text, "says: " _ text)
    }
    For secret = "CTL-SECRET-41", "MRN-SECRET-9", "Header 41" { Do $$$AssertNotTrue((m.body _ m.subject) [ secret, "names no " _ secret) }
    Set m = ##class(Shutter.Operation.OutageMail).Compose(o, "open")
    Do $$$AssertTrue(m.body [ "on Shutter's Incidents page", "no link set: the page by name")
}

/// Escalation Mail writes an outage email as an .eml file when no mail server is set.
Method TestWritesAnEml()
{
    Set op = ##class(Shutter.Operation.EscalationMail).%New("Escalation Mail Test")
    Set op.OutputFolder = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory() _ "shutter-outage-mail-test")
    Set path = op.WriteNamed("outage-7-open-test.eml", "lab@nhs.net", "Shutter: Results Out, an outage opened", "Receiver: Results Out")
    Do $$$AssertTrue(##class(%File).Exists(path), "the file: " _ path)
    Set f = ##class(%Stream.FileCharacter).%New(), f.TranslateTable = "UTF8"
    Do f.LinkToFile(path)
    Set text = f.Read(32000)
    Do $$$AssertTrue(text [ "To: lab@nhs.net", "addressed")
    Do $$$AssertTrue(text [ "Receiver: Results Out", "the body")
    Kill f
    Do ##class(%File).Delete(path), ##class(%File).RemoveDirectory(op.OutputFolder)
}

}
