/// Creates the SHUTTER namespace (interoperability enabled) before the IPM module is loaded into it: the code in a
/// database of the image (${MGRDIR}SHUTTER), the data in a database under ${MGRDIR}shutter/db/, the directory
/// docker-compose.yml keeps in the shutter-mgr volume, so that cases, approvals, incidents and the configuration
/// survive `docker compose down` and `up`, and a rebuilt image brings new code to the same data (E7). Used by
/// iris.script during the image build; not part of the module.
/// It also creates the demo hospital's namespace, HOSPITAL (docs/CONTRACTS.md, section 11): its own code and data
/// databases, laid out like Shutter's, with the packages its production needs mapped from Shutter's code database
/// (Shutter.Intake, Shutter.Util, Shutter.Msg, Shutter.Store and Hospital), so nothing is loaded into it: the module
/// load compiles them in SHUTTER, and Hospital.Setup.Install, run in HOSPITAL afterwards, installs the production.
/// Shutter.Store is mapped because Shutter.Util.Time reads the feed's time zone through Shutter.Store.SiteProfile.
Class Shutter.Installer
{

XData Manifest [ XMLNamespace = INSTALLER ]
{
<Manifest>
  <Default Name="NAMESPACE" Value="SHUTTER"/>
  <Default Name="DBDIR" Value="${MGRDIR}${NAMESPACE}"/>
  <Default Name="DATADIR" Value="${MGRDIR}shutter/db/${NAMESPACE}DATA"/>
  <Default Name="HOSPITAL" Value="HOSPITAL"/>
  <Default Name="HOSPITALDBDIR" Value="${MGRDIR}${HOSPITAL}"/>
  <Default Name="HOSPITALDATADIR" Value="${MGRDIR}shutter/db/${HOSPITAL}DATA"/>
  <Namespace Name="${NAMESPACE}" Create="yes" Code="${NAMESPACE}" Data="${NAMESPACE}DATA" Ensemble="1">
    <Configuration>
      <Database Name="${NAMESPACE}" Dir="${DBDIR}" Create="yes" Resource="%DB_${NAMESPACE}"/>
      <Database Name="${NAMESPACE}DATA" Dir="${DATADIR}" Create="yes" Resource="%DB_${NAMESPACE}DATA"/>
    </Configuration>
  </Namespace>
  <!-- The demo hospital: a production that is not Shutter's, in a namespace of its own, with the packages it needs
       mapped from Shutter's code database. Its data (messages, the production's settings) lives in its own data
       database inside the volume, beside Shutter's. -->
  <Namespace Name="${HOSPITAL}" Create="yes" Code="${HOSPITAL}" Data="${HOSPITAL}DATA" Ensemble="1">
    <Configuration>
      <Database Name="${HOSPITAL}" Dir="${HOSPITALDBDIR}" Create="yes" Resource="%DB_${HOSPITAL}"/>
      <Database Name="${HOSPITAL}DATA" Dir="${HOSPITALDATADIR}" Create="yes" Resource="%DB_${HOSPITAL}DATA"/>
      <ClassMapping Package="Shutter.Intake" From="${NAMESPACE}"/>
      <ClassMapping Package="Shutter.Util" From="${NAMESPACE}"/>
      <ClassMapping Package="Shutter.Msg" From="${NAMESPACE}"/>
      <ClassMapping Package="Shutter.Store" From="${NAMESPACE}"/>
      <ClassMapping Package="Hospital" From="${NAMESPACE}"/>
    </Configuration>
  </Namespace>
</Manifest>
}

/// The demo hospital's namespace alone, for an instance that already has Shutter (a development instance, CI):
/// SELECT Shutter.Installer_RunHospital('SHUTTER') makes HOSPITAL with its databases and the package mappings from
/// that Shutter namespace. Hospital.Setup.Install, run in HOSPITAL afterwards, installs the production.
XData HospitalManifest [ XMLNamespace = INSTALLER ]
{
<Manifest>
  <Default Name="NAMESPACE" Value="SHUTTER"/>
  <Default Name="HOSPITAL" Value="HOSPITAL"/>
  <Default Name="HOSPITALDBDIR" Value="${MGRDIR}${HOSPITAL}"/>
  <Default Name="HOSPITALDATADIR" Value="${MGRDIR}shutter/db/${HOSPITAL}DATA"/>
  <Namespace Name="${HOSPITAL}" Create="yes" Code="${HOSPITAL}" Data="${HOSPITAL}DATA" Ensemble="1">
    <Configuration>
      <Database Name="${HOSPITAL}" Dir="${HOSPITALDBDIR}" Create="yes" Resource="%DB_${HOSPITAL}"/>
      <Database Name="${HOSPITAL}DATA" Dir="${HOSPITALDATADIR}" Create="yes" Resource="%DB_${HOSPITAL}DATA"/>
      <ClassMapping Package="Shutter.Intake" From="${NAMESPACE}"/>
      <ClassMapping Package="Shutter.Util" From="${NAMESPACE}"/>
      <ClassMapping Package="Shutter.Msg" From="${NAMESPACE}"/>
      <ClassMapping Package="Shutter.Store" From="${NAMESPACE}"/>
      <ClassMapping Package="Hospital" From="${NAMESPACE}"/>
    </Configuration>
  </Namespace>
</Manifest>
}

ClassMethod RunHospital(shutterNs As %String = "SHUTTER") As %String [ SqlProc ]
{
    If (shutterNs = "") || (shutterNs = $CHAR(0)) Set shutterNs = "SHUTTER"
    Set vars("NAMESPACE") = $ZCONVERT(shutterNs, "U")
    Set sc = ..setupHospital(.vars)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

ClassMethod setupHospital(ByRef pVars, pLogLevel As %Integer = 3, pInstaller As %Installer.Installer, pLogger As %Installer.AbstractLogger) As %Status [ CodeMode = objectgenerator, Internal ]
{
    Quit ##class(%Installer.Manifest).%Generate(%compiledclass, %code, "HospitalManifest")
}

/// Runs the manifest for <var>ns</var> (and the HOSPITAL namespace mapped from it) and returns "ok" or the error
/// text; callable over SQL (SELECT Shutter.Installer_Run('SHUTTER')) for an instance reached only through its REST API.
ClassMethod Run(ns As %String = "SHUTTER") As %String [ SqlProc ]
{
    Set vars("NAMESPACE") = $ZCONVERT(ns, "U")
    Set sc = ..setup(.vars)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// Runs the manifest. Variables: NAMESPACE (default SHUTTER), HOSPITAL (default HOSPITAL).
ClassMethod setup(ByRef pVars, pLogLevel As %Integer = 3, pInstaller As %Installer.Installer, pLogger As %Installer.AbstractLogger) As %Status [ CodeMode = objectgenerator, Internal ]
{
    Quit ##class(%Installer.Manifest).%Generate(%compiledclass, %code, "Manifest")
}

}
