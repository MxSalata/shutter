/// The rig's documents namespace: a stock TCP service and router, and stock TCP operations whose names say what each is for.
/// The sending application's MSH-5 picks the route. Docs Out has a document profile and its receiver is down unless a check
/// starts a listener; Docs Refuse Out has a profile and its listener answers by control id; Docs Plain Out has no profile at
/// all; Docs Half Out is named on the forwarder and has no profile, so the forwarder must fall back to the ordinary intake.
Class DocSite.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="DocSite.Production" TestingEnabled="false" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Docs In" ClassName="EnsLib.HL7.Service.TCPService" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="Port">7311</Setting>
    <Setting Target="Adapter" Name="StayConnected">0</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5.1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">Docs Router</Setting>
  </Item>
  <Item Name="Docs Router" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="BusinessRuleName">DocSite.Rule</Setting>
  </Item>
  <Item Name="Docs Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7312</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">2</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
  <Item Name="Docs Refuse Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7313</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">2</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
  <Item Name="Docs Plain Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7314</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">2</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
  <Item Name="Docs Half Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7315</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">2</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
  </Item>
</Production>
}
}
