/// The rig's ADT namespace, on stock classes, with no pathology profile: one operation that fails at once, and one that retries for ever and raises only QueueCountAlert.
Class OraAdt.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="OraAdt.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Beds In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7531</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Beds Out</Setting>
  </Item>
  <Item Name="Beds Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7431</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Beds Queue In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7532</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Beds Queue Out</Setting>
  </Item>
  <Item Name="Beds Queue Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7432</Setting>
    <Setting Target="Host" Name="AlertOnError">0</Setting>
    <Setting Target="Host" Name="FailureTimeout">-1</Setting>
    <Setting Target="Host" Name="QueueCountAlert">2</Setting>
  </Item>
  <Item Name="Ora Say" ClassName="OraSite.Say" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="CallInterval">2</Setting>
  </Item>
  <Item Name="Ens.Alert" ClassName="OraSite.AlertLog" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
</Production>
}
}
