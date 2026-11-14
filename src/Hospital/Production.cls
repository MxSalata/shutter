/// The demo hospital's PAS feed: a production that is not Shutter's, in its own namespace (HOSPITAL), watched by
/// Shutter the way a trust's production would be (docs/CONTRACTS.md, section 11). Its process delivers ADT to the ward
/// system and hands each failed delivery to Shutter through the forwarder; the case then appears in Shutter's own
/// production with the source recorded on it. Beside it, a results route (category "Lab", since 1.4.6): Lab In feeds
/// laboratory results to Lab Results Out, a stock HL7 TCP operation that Shutter watches for outages, whose receiver is a
/// stand-in inside this instance (Results System In); the pathology paths of the Scenarios page play through it. The
/// folders, the two addresses and the results route's loopback port come from system default settings written by
/// Hospital.Setup, so this definition carries none.
Class Hospital.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Hospital.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>The demo hospital's PAS feed: not Shutter's production. ADT goes to the ward system and results to the demo's results system; a failed delivery is handed to Shutter.</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="PAS In" Category="Feed" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" Comment="The hospital's ADT messages, one per file" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="CallInterval">1</Setting>
    <Setting Target="Adapter" Name="DeleteFromServer">1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">PAS to Downstream</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="AckMode">Never</Setting>
    <Setting Target="Host" Name="UseAckCommitCodes">0</Setting>
  </Item>
  <Item Name="PAS to Downstream" Category="Feed" ClassName="Hospital.Process.PASToDownstream" PoolSize="1" Enabled="true" Foreground="false" Comment="Builds the ward operation, delivers it, hands a failure to Shutter" LogTraceEvents="true" Schedule="">
  </Item>
  <Item Name="Downstream Out" Category="Feed" ClassName="Hospital.Operation.DownstreamOut" PoolSize="1" Enabled="true" Foreground="false" Comment="The hospital's own connector to the ward system (the demo bed-management system)" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">DownstreamAPI</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
  <Item Name="Ens.Alert" Category="Shutter" ClassName="Shutter.Intake.AlertProcess" PoolSize="1" Enabled="true" Foreground="false" Comment="The alerts the hospital's items raise: a delivery failure's message goes to Shutter through the forwarder, once per session; every alert is passed on to the site's own consumer when PassTo names one" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="Receivers">Downstream Out,Lab Results Out</Setting>
  </Item>
  <Item Name="Lab In" Category="Lab" ClassName="Hospital.Service.LabFeed" PoolSize="0" Enabled="true" Foreground="false" Comment="The demo's results route: the pathology paths of the Scenarios page play their results through it, to the results system's connector" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="TargetConfigName">Lab Results Out</Setting>
  </Item>
  <Item Name="Lab Results Out" Category="Lab" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="The hospital's connector to the demo's results system: a stock HL7 TCP operation, which Shutter watches for outages; the port is a default setting (Hospital.Setup)" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
  <Item Name="Results System In" Category="Lab" ClassName="Hospital.Service.LabReceiver" PoolSize="1" Enabled="true" Foreground="false" Comment="A stand-in for the demo's results system inside this instance, on a loopback port: it answers each result (AE for a test code it does not know) and files nothing" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="JobPerConnection">0</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
  </Item>
  <Item Name="Live PAS" Category="Feed" ClassName="Hospital.LivePlayer" PoolSize="1" Enabled="false" Foreground="false" Comment="The live hospital's PAS: one of Shutter's scenarios every few minutes with fresh patients at present times and real faults, and an ordinary message a minute between them; on only when the install was told live" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="CallInterval">5</Setting>
  </Item>
  <Item Name="Shutter Forwarder" Category="Shutter" ClassName="Shutter.Intake.Forwarder" PoolSize="1" Enabled="true" Foreground="false" Comment="Hands a failed delivery to Shutter's intake, so that a case opens in Shutter's own production" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="Credentials">ShutterIntake</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">5</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
</Production>
}

}
