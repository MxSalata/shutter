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

}
