/// Sends a reminder digest for cases left open: the "Escalation Mail" operation mails it through the site's mail server.
Class Shutter.Msg.ReminderSend Extends Ens.Request
{

/// The Shutter.Store.ReminderDigest's id.
Property DigestId As %String(MAXLEN = 20);

Storage Default
{
<Data name="ReminderSendDefaultData">
<Subscript>"ReminderSend"</Subscript>
<Value name="1">
<Value>DigestId</Value>
</Value>
</Data>
<DefaultData>ReminderSendDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
