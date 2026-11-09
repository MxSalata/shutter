/// Sends escalations (T29) through the site's mail server: the SMTP server, port, TLS configuration and credentials
/// are the adapter's settings, set at first-time configuration (most NHS trusts use the NHS relay). With no SMTP
/// server set, each email is written as an .eml file to OutputFolder instead, so a demo or a test instance needs no
/// mail server. Either way the send is a message in the production, so it shows in the Visual Trace.
Class Shutter.Operation.EscalationMail Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.EMail.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.EMail.OutboundAdapter;

/// The sender's address.
Property From As %String(MAXLEN = 200) [ InitialExpression = "shutter@localhost" ];

/// Where emails are written when no SMTP server is set; empty means <mgr>/shutter/out/mail.
Property OutputFolder As %String(MAXLEN = 500);

Parameter SETTINGS = "From:Escalation,OutputFolder:Escalation";

Method OnEscalationSend(request As Shutter.Msg.EscalationSend, Output response As Ens.Response) As %Status
{
    Set response = ##class(Ens.Response).%New()
    Set esc = ##class(Shutter.Store.Escalation).%OpenId(request.EscalationId)
    If '$ISOBJECT(esc) Quit $$$ERROR($$$GeneralError, "No escalation " _ request.EscalationId)
    If esc.State '= "queued" Quit $$$OK
    // The last check before anything leaves: the subject and the addresses against the profile as it stands now (the
    // allowed domains may have changed since the send was accepted, or the row was changed outside the API). A refused
    // escalation fails with the reason on the timeline; it can be edited and sent again.
    Set problem = esc.Check(.field)
    If problem '= "" Do esc.MarkFailed("Refused before sending, " _ field _ ": " _ problem) Quit $$$OK
    // Shadow mode (CONTRACTS 18): nothing tells a team to correct a case nothing was done about.
    If ##class(Shutter.Util.RecoveryControl).MailSuppressed() Do esc.MarkFailed("Not sent: shadow mode sends no email, and enabling recovery does not send this one") Quit $$$OK
    Try {
        If ..Adapter.SMTPServer = "" {
            Set file = ..WriteFile(esc)
            Do esc.MarkSaved(file)
        } Else {
            Set mail = ..Mail(esc)
            Set sc = ..Adapter.SendMail(mail, .failed)
            If $$$ISERR(sc) {
                Do esc.MarkFailed($SYSTEM.Status.GetErrorText(sc))
            } ElseIf $DATA(failed) && $ISOBJECT(failed) && (failed.Count() > 0) {
                Set list = ""
                For i = 1:1:failed.Count() { Set list = list _ $SELECT(list = "": "", 1: ", ") _ failed.GetAt(i) }
                Do esc.MarkFailed("Refused for " _ list)
            } Else {
                Do esc.MarkSent("smtp", "The mail server " _ ..Adapter.SMTPServer _ " accepted it, which does not show anyone has read it" _ " for " _ esc.ToAddr)
            }
        }
    } Catch ex {
        Do esc.MarkFailed(ex.DisplayString())
    }
    Quit $$$OK
}

/// A reminder digest for cases left open (Shutter.Util.CaseReminderTask): by the same mail server, with nobody reviewing it,
/// so the last check is here. A digest that may no longer go, a mail server's refusal or no mail server at all fails it,
/// logged, and the next run builds it afresh; never the .eml file, which nobody would read and which would keep the
/// identifiers on disk.
Method OnReminderSend(request As Shutter.Msg.ReminderSend, Output response As Ens.Response) As %Status
{
    Set response = ##class(Ens.Response).%New()
    Set row = ##class(Shutter.Store.ReminderDigest).%OpenId(request.DigestId)
    If '$ISOBJECT(row) || (row.State '= "queued") Quit $$$OK
    // Shadow mode (CONTRACTS 18) holds this mail as it holds an escalation's, and the next run builds it afresh.
    If ##class(Shutter.Util.RecoveryControl).MailSuppressed() Do row.MarkFailed("Not sent: shadow mode sends no email") Quit $$$OK
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set settings = ##class(Shutter.Util.CaseReminder).Settings(profile)
    Set problem = row.SendProblem(##class(Shutter.Util.Time).NowUTC(), settings, ##class(Shutter.Store.SiteProfile).AllowedDomains())
    If (problem = "") && (..Adapter.SMTPServer = "") Set problem = "no mail server is set on this operation"
    If problem '= "" Do row.MarkFailed(problem) Quit $$$OK
    Set changed = row.ChangedSince(settings)
    If changed '= "" Do row.MarkFailed(changed, 1) Quit $$$OK
    Try {
        Set mail = ##class(%Net.MailMessage).%New()
        Set mail.From = ..Sender(), mail.Subject = ##class(Shutter.Util.Mail).HeaderValue(row.Subject), mail.Charset = "UTF-8"
        Do mail.To.Insert(##class(Shutter.Util.Mail).HeaderValue(row.Recipient))
        Do mail.TextData.Write(row.Body)
        Set sc = ..Adapter.SendMail(mail, .failed)
        If $$$ISERR(sc) {
            Do row.MarkFailed($SYSTEM.Status.GetErrorText(sc))
        } ElseIf $DATA(failed) && $ISOBJECT(failed) && (failed.Count() > 0) {
            Do row.MarkFailed("Refused for " _ failed.GetAt(1))
        } Else {
            Do row.MarkAccepted("The mail server " _ ..Adapter.SMTPServer _ " accepted it, which does not show anyone has read it")
        }
    } Catch ex {
        Do row.MarkFailed(ex.DisplayString())
    }
    Quit $$$OK
}

/// The sender: the site profile's mail.from when the site set one and it is a bare address, else this operation's From
/// setting (a profile stored before the address rules is warned about in the event log).
/// An outage email (Shutter.Operation.OutageMail): sent through the mail server when one is set, else written as an .eml
/// file to OutputFolder, as an escalation is. A failed send is logged; the outage's own record is unchanged by it.
Method OnOutageMailSend(request As Shutter.Msg.OutageMailSend, Output response As Ens.Response) As %Status
{
    Set response = ##class(Ens.Response).%New()
    Try {
        If ..Adapter.SMTPServer = "" {
            Set path = ..WriteNamed("outage-" _ request.OutageId _ "-" _ request.State _ "-" _ $TRANSLATE($ZDATETIME($ZTIMESTAMP, 8, 1), " :", "-") _ ".eml", request.ToAddr, request.Subject, request.Body)
            $$$LOGINFO("Outage " _ request.OutageId _ " (" _ request.State _ "): no mail server is set, so the email was written to " _ path)
        } Else {
            Set mail = ##class(%Net.MailMessage).%New()
            Set mail.From = ..Sender(), mail.Subject = ##class(Shutter.Util.Mail).HeaderValue(request.Subject), mail.Charset = "UTF-8"
            For i = 1:1:$LENGTH(request.ToAddr, ",") { Set a = ##class(Shutter.Util.Mail).HeaderValue($ZSTRIP($PIECE(request.ToAddr, ",", i), "<>W")) Do:a'="" mail.To.Insert(a) }
            Do mail.TextData.Write(request.Body)
            Set sc = ..Adapter.SendMail(mail, .failed)
            If $$$ISERR(sc) $$$LOGWARNING("Outage " _ request.OutageId _ ": the mail server refused the email: " _ $SYSTEM.Status.GetErrorText(sc))
        }
    } Catch err {
        $$$LOGWARNING("Outage " _ request.OutageId _ ": the email was not sent: " _ err.DisplayString())
    }
    Quit $$$OK
}

/// An .eml file named name in OutputFolder, with the same headers an escalation's file has.
Method WriteNamed(name As %String, to As %String, subject As %String, body As %String) As %String
{
    Set dir = ..OutputFolder
    If dir = "" Set dir = ##class(%File).NormalizeDirectory(##class(%File).SubDirectoryName($SYSTEM.Util.ManagerDirectory(), "shutter/out/mail"))
    Do ##class(%File).CreateDirectoryChain(dir)
    Set path = ##class(%File).NormalizeFilename(name, dir)
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.TranslateTable = "UTF8", f.LineTerminator = $CHAR(13, 10)
    $$$ThrowOnError(f.LinkToFile(path))
    Do ..Header(f, "From", ..Sender())
    Do ..Header(f, "To", to)
    Do ..Header(f, "Subject", subject)
    Set ts = $ZTIMESTAMP
    Do ..Header(f, "Date", $ZDATE(ts, 11) _ ", " _ $ZDATE(ts, 2) _ " " _ $ZTIME($PIECE(ts, ",", 2) \ 1, 1) _ " +0000")
    Do ..Header(f, "MIME-Version", "1.0")
    Do ..Header(f, "Content-Type", "text/plain; charset=UTF-8")
    Do f.WriteLine("")
    Do f.Write(body)
    $$$ThrowOnError(f.%Save())
    Quit path
}

Method Sender() As %String
{
    Set from = $ZSTRIP(##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Mail(), "from"), "<>W")
    If (from '= "") && (##class(Shutter.Util.Mail).ShapeProblem(from) '= "") {
        $$$LOGWARNING("The site profile's mail.from (" _ ##class(Shutter.Util.Mail).HeaderValue(from) _ ") is not a bare address; the operation's From setting is used instead")
        Set from = ""
    }
    Quit $SELECT(from '= "": from, 1: ..From)
}

Method Mail(esc As Shutter.Store.Escalation) As %Net.MailMessage
{
    Set mail = ##class(%Net.MailMessage).%New()
    Set mail.From = ..Sender(), mail.Subject = ##class(Shutter.Util.Mail).HeaderValue(esc.Subject), mail.Charset = "UTF-8"
    For i = 1:1:$LENGTH(esc.ToAddr, ",") { Set a = ##class(Shutter.Util.Mail).HeaderValue($ZSTRIP($PIECE(esc.ToAddr, ",", i), "<>W")) Do:a'="" mail.To.Insert(a) }
    For i = 1:1:$LENGTH(esc.CcAddr, ",") { Set a = ##class(Shutter.Util.Mail).HeaderValue($ZSTRIP($PIECE(esc.CcAddr, ",", i), "<>W")) Do:a'="" mail.Cc.Insert(a) }
    Do mail.TextData.Write(esc.Body)
    Quit mail
}

/// The email as an .eml file (RFC 5322, plain text), named after the case and the escalation. Every header goes
/// through Header, so no value can end its line or start another header.
Method WriteFile(esc As Shutter.Store.Escalation) As %String
{
    Set dir = ..OutputFolder
    If dir = "" Set dir = ##class(%File).NormalizeDirectory(##class(%File).SubDirectoryName($SYSTEM.Util.ManagerDirectory(), "shutter/out/mail"))
    Do ##class(%File).CreateDirectoryChain(dir)
    Set path = ##class(%File).NormalizeFilename(esc.Case.CaseId _ "-escalation-" _ esc.Seq _ ".eml", dir)
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.TranslateTable = "UTF8", f.LineTerminator = $CHAR(13, 10)
    Set sc = f.LinkToFile(path)
    $$$ThrowOnError(sc)
    Do ..Header(f, "From", ..Sender())
    Do ..Header(f, "To", esc.ToAddr)
    Do:esc.CcAddr'="" ..Header(f, "Cc", esc.CcAddr)
    Do ..Header(f, "Subject", esc.Subject)
    Set ts = $ZTIMESTAMP
    Do ..Header(f, "Date", $ZDATE(ts, 11) _ ", " _ $ZDATE(ts, 2) _ " " _ $ZTIME($PIECE(ts, ",", 2) \ 1, 1) _ " +0000")
    Do ..Header(f, "MIME-Version", "1.0")
    Do ..Header(f, "Content-Type", "text/plain; charset=UTF-8")
    Do f.WriteLine("")
    Do f.Write(esc.Body)
    $$$ThrowOnError(f.%Save())
    Quit path
}

/// One header of the .eml: the value's control characters become spaces (Shutter.Util.Mail.HeaderValue), so the
/// header stays one logical line, and a line longer than 78 characters is folded at a space or a comma with CRLF and
/// one space (RFC 5322 2.2.3); a line with nowhere to fold is written whole.
Method Header(f As %Stream.FileCharacter, name As %String, value As %String) [ Private ]
{
    Set text = name _ ": " _ ##class(Shutter.Util.Mail).HeaderValue(value)
    // The first line keeps the header's name and at least one character of its value; a continuation line keeps its
    // leading space and at least one character.
    Set least = $LENGTH(name) + 4
    While $LENGTH(text) > 78 {
        Set cut = 0
        For i = 78:-1:least { If " ," [ $EXTRACT(text, i) Set cut = i Quit }
        Quit:cut=0
        // The fold replaces the space it breaks at, so the unfolded header reads exactly as the value; after a comma
        // the continuation's leading space is the one the list may already carry.
        Set head = $EXTRACT(text, 1, cut), rest = $EXTRACT(text, cut + 1, *)
        If $EXTRACT(head, *) = " " {
            Set head = $EXTRACT(head, 1, * - 1)
        } Else {
            Set rest = $ZSTRIP(rest, "<W")
        }
        Do f.WriteLine(head)
        Set text = " " _ rest, least = 3
    }
    Do f.WriteLine(text)
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.EscalationSend">
    <Method>OnEscalationSend</Method>
  </MapItem>
  <MapItem MessageType="Shutter.Msg.ReminderSend">
    <Method>OnReminderSend</Method>
  </MapItem>
  <MapItem MessageType="Shutter.Msg.OutageMailSend">
    <Method>OnOutageMailSend</Method>
  </MapItem>
</MapItems>
}

}
