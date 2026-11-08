/// Whose a production name is, for the install into a site's own production (shape B) and its uninstall. The module
/// compiles its own packages (Shutter, and the demo's Hospital and Downstream) wherever it is loaded, and the package
/// manager removes them whole on uninstall, so a site's production in one of them cannot take Shutter's items safely.
Class Shutter.Util.SiteProduction
{

/// The module's packages, as class name prefixes.
Parameter PACKAGES = "Shutter.,Hospital.,Downstream.";

/// "" when Shutter's items may go into this production; otherwise why not, in plain words. Class packages differ by
/// more than case in IRIS, so the comparison ignores case.
ClassMethod InstallRefusal(production As %String) As %String
{
    Set upper = $ZCONVERT(production, "U")
    For i = 1:1:$LENGTH(..#PACKAGES, ",") {
        Set prefix = $PIECE(..#PACKAGES, ",", i)
        If $EXTRACT(upper, 1, $LENGTH(prefix)) = $ZCONVERT(prefix, "U") {
            Return "The production " _ production _ " is in the " _ $EXTRACT(prefix, 1, *-1) _ " package, which Shutter's module loads and its uninstall removes whole: loading Shutter replaces a class of the same name there. Copy the production to a package of your own and install into that"
        }
    }
    Quit ""
}

/// Whether the uninstall removes this production definition (name), given the production Shutter's items live in
/// (production, from Setup.ProductionName()): Shutter's own, and the demo hospital's, but never the production Shutter's
/// items went into. In Shutter's own namespace any Hospital. production is the demo's; in a site's namespace only
/// Hospital.Production by its exact name, which the module compiles wherever it is loaded.
ClassMethod DefinitionGoes(name As %String, production As %String) As %Boolean
{
    If (production '= "Shutter.Production") && (name = production) Quit 0
    If $EXTRACT(name, 1, 8) = "Shutter." Quit 1
    If production = "Shutter.Production" Quit $EXTRACT(name, 1, 9) = "Hospital."
    Quit name = "Hospital.Production"
}

}
