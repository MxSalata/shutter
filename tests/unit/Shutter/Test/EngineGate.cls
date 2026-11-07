/// The gate with its engine read answered from what a Shutter.Test.Gate row says, so every answer can be run with no production.
/// The table and everything after it are the real ones.
Class Shutter.Test.EngineGate Extends Shutter.Operation.Gate
{

ClassMethod EngineRow(case As Shutter.Store.Case) As %DynamicObject
{
    Quit ##class(Shutter.Util.EngineCheck).Judge(##class(%DynamicObject).%FromJSON(^||Shutter.Test.EngineFacts))
}

}
