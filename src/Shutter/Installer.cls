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
  <Default Name="MGRDIR" Value="#{##class(%File).ManagerDirectory()}"/>
  <Default Name="DBDIR" Value="${MGRDIR}${NAMESPACE}"/>
  <!-- Not DATADIR: %Installer predefines that name as the instance's install directory, and a Default never replaces a
       variable that exists, so the data database landed at /usr/irissys/, inside the image and outside the volume
       (found 1 Nov 2026 on the upgrade proof: every case was lost on a rebuild, and would be on docker compose down). -->
  <Default Name="SHUTTERDATADIR" Value="${MGRDIR}shutter/db/${NAMESPACE}DATA"/>
  <Default Name="HOSPITAL" Value="HOSPITAL"/>
  <Default Name="HOSPITALDBDIR" Value="${MGRDIR}${HOSPITAL}"/>
  <Default Name="HOSPITALDATADIR" Value="${MGRDIR}shutter/db/${HOSPITAL}DATA"/>
  <Default Name="RECORDS" Value="RECORDS"/>
  <Default Name="RECORDSDBDIR" Value="${MGRDIR}${RECORDS}"/>
  <Default Name="RECORDSDATADIR" Value="${MGRDIR}shutter/db/${RECORDS}DATA"/>
  <Namespace Name="${NAMESPACE}" Create="yes" Code="${NAMESPACE}" Data="${NAMESPACE}DATA" Ensemble="1">
    <Configuration>
      <Database Name="${NAMESPACE}" Dir="${DBDIR}" Create="yes" Resource="%DB_${NAMESPACE}"/>
      <Database Name="${NAMESPACE}DATA" Dir="${SHUTTERDATADIR}" Create="yes" Resource="%DB_${NAMESPACE}DATA"/>
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
  <!-- The demo records system (v1.25): the demo receiver package once more, in a namespace of its own with its own data,
       so a second receiver of category history_of_record stands beside the bed manager; its web application
       /records/api is made by Shutter.Setup (InstallRecords), which also sets its demo flag. -->
  <Namespace Name="${RECORDS}" Create="yes" Code="${RECORDS}" Data="${RECORDS}DATA" Ensemble="0">
    <Configuration>
      <Database Name="${RECORDS}" Dir="${RECORDSDBDIR}" Create="yes" Resource="%DB_${RECORDS}"/>
      <Database Name="${RECORDS}DATA" Dir="${RECORDSDATADIR}" Create="yes" Resource="%DB_${RECORDS}DATA"/>
      <ClassMapping Package="Downstream" From="${NAMESPACE}"/>
    </Configuration>
  </Namespace>
</Manifest>
}

/// The demo records system's namespace alone (v1.25), for an instance that already has Shutter (a development instance,
/// CI): the demo receiver package mapped from Shutter's code database, its own data database.
XData RecordsManifest [ XMLNamespace = INSTALLER ]
{
<Manifest>
  <Default Name="NAMESPACE" Value="SHUTTER"/>
  <Default Name="MGRDIR" Value="#{##class(%File).ManagerDirectory()}"/>
  <Default Name="RECORDS" Value="RECORDS"/>
  <Default Name="RECORDSDBDIR" Value="${MGRDIR}${RECORDS}"/>
  <Default Name="RECORDSDATADIR" Value="${MGRDIR}shutter/db/${RECORDS}DATA"/>
  <Namespace Name="${RECORDS}" Create="yes" Code="${RECORDS}" Data="${RECORDS}DATA" Ensemble="0">
    <Configuration>
      <Database Name="${RECORDS}" Dir="${RECORDSDBDIR}" Create="yes" Resource="%DB_${RECORDS}"/>
      <Database Name="${RECORDS}DATA" Dir="${RECORDSDATADIR}" Create="yes" Resource="%DB_${RECORDS}DATA"/>
      <ClassMapping Package="Downstream" From="${NAMESPACE}"/>
    </Configuration>
  </Namespace>
</Manifest>
}

/// Makes the RECORDS namespace (RecordsManifest) and then its web application and demo flag (Shutter.Setup.InstallRecords).
/// SELECT Shutter.Installer_RunRecords('SHUTTER') on an instance reached through its REST API.
ClassMethod RunRecords(shutterNs As %String = "SHUTTER") As %String [ SqlProc ]
{
    If (shutterNs = "") || (shutterNs = $CHAR(0)) Set shutterNs = "SHUTTER"
    Set vars("NAMESPACE") = $ZCONVERT(shutterNs, "U")
    // The manifest once: run again on an instance that has the namespace, it only renews the web application and the roles.
    Set sc = $SELECT(..NamespaceExists("RECORDS"): $$$OK, 1: ..setupRecords(.vars))
    If $$$ISOK(sc) {
        New $NAMESPACE
        Set $NAMESPACE = $ZCONVERT(shutterNs, "U")
        Set sc = $CLASSMETHOD("Shutter.Setup", "InstallRecords", "RECORDS")
    }
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// Makes the demo's two other namespaces when they are missing, for Shutter.Setup's demo install: a load on a stock
/// instance has had no image build to make them first, so the records system would answer 404 and the hospital's
/// scenarios would wait for a case that never comes. Setup's own steps then find them, as they do in an image.
ClassMethod EnsureDemoNamespaces(shutterNs As %String) As %Status
{
    Set vars("NAMESPACE") = $ZCONVERT(shutterNs, "U"), sc = $$$OK
    If '..NamespaceExists("RECORDS") Set sc = ..setupRecords(.vars)
    If $$$ISOK(sc) && '..NamespaceExists("HOSPITAL") Set sc = ..setupHospital(.vars)
    Quit sc
}

/// Whether a namespace exists, read in %SYS.
ClassMethod NamespaceExists(ns As %String) As %Boolean
{
    Set exists = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set exists = ##class(Config.Namespaces).Exists(ns)
    } Catch ex {
    }
    Quit exists
}

ClassMethod setupRecords(ByRef pVars, pLogLevel As %Integer = 3, pInstaller As %Installer.Installer, pLogger As %Installer.AbstractLogger) As %Status [ CodeMode = objectgenerator, Internal ]
{
    Quit ##class(%Installer.Manifest).%Generate(%compiledclass, %code, "RecordsManifest")
}

/// The demo hospital's namespace alone, for an instance that already has Shutter (a development instance, CI):
/// SELECT Shutter.Installer_RunHospital('SHUTTER') makes HOSPITAL with its databases and the package mappings from
/// that Shutter namespace. Hospital.Setup.Install, run in HOSPITAL afterwards, installs the production.
XData HospitalManifest [ XMLNamespace = INSTALLER ]
{
<Manifest>
  <Default Name="NAMESPACE" Value="SHUTTER"/>
  <Default Name="MGRDIR" Value="#{##class(%File).ManagerDirectory()}"/>
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
    // The manifest once: a demo install may have made it already (EnsureDemoNamespaces).
    Set sc = $SELECT(..NamespaceExists("HOSPITAL"): $$$OK, 1: ..setupHospital(.vars))
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
