/// Reaches the evidence operation's private building of a case's operation, for <class>Shutter.Test.EdgeRows</class>. It's
/// never added to a production.
Class Shutter.Test.EvidenceProbe Extends Shutter.Operation.Evidence
{

Method OperationFor(case As Shutter.Store.Case) As %DynamicObject
{
    Quit ..OperationOf(case)
}

}
