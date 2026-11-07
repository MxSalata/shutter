/// The routed production's rule: a message the function answers 1 for goes aside, and every message also goes to a second
/// target. A later check can load its own rule in place of this one and point the router at it.
Class V11Rig.Rule Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="V11Rig.Routed">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="held"><when condition="RigHold(Document,&quot;LIMS Out&quot;)"><send transform="" target="Aside Out"/><send transform="" target="Second Out"/><return/></when></rule>
<rule name="all"><when condition="1"><send transform="" target="LIMS Out"/><send transform="" target="Second Out"/><return/></when></rule>
</ruleSet>
</ruleDefinition>
}

}
