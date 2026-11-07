/// That the mail server accepted a case's reminder for a threshold (CONTRACTS 6.4, reminders): one row per case and threshold,
/// written when it took the digest, not that anyone read it, so a case is reminded once per threshold and a restart keeps it.
Class Shutter.Store.CaseReminder Extends %Persistent
{

Property Case As Shutter.Store.Case [ Required ];

/// team, the first threshold; officer, the later one.
Property Threshold As %String(MAXLEN = 16, VALUELIST = ",team,officer") [ Required ];

Index CaseThreshold On (Case, Threshold) [ Unique ];

Property Recipient As %String(MAXLEN = 320);

Property DigestId As %String(MAXLEN = 20);

Property AcceptedAt As %String(MAXLEN = 30);

/// The thresholds already sent for a case's row id, as an array.
ClassMethod Thresholds(caseRowId As %String) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Threshold FROM Shutter_Store.CaseReminder WHERE ""Case"" = ? ORDER BY ID", caseRowId)
    While rs.%Next() { Do out.%Push(rs.%Get("Threshold")) }
    Quit out
}

Storage Default
{
<Data name="CaseReminderDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Threshold</Value>
</Value>
<Value name="4">
<Value>Recipient</Value>
</Value>
<Value name="5">
<Value>DigestId</Value>
</Value>
<Value name="6">
<Value>AcceptedAt</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.CaseReminderD</DataLocation>
<DefaultData>CaseReminderDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CaseReminderD</IdLocation>
<IndexLocation>^Shutter.Store.CaseReminderI</IndexLocation>
<StreamLocation>^Shutter.Store.CaseReminderS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
