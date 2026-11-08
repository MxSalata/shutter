/// The one control row of this deployment: whether Shutter's recovery is stopped, and the generation every stop, clear and
/// mode change moves on (CONTRACTS 18). It lives in the data database, so a restart, a reinstall or a knowledge reseed
/// leaves it as it is. Only Shutter.Util.RecoveryControl writes it, under its lock.
Class Shutter.Store.RecoveryControl Extends %Persistent
{

Property Name As %String(MAXLEN = 32) [ InitialExpression = "current", Required ];

Index NameIdx On Name [ Unique ];

/// A generated id for this deployment, printed on the report's rows.
Property DeploymentId As %String(MAXLEN = 64);

/// Keys the report's patient references, so that nothing the report prints works one back. No route returns it.
Property ReportKey As %String(MAXLEN = 64);

/// Moves on at every stop, clear and mode change; never goes back.
Property Generation As %Integer [ InitialExpression = 1 ];

Property StopLatched As %Boolean [ InitialExpression = 0 ];

Property StoppedAt As %String(MAXLEN = 30);

Property StoppedBy As %String(MAXLEN = 160);

Property StopReason As %String(MAXLEN = 1000);

/// The newest plan id when the generation last moved. A plan at or under it was made before that change and is not
/// dispatched: it needs fresh evidence and a new plan.
Property PlanFloor As %Integer [ InitialExpression = 0 ];

Property LastChangedAt As %String(MAXLEN = 30);

Property LastChangedBy As %String(MAXLEN = 160);

}
