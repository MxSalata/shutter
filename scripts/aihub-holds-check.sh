#!/usr/bin/env bash
# What the README's AI Hub feedback says about a build, asked of a stock instance of that build with no model call.
#
#   scripts/aihub-holds-check.sh IMAGE [CONTAINER]
#
# IMAGE is a plain AI Hub Community image: no Shutter on it, because Shutter's install rebuilds the descriptor registry
# and would hide the first question. The container runs with no network, so no provider can be reached whatever a probe
# does, and it is removed at the end (KEEP=1 leaves it). Prints one line per probe, starting RESULT, with what the
# instance answered, and exits 1 only when a probe could not run.
#
# Asked:
# - does a fresh Config Store take an AI.LLM configuration before %ConfigStore.DescriptorManager.RebuildRegistry(),
#   in USER and in a namespace made here?
# - does an agent's %Init() take a provider named @{config:Name}, and does it refuse the bare name?
# - what does %AI.Policy.Audit declare for %LogExecution, and does a subclass compile with and without As %Status?
# - how many arguments does %AI.Agent.Run take, and is IPM in the image?
set -euo pipefail

image=${1:?usage: aihub-holds-check.sh IMAGE [CONTAINER]}
ctr=${2:-shutter-aihub-holds}
cleanup() { [ "${KEEP:-0}" = 1 ] || docker rm -f "$ctr" > /dev/null 2>&1 || true; }
trap cleanup EXIT

docker rm -f "$ctr" > /dev/null 2>&1 || true
docker run -d --name "$ctr" --network none "$image" --check-caps false --ISCAgent false > /dev/null
up=0
for _ in $(seq 1 60); do
  if docker exec "$ctr" iris qlist IRIS 2>/dev/null | grep -q '\^running'; then up=1; break; fi
  sleep 5
done
[ "$up" = 1 ] || { echo "the instance did not start"; docker logs "$ctr" 2>&1 | tail -50; exit 1; }
sleep 5
echo "image $image"
docker exec "$ctr" iris list IRIS | grep -i -m1 'version' || true

# A class file in the container; the name is the class's.
put() { docker exec -i "$ctr" sh -c "cat > /tmp/$1.cls"; }

put ZProbe.Holds <<'CLS'
Class ZProbe.Holds
{

/// A namespace with a database of its own, as a site's would be.
ClassMethod MakeNamespace(ns As %String) As %Status
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set dir = ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ $ZCONVERT(ns, "L"))
    Do ##class(%File).CreateDirectoryChain(dir)
    Set sc = ##class(SYS.Database).CreateDatabase(dir)
    If $$$ISERR(sc) Quit sc
    Kill props
    Set props("Directory") = dir
    Set sc = ##class(Config.Databases).Create(ns, .props)
    If $$$ISERR(sc) Quit sc
    Kill props
    Set props("Globals") = ns, props("Routines") = ns
    Quit ##class(Config.Namespaces).Create(ns, .props)
}

/// The text of a status, or of what was thrown.
ClassMethod Text(sc) As %String
{
    If $ISOBJECT(sc) Quit "threw " _ sc.DisplayString()
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

ClassMethod CreateConfig(name As %String) As %String
{
    Try {
        Set config = {"model_provider": "anthropic", "model": "probe-no-model", "api_key": "probe-no-key"}
        Set answer = ..Text(##class(%ConfigStore.Configuration).Create("AI", "LLM", "", name, config))
    } Catch ex {
        Set answer = ..Text(ex)
    }
    Quit answer
}

ClassMethod Rebuild() As %String
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("%ConfigStore.DescriptorManager") Quit "no such class"
    Try {
        Do ##class(%ConfigStore.DescriptorManager).RebuildRegistry()
        Set answer = "ran"
    } Catch ex {
        Set answer = ..Text(ex)
    }
    Quit answer
}

ClassMethod Registry(label As %String)
{
    Write !,"RESULT registry, ",label,", Create before any rebuild: ",..CreateConfig("ProbeBefore")
    Write !,"RESULT registry, ",label,", RebuildRegistry: ",..Rebuild()
    Write !,"RESULT registry, ",label,", Create after the rebuild: ",..CreateConfig("ProbeAfter")
}

ClassMethod InitAgent(class As %String) As %String
{
    Try {
        Set agent = $CLASSMETHOD(class, "%New")
        Set answer = ..Text(agent.%Init())
    } Catch ex {
        Set answer = ..Text(ex)
    }
    Quit answer
}

ClassMethod Spec(class As %String, method As %String) As %String
{
    Set m = ##class(%Dictionary.CompiledMethod).%OpenId(class _ "||" _ method)
    If '$ISOBJECT(m) Quit "no such method"
    Quit "returns [" _ m.ReturnType _ "], abstract " _ m.Abstract _ ", arguments (" _ m.FormalSpec _ ")"
}

ClassMethod Rest()
{
    Write !,"RESULT provider, @{config:ProbeAfter}: %Init ",..InitAgent("ZProbe.AgentNamed")
    Write !,"RESULT provider, bare ProbeAfter: %Init ",..InitAgent("ZProbe.AgentBare")
    Write !,"RESULT provider, @{config:NoSuchName}: %Init ",..InitAgent("ZProbe.AgentMissing")
    Write !,"RESULT %AI.Policy.Audit %LogExecution: ",..Spec("%AI.Policy.Audit", "%LogExecution")
    Write !,"RESULT %AI.Agent Run: ",..Spec("%AI.Agent", "Run")
    Write !,"RESULT IPM in the image: ",$SELECT(##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main"): "yes", 1: "no")
}

}
CLS

agent() {
  put "ZProbe.$1" <<CLS
Class ZProbe.$1 Extends %AI.Agent
{

Parameter PROVIDERCONFIG = "$2";

Parameter MODEL = "probe-no-model";

}
CLS
}
agent AgentNamed '@{config:ProbeAfter}'
agent AgentBare 'ProbeAfter'
agent AgentMissing '@{config:NoSuchName}'

audit() {
  put "ZProbe.$1" <<CLS
Class ZProbe.$1 Extends %AI.Policy.Audit
{

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status)$2
{
    $3
}

}
CLS
}
audit AuditTyped ' As %Status' 'Return $$$OK'
audit AuditUntyped '' 'Quit'

session() { docker exec -i "$ctr" iris session IRIS -U "$1"; }
results() { grep -E '^(USER>|PROBENS>)?RESULT' | sed -E 's/^(USER>|PROBENS>)//' | tee -a /tmp/aihub-holds.$$ || true; }

load() { # class, namespace, and what to print
  printf '%s\n' "Set sc = \$SYSTEM.OBJ.Load(\"/tmp/$1.cls\", \"ck-d\") Write !,\"RESULT compile $1: \",\$SELECT(\$SYSTEM.Status.IsOK(sc): \"ok\", 1: \$SYSTEM.Status.GetErrorText(sc)),!" 'Halt' | session "$2" | results
}

load ZProbe.Holds USER
out=$(printf '%s\n' 'Set sc = ##class(ZProbe.Holds).MakeNamespace("PROBENS") Write !,"RESULT namespace PROBENS: ",##class(ZProbe.Holds).Text(sc),!' 'Halt' | session USER)
echo "$out" | results
load ZProbe.Holds PROBENS

# The namespace made here first, then USER: neither has had a rebuild yet.
printf '%s\n' 'Do ##class(ZProbe.Holds).Registry("a new namespace")' 'Write !' 'Halt' | session PROBENS | results
printf '%s\n' 'Do ##class(ZProbe.Holds).Registry("USER")' 'Write !' 'Halt' | session USER | results

for class in AgentNamed AgentBare AgentMissing AuditTyped AuditUntyped; do load "ZProbe.$class" USER; done
printf '%s\n' 'Do ##class(ZProbe.Holds).Rest()' 'Write !' 'Halt' | session USER | results

want=$(grep -c 'RESULT' /tmp/aihub-holds.$$ || true)
rm -f /tmp/aihub-holds.$$
echo "$want answers"
[ "$want" -ge 20 ] || { echo "some probes did not answer"; exit 1; }
