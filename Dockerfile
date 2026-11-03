# Shutter on InterSystems IRIS for Health Community with AI Hub.
# The AI Hub builds are irishealth-community:2027.1.0AI.109.0 and 2026.3.0AI.154.0, loaded and tagged as the README says.
# Any IRIS for Health Community 2026.2 or later builds the core (replay) edition: pass IRIS_IMAGE as a build argument.
ARG IRIS_IMAGE=irishealth-community:2027.1.0AI.109.0
FROM ${IRIS_IMAGE}

USER root
WORKDIR /home/irisowner/dev
RUN chown ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /home/irisowner/dev
USER ${ISC_PACKAGE_MGRUSER}

COPY --chown=irisowner:irisowner . /home/irisowner/dev

# The Second Parser (docs/CONTRACTS.md, 6.1): HAPI and its dependencies from Maven Central, each checked against the SHA-256
# pinned in pex/build.sh in the same step (a mismatch fails the build), and shutter.pex compiled with the image's own JDK into
# the manager directory (mgr/pex, beside the data volume mgr/shutter and not inside it, so an upgraded container runs this
# image's jar), where the production item's classpath expects it. The step never fails the image: without a JDK, a PEX
# framework jar, network or a matching checksum it prints why and leaves no jar, and the item stays off. PEX_STRICT=1 (CI's
# image job, on an image known to carry the framework) makes such a skip fail the build instead.
ARG PEX_STRICT=0
RUN PEX_STRICT="${PEX_STRICT}" bash /home/irisowner/dev/pex/build.sh /usr/irissys/mgr/pex

# auto (the default) loads the full package (the root module: core and live agents) when the image has the AI Hub package,
# and the core module alone (core/module.xml, the replay edition) on a plain IRIS for Health Community base; 1 requires
# AI Hub and fails the build without it; 0 loads the core alone whatever the image has.
ARG WITH_AIHUB=auto

# Read by the installer while the image is built (empty keeps the defaults: a purge of 90 days). The demo users' password
# (SHUTTER_DEMO_PASSWORD, default shutter) comes in as a BuildKit secret, never a build argument: a build argument's value
# is printed in the build log and kept in the image's history (docker history). docker-compose.yml sources the secret from
# the environment or .env; a plain docker build passes --secret id=shutter_demo_password,env=SHUTTER_DEMO_PASSWORD; with no
# secret the default applies (the mount is world-readable, since the install runs as irisowner, not root). The rest of .env (the live hospital, the budget, the public demo's logins) is container
# environment, applied each time the production starts (Shutter.Setup.ApplyEnvironment).
ARG SHUTTER_MESSAGE_DAYS=
ARG SHUTTER_MESSAGE_PURGE=
ARG SHUTTER_ESCALATION_DAYS=

# Create the namespace, install the package manager (the pinned installer in vendor/ipm) and load the
# modules while the image is built, so that `docker compose up` starts an instance that is ready. A
# step that fails ends its session with exit code 1 and fails the build, so no image is made that
# would answer 404. The production is set to start with the instance; SHUTTER_BUILD tells the install
# not to start it here.
RUN --mount=type=secret,id=shutter_demo_password,mode=0444 iris start IRIS \
 && SHUTTER_BUILD=1 SHUTTER_WITH_AIHUB="${WITH_AIHUB}" SHUTTER_DEMO_PASSWORD="$(cat /run/secrets/shutter_demo_password 2>/dev/null || true)" SHUTTER_MESSAGE_DAYS="${SHUTTER_MESSAGE_DAYS}" SHUTTER_MESSAGE_PURGE="${SHUTTER_MESSAGE_PURGE}" SHUTTER_ESCALATION_DAYS="${SHUTTER_ESCALATION_DAYS}" iris session IRIS < /home/irisowner/dev/iris.script \
 && iris stop IRIS quietly
