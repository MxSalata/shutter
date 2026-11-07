/// The rig's routed namespace, on stock classes but its rule's function: a service, a router, and three receivers behind it.
/// LIMS Out retries for ever; Second Out and Aside Out don't retry. Nothing of Shutter's is in it.
Class V11Rig.Routed Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="V11Rig.Routed" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Routed In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7601</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Routed Router</Setting>
  </Item>
  <Item Name="Routed Router" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">V11Rig.Rule</Setting>
  </Item>
  <Item Name="LIMS Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7701</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">-1</Setting>
  </Item>
  <Item Name="Second Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7702</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Aside Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7703</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
  <Item Name="Ens.Alert" ClassName="V11Rig.AlertLog" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
</Production>
}
}
