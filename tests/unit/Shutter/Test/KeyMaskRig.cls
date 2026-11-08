/// The end-to-end check's rig (tests/e2e/key_mask_check.py): sets an agent item's settings in the running production and
/// puts them back. Not a test case.
Class Shutter.Test.KeyMaskRig
{

/// Sets <var>item</var>'s ProviderConfig, Model and Mode (each only when given) in Shutter's production and applies the
/// change, which restarts the item. Returns "ok" or the error.
ClassMethod Arm(item As %String, providerConfig As %String = "", model As %String = "", mode As %String = "") As %String [ SqlProc ]
{
    Set out = "ok"
    Try {
        Set prod = ##class(Ens.Config.Production).%OpenId(##class(Shutter.Setup).ProductionName())
        If '$ISOBJECT(prod) Quit
        Set it = ""
        For i = 1:1:prod.Items.Count() { If prod.Items.GetAt(i).Name = item Set it = prod.Items.GetAt(i) Quit }
        If '$ISOBJECT(it) Set out = "no item " _ item Quit
        For pair = $LISTBUILD("ProviderConfig", providerConfig), $LISTBUILD("Model", model), $LISTBUILD("Mode", mode) {
            Set name = $LIST(pair, 1), value = $LIST(pair, 2)
            Continue:value = ""
            Do ..Put(it, name, $SELECT(value = "-": "", 1: value))
        }
        $$$ThrowOnError(prod.%Save())
        $$$ThrowOnError(##class(Ens.Director).UpdateProduction(60, 1))
    } Catch ex {
        Set out = ex.DisplayString()
    }
    Quit out
}

/// Sets one Host setting of an item, adding it when the item has none, or removes it when <var>value</var> is "".
ClassMethod Put(it As Ens.Config.Item, name As %String, value As %String)
{
    For j = it.Settings.Count():-1:1 {
        Set st = it.Settings.GetAt(j)
        If st.Name = name Do it.Settings.RemoveAt(j)
    }
    Quit:value = ""
    Set st = ##class(Ens.Config.Setting).%New()
    Set st.Name = name, st.Target = "Host", st.Value = value
    Do it.Settings.Insert(st)
}

}
