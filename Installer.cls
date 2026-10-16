/// Creates the INTERLOCK namespace (interoperability enabled) before the IPM module is loaded into it.
/// Used by iris.script during the image build; not part of the module.
Class Interlock.Installer
{

XData Manifest [ XMLNamespace = INSTALLER ]
{
<Manifest>
  <Default Name="NAMESPACE" Value="INTERLOCK"/>
  <Default Name="DBDIR" Value="${MGRDIR}${NAMESPACE}"/>
  <Namespace Name="${NAMESPACE}" Create="yes" Code="${NAMESPACE}" Data="${NAMESPACE}" Ensemble="1">
    <Configuration>
      <Database Name="${NAMESPACE}" Dir="${DBDIR}" Create="yes" Resource="%DB_${NAMESPACE}"/>
    </Configuration>
  </Namespace>
</Manifest>
}

/// Runs the manifest for <var>ns</var> and returns "ok" or the error text; callable over SQL
/// (SELECT Interlock.Installer_Run('INTERLOCK')) for an instance reached only through its REST API.
ClassMethod Run(ns As %String = "INTERLOCK") As %String [ SqlProc ]
{
    Set vars("NAMESPACE") = $ZCONVERT(ns, "U")
    Set sc = ..setup(.vars)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// Runs the manifest. Variables: NAMESPACE (default INTERLOCK).
ClassMethod setup(ByRef pVars, pLogLevel As %Integer = 3, pInstaller As %Installer.Installer, pLogger As %Installer.AbstractLogger) As %Status [ CodeMode = objectgenerator, Internal ]
{
    Quit ##class(%Installer.Manifest).%Generate(%compiledclass, %code, "Manifest")
}

}
