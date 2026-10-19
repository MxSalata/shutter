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
    Try {
        If ..Adapter.SMTPServer = "" {
            Set file = ..WriteFile(esc)
            Do esc.MarkSent("file", file)
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
                Do esc.MarkSent("smtp", "Accepted by " _ ..Adapter.SMTPServer _ " for " _ esc.ToAddr)
            }
        }
    } Catch ex {
        Do esc.MarkFailed(ex.DisplayString())
    }
    Quit $$$OK
}

/// The sender: the site profile's mail.from when the site set one, else this operation's From setting.
Method Sender() As %String
{
    Set from = $ZSTRIP(##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Mail(), "from"), "<>W")
    Quit $SELECT(from '= "": from, 1: ..From)
}

Method Mail(esc As Shutter.Store.Escalation) As %Net.MailMessage
{
    Set mail = ##class(%Net.MailMessage).%New()
    Set mail.From = ..Sender(), mail.Subject = esc.Subject, mail.Charset = "UTF-8"
    For i = 1:1:$LENGTH(esc.ToAddr, ",") { Set a = $ZSTRIP($PIECE(esc.ToAddr, ",", i), "<>W") Do:a'="" mail.To.Insert(a) }
    For i = 1:1:$LENGTH(esc.CcAddr, ",") { Set a = $ZSTRIP($PIECE(esc.CcAddr, ",", i), "<>W") Do:a'="" mail.Cc.Insert(a) }
    Do mail.TextData.Write(esc.Body)
    Quit mail
}

/// The email as an .eml file (RFC 5322, plain text), named after the case and the escalation.
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
    Do f.WriteLine("From: " _ ..Sender())
    Do f.WriteLine("To: " _ esc.ToAddr)
    Do:esc.CcAddr'="" f.WriteLine("Cc: " _ esc.CcAddr)
    Do f.WriteLine("Subject: " _ esc.Subject)
    Set ts = $ZTIMESTAMP
    Do f.WriteLine("Date: " _ $ZDATE(ts, 11) _ ", " _ $ZDATE(ts, 2) _ " " _ $ZTIME($PIECE(ts, ",", 2) \ 1, 1) _ " +0000")
    Do f.WriteLine("MIME-Version: 1.0")
    Do f.WriteLine("Content-Type: text/plain; charset=UTF-8")
    Do f.WriteLine("")
    Do f.Write(esc.Body)
    $$$ThrowOnError(f.%Save())
    Quit path
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.EscalationSend">
    <Method>OnEscalationSend</Method>
  </MapItem>
</MapItems>
}

}
