/// The rig's Documents namespace: an item named as Pathology's is (Results Out), and a schema category named as Pathology's
/// is with other contents (TRUSTLAB). Its receiver raises no alert yet, and it has no Ens.Alert.
Class OnbDocs.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="OnbDocs.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Docs In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7111</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">TRUSTLAB</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Docs Router</Setting>
  </Item>
  <Item Name="Docs Router" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">OnbDocs.Rule</Setting>
  </Item>
  <Item Name="Results Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7212</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
  </Item>
</Production>
}
}
