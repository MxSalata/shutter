/// One outage email for Escalation Mail to send, or to write as an .eml file when no mail server is set. It names the
/// receiver, its reading, the counts, the Do and Call lines and the page, and never a patient, a control id or a result.
Class Shutter.Msg.OutageMailSend Extends Ens.Request
{

Property OutageId As %String(MAXLEN = 20);

/// The outage state the email is about: open, needs_person or closed.
Property State As %String(MAXLEN = 16);

/// The receiver's mail.to, comma-separated, each address checked by the site profile.
Property ToAddr As %String(MAXLEN = 2000);

Property Subject As %String(MAXLEN = 300);

Property Body As %String(MAXLEN = 20000);

Storage Default
{
<Data name="OutageMailSendDefaultData">
<Subscript>"OutageMailSend"</Subscript>
<Value name="1">
<Value>OutageId</Value>
</Value>
<Value name="2">
<Value>State</Value>
</Value>
<Value name="3">
<Value>ToAddr</Value>
</Value>
<Value name="4">
<Value>Subject</Value>
</Value>
<Value name="5">
<Value>Body</Value>
</Value>
</Data>
<DefaultData>OutageMailSendDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
