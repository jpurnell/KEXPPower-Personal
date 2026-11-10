# Spinner's diagnostics schema

`spinner-schema.json` is what Spinner may send to the diagnostics hub: each kind of event, its fields, and the channels that may send it. It is the source of truth. `FieldEventTests` validates every event the app can produce against it, so the app and the file cannot drift apart.

**Adding or changing a kind** (fields are only ever added; bump `version`):
1. Write the failing test, then the `FieldEvent` case, then the schema entry.
2. Copy the file's contents into Spinner's entry in the hub's apps file (`schema`), keep the entry's `key` and `bundleID`, and restart the hub: it validates the file when it starts and refuses a schema that allows free text from the App Store channel.

**Checking an event arrived:** the hub keeps raw events for 30 days; see the hub's README.
