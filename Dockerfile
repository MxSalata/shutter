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

# 1 loads the aihub module (live agents) too: for images with the AI Hub package. 0 for a plain
# IRIS for Health Community base, which gets the replay edition.
ARG WITH_AIHUB=1

# Create the namespace, install the package manager and load the modules while the image is built,
# so that `docker compose up` starts an instance that is ready. The production is set to start with
# the instance; SHUTTER_BUILD tells the install not to start it here.
RUN iris start IRIS \
 && SHUTTER_BUILD=1 iris session IRIS < /home/irisowner/dev/iris.script \
 && if [ "${WITH_AIHUB}" = "1" ]; then SHUTTER_BUILD=1 iris session IRIS < /home/irisowner/dev/aihub.script; fi \
 && iris stop IRIS quietly
