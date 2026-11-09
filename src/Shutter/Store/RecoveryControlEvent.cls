/// The control's history, append only: who stopped, cleared or changed the mode, when and why, with the calls that were
/// still outstanding at that moment.
Class Shutter.Store.RecoveryControlEvent Extends %Persistent
{

Property At As %String(MAXLEN = 30);

/// The signed-in user, "system" for a stop the control latched itself, or "install".
Property Actor As %String(MAXLEN = 160);

Property Action As %String(MAXLEN = 16, VALUELIST = ",stop,clear_stop,mode_change,demo_reset");

Property OldGeneration As %Integer;

Property NewGeneration As %Integer;

Property OldState As %String(MAXLEN = 32);

Property NewState As %String(MAXLEN = 32);

Property Reason As %String(MAXLEN = 1000);

Property OutstandingCount As %Integer [ InitialExpression = 0 ];

/// The first of them, by permit id, comma separated.
Property OutstandingIds As %String(MAXLEN = 1000);

Storage Default
{
<Data name="RecoveryControlEventDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>At</Value>
</Value>
<Value name="3">
<Value>Actor</Value>
</Value>
<Value name="4">
<Value>Action</Value>
</Value>
<Value name="5">
<Value>OldGeneration</Value>
</Value>
<Value name="6">
<Value>NewGeneration</Value>
</Value>
<Value name="7">
<Value>OldState</Value>
</Value>
<Value name="8">
<Value>NewState</Value>
</Value>
<Value name="9">
<Value>Reason</Value>
</Value>
<Value name="10">
<Value>OutstandingCount</Value>
</Value>
<Value name="11">
<Value>OutstandingIds</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.RecoveryCont4C2D</DataLocation>
<DefaultData>RecoveryControlEventDefaultData</DefaultData>
<IdLocation>^Shutter.Store.RecoveryCont4C2D</IdLocation>
<IndexLocation>^Shutter.Store.RecoveryCont4C2I</IndexLocation>
<StreamLocation>^Shutter.Store.RecoveryCont4C2S</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
