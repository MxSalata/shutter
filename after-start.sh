#!/bin/sh
# Runs after IRIS has started in the container (iris-main --after). A container whose image ran IRIS during
# the build logs a "failed over from node <build host>" alert at its first start, and the AI Hub preview build
# logs a startup error of its own; Docker's health check reads the monitor's state, so these two known
# alerts are cleared and any other alert is left alone. Then the state and the outcome are logged.
sleep 5
iris session IRIS -U INTERLOCK "write \"Interlock after-start: \", ##class(Interlock.Setup).ClearStartupAlerts(), !" 2>&1
