# Interlock on InterSystems IRIS for Health Community with AI Hub.
# The contest build is irishealth-community:2026.3.0AI.154.0, loaded and tagged as the README says.
# Any IRIS for Health Community 2026.2 or later builds the core (replay) edition: pass IRIS_IMAGE as a build argument.
ARG IRIS_IMAGE=irishealth-community:2026.3.0AI.154.0
FROM ${IRIS_IMAGE}

USER root
WORKDIR /home/irisowner/dev
RUN chown ${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} /home/irisowner/dev
USER ${ISC_PACKAGE_MGRUSER}

COPY --chown=irisowner:irisowner . /home/irisowner/dev

# The demo users (operator, approver, wards-client) are created with this password when the image is built.
ARG INTERLOCK_DEMO_PASSWORD=interlock

# Create the namespace, install the package manager and load the module while the image is built,
# so that `docker compose up` starts an instance that is ready.
RUN iris start IRIS \
 && INTERLOCK_DEMO_PASSWORD="${INTERLOCK_DEMO_PASSWORD}" iris session IRIS < /home/irisowner/dev/iris.script \
 && iris stop IRIS quietly
