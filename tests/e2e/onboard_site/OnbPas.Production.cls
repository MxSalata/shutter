/// The rig's PAS namespace: ADT to a bed manager. A person gives its receiver an API in the site profile after onboarding,
/// and a recovery can then be seen at /beds/api.
Class OnbPas.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="OnbPas.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="PAS In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7121</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Bed Mgmt Out</Setting>
  </Item>
  <Item Name="Bed Mgmt Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7221</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
</Production>
}
}
