/// The rig's Pathology namespace, as a hospital has it: order comms to a LIMS and results back, on stock classes, with a
/// schema of its own and its own alert consumer under the name Ens.Alert. Nothing of Shutter's is in it.
Class OnbPath.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="OnbPath.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="OrderComms In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7101</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Path Router</Setting>
  </Item>
  <Item Name="LIMS Results In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7102</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">TRUSTLAB</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Path Router</Setting>
  </Item>
  <Item Name="Path Router" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">OnbPath.Rule</Setting>
  </Item>
  <Item Name="LIMS Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true" Comment="As a hospital runs MLLP: retries forever">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7201</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">-1</Setting>
  </Item>
  <Item Name="Results Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7202</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Ens.Alert" ClassName="OnbSite.AlertLog" PoolSize="1" Enabled="true">
  </Item>
</Production>
}
}
