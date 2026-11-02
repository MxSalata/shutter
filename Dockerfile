# Shutter on InterSystems IRIS for Health Community with AI Hub.
# The contest build is irishealth-community:2026.3.0AI.154.0, loaded and tagged as the README says.
# Any IRIS for Health Community 2026.2 or later builds the core (replay) edition: pass IRIS_IMAGE as a build argument.
ARG IRIS_IMAGE=irishealth-community:2026.3.0AI.154.0
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

# auto (the default) loads the aihub module (live agents) when the image has the AI Hub package and skips it on a plain
# IRIS for Health Community base, which gets the replay edition; 1 requires it and fails the build without it; 0 skips it.
ARG WITH_AIHUB=auto

# Read by the installer while the image is built (empty keeps the defaults: the demo password shutter, a purge of 90 days).
# The rest of .env (the live hospital, the budget, the public demo's logins) is container environment, applied each time the
# production starts (docker-compose.yml, Shutter.Setup.ApplyEnvironment): never a build argument, which the image's history
# would keep.
ARG SHUTTER_DEMO_PASSWORD=
ARG SHUTTER_MESSAGE_DAYS=
ARG SHUTTER_MESSAGE_PURGE=
ARG SHUTTER_ESCALATION_DAYS=

# Create the namespace, install the package manager (the pinned installer in vendor/ipm) and load the
# modules while the image is built, so that `docker compose up` starts an instance that is ready. A
# step that fails ends its session with exit code 1 and fails the build, so no image is made that
# would answer 404. The production is set to start with the instance; SHUTTER_BUILD tells the install
# not to start it here.
RUN iris start IRIS \
 && SHUTTER_BUILD=1 SHUTTER_DEMO_PASSWORD="${SHUTTER_DEMO_PASSWORD}" SHUTTER_MESSAGE_DAYS="${SHUTTER_MESSAGE_DAYS}" SHUTTER_MESSAGE_PURGE="${SHUTTER_MESSAGE_PURGE}" SHUTTER_ESCALATION_DAYS="${SHUTTER_ESCALATION_DAYS}" iris session IRIS < /home/irisowner/dev/iris.script \
 && SHUTTER_BUILD=1 SHUTTER_WITH_AIHUB="${WITH_AIHUB}" iris session IRIS < /home/irisowner/dev/aihub.script \
 && iris stop IRIS quietly
