# Troubleshooting

The README's "Troubleshooting" in full. The health report is `curl http://localhost:52773/api/shutter/health`; more about running Shutter: [running.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/running.md).

- **`install.sh` stops at a check.** It prints `[fix]` with what to do for each one, and changes nothing until every check passes. A port in use: `SHUTTER_WEB_PORT` is the web app's, `SHUTTER_SUPERSERVER_PORT` is 1972, IRIS's own; with no `.env` yet, `SHUTTER_SUPERSERVER_PORT=1973 ./install.sh --replay` keeps it in the `.env` it creates, and otherwise set it in `.env`.
- **Not healthy after 25 minutes.** `install.sh` prints the last 30 lines of the log and the health address; `curl http://localhost:52773/api/shutter/health` is the report to read.
- **The Doctor.** In the Management Portal's SQL page (namespace `SHUTTER`, as `_SYSTEM`), `SELECT Shutter.Setup_Doctor()`: `missing_items` and `disabled_items` should be `[]`, `production_state` `running`, `board_members` 5 (the board's four and the single investigator), `recordings` more than 0 (174 on build 109: every recording, not only the board's 100 runs) and `second_parser` `probe: ok` ([the values on build 109](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt-109.md)).
- **"License limit exceeded" or "Service Unavailable".** The Community licence's connections are used up, usually by repeated sign-ins: about eight on build 154, and signing out doesn't free them at once. The web app carries on, but new Management Portal sessions and terminals are refused; restarting the container (`docker compose restart`) frees them.
- **On the first start,** `ERROR #5002 ... Sharding` and "Error trading CSP licenses" come from the IRIS image and are harmless.
- **`install.sh` says the AI Hub image is too small.** The load was cut short; load the file again (a complete load is about 5.4 GB of content, from the 5.5 GB file).
