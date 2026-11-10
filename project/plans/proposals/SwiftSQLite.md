# Design Proposal: SwiftSQLite (one shared, dependency-free SQLite wrapper)

**Status:** PROPOSED 2026-11-09. Owner: wants one reusable package extracted from the best of the hand-written SQLite wrappers in the portfolio, with each project migrated onto it later. Written in the KEXPPower repository for review; **on approval it moves to the new sibling repository `SwiftSQLite`** (created from the development-guidelines template as a sibling directory, not nested). No existing repository was modified and nothing was built for this survey.

**Facts marked (repo) were read on 2026-11-09 from the files named. Anything about Linux, SQLite's behavior, toolchains or code that was not read is marked *unverified*.**

---

## 1. Objective

One small Swift 6 package, `SwiftSQLite`, over the system SQLite library (no third-party dependency), that owns the parts every portfolio store re-implements: opening with safe flags and an owner-only file, a busy timeout, prepared and *bound* statements, typed rows, transactions, versioned migrations, a typed error, and an in-memory open for tests. Domain stores (an outbox, a registry, an issue table) stay in their own packages and become thin: SQL and mapping only.

## 2. Motivation

**Current situation (repo).** 21 non-test files across 8 working copies import `SQLite3` or `CSQLite`; after removing the duplicates, there are **12 distinct wrapper implementations of the same ~40 lines** (open, prepare, bind, step, finalize), 5 of them in one package:

- SwiftPushHub: 5 files (`SQLiteEventOutbox`, `SQLiteDeviceOwnership`, `SQLiteDevicePreferences`, `SQLiteEnrollmentStore`, `SQLiteObservationStateStore`), each with its own private `query` function.
- FleetWatch (and `FleetWatch-infoplist`): `SQLiteDatabase.swift` (an enum of static functions) plus `FleetStore` and `MachineRegistry`, which hold their own handles.
- SwiftPush (and `SwiftPush-send-cli`): `SQLiteDeviceRegistry.swift` (the two copies are byte-identical, `diff -q` printed nothing).
- VaultMCP: `SQLiteStore.swift` (1,325 lines) with an internal `DatabaseHandle`.
- SwiftDiagnosticsHub: `SQLiteStore.swift`, built today by copying SwiftPushHub's pattern.
- swift-oauth: `OAuthStorage.swift` over its own `CSQLite` system-library target (read only by grep; see §3).

**Workaround today:** copy the previous file and adapt it. **Drawbacks (repo, see §3):** the copies have drifted in ways that matter. Only 2 of 12 set a busy timeout, only 2 have any schema versioning, only 1 binds integers as integers (the others bind numbers as text and rely on column affinity), one has a data-loss-shaped `step` loop, and the owner-only file mode is applied *after* the file is created. A fix to one does not reach the others.

## 3. Survey of Existing Code

### 3.1 Per-project record (all (repo))

| | SwiftPushHub (5 files) | SwiftPush / send-cli | FleetWatch (+infoplist) | VaultMCP | SwiftDiagnosticsHub | swift-oauth |
|---|---|---|---|---|---|---|
| Handle owner | `actor`, `private nonisolated(unsafe) let db`, `// Justification:` comment | same | `actor` x2 (`FleetStore`, `MachineRegistry`), same unsafe + comment; `SQLiteDatabase` is an enum of static funcs over a caller-owned pointer | `final class SQLiteStore: Sendable` holding `DatabaseHandle: @unchecked Sendable` (comment: serialized by `VaultIndex` actor) | `actor`, same unsafe + comment | an actor (`OAuthStorage`); detail not read |
| Open flags | READWRITE, CREATE, **FULLMUTEX** | same | same | READWRITE/CREATE or **READONLY** (an `AccessMode`); **no FULLMUTEX** | same as Hub | `sqlite3_open` (no flags); *detail unverified* |
| WAL | no | no | no | **yes**, `journal_mode=WAL`, `synchronous=NORMAL`, writer only | no | not seen |
| File mode 0600 | yes, **after** schema exec | yes, after | yes, after (`mode:` parameter) | **no** | yes, after | not seen |
| Busy timeout | **none** | none | **5 s** | **5 s**, configurable | **none** | not seen |
| Statement helper | private `query(sql, [String], columns:)` per file | same | static `query(db, sql, [Parameter], columns:)` | `DatabaseHandle.execute/executeMultiple/query` | `run(sql, [SQLValue]) -> [Row]` | inline `sqlite3_*` |
| Binding types | **text only** (numbers pass as text strings) | text only (booleans as `"1"`/`"0"`) | text, **real**, null | text, int, double, **blob**, null | text, **int64**, null | mixed |
| Int vs Int64 | n/a (text); `LIMIT \(limit)` interpolated | n/a | n/a (reals; `Double(maxEvents)` for LIMIT) | `bind_int64(Int64(n))` from `Int`; `Int(column_int64)` | **`.int(Int64)`**, `Int64(limit)` bound; ms dates | `column_int` (32-bit) for `user_version` |
| Row reading | `[[String]]`, parse with `Int64(row[2])` | `[[String]]` | `[[String]]`, JSON `documents` table | `[[SQLiteValue]]` enum (text/int/double/blob/null) | `Row` of `SQLValue` with typed accessors that throw `.corrupt` | inline |
| Transactions | none in outbox (check-then-insert, select-then-delete); `BEGIN IMMEDIATE` in registry | `BEGIN IMMEDIATE`, logged ROLLBACK | `BEGIN IMMEDIATE`, logged ROLLBACK | **`withTransaction { }`** helper, `BEGIN IMMEDIATE` | inline `BEGIN IMMEDIATE`, `Result { ROLLBACK }` | in migrations |
| Schema/migrations | `CREATE TABLE IF NOT EXISTS` only | same (+`PRAGMA foreign_keys=ON`) | same | **`PRAGMA user_version`**, `schemaTooNew`, add-column steps, fresh-vs-legacy detection, in a transaction | same as Hub (none yet) | **`user_version`**, ~10 ordered migrations, one with a data rewrite and a rollback path; `schemaVersion:` init parameter so a test can build an old DB |
| Error type | per-package (`OutboxError.storage/.corrupt`) | `RegistryError` | `StoreError` | `SQLiteError` (open/prepare/execution/bind/schemaTooNew) | `StoreError.storage/.corrupt` | `OAuthStorageError` |
| Test seam | protocol + `InMemory*` actor per store | protocol + in-memory | `FleetStoreTests` use real temp files | `":memory:"` accepted by path | **contract suite run over `.memory` and `.sqlite`** (`StoreKind.allCases`) | `:memory:` accepted |
| Targets | macOS 15 (+iOS 17 for the package; the hub itself runs on a Mac) | Apple-only (own Package.swift comment) | Apple-only server (Package.swift: "Apple-only (Network, Security, CryptoKit, the SDK's SQLite3)") | macOS 14 | macOS 14, iOS 17, watchOS 10, tvOS 17, visionOS 1 (platform list only; the hub is a server) | has a Linux `CSQLite` system-library target |

Tools versions (repo): SwiftPush, SwiftPushHub, FleetWatch, VaultMCP, SwiftReleaseKit, swift-oauth are all `swift-tools-version: 6.2`; **SwiftDiagnosticsHub is 6.4**. SwiftPush's manifest records why 6.2 is deliberate: "a manifest newer than the host's toolchain cannot be resolved there." The deployment host's Swift was reported as 6.4.1 in the owner's notes (*not re-verified today*), but SwiftReleaseKit's manifest calls 6.2 "the oldest manifest the portfolio's hosts all resolve". **Recommend `swift-tools-version: 6.2` for SwiftSQLite**; SwiftDiagnosticsHub's 6.4 is a difference to reconcile when it migrates (it can depend on a 6.2 package; the reverse would not resolve on a 6.2-only host).

### 3.2 Best practice from each

- **SwiftDiagnosticsHub:** typed `Row` accessors that throw `.corrupt` instead of crashing on a wrong type; Int64 binding; a contract test suite run over both the in-memory and SQLite implementations; `milliseconds` helper (but see bug 7).
- **FleetWatch:** busy timeout as a named constant with a stated reason (a second process, the CLI); `mode:` parameter instead of a hard-coded constant; `.real` binding.
- **VaultMCP:** `AccessMode.readOnly` enforced at the SQLite layer; WAL with the reason written down; `withTransaction` that rolls back and rethrows; `user_version` with a `schemaTooNew` refusal; the fresh-database-versus-unversioned-legacy distinction; `pragma_table_info(?)` with a bound parameter; blob binding; configurable busy timeout; tests that stamp `user_version` directly rather than through a test-only hook.
- **swift-oauth:** migration testing by letting the test open a database at an *older* schema version; a data migration with rollback; a Linux `CSQLite` system-library target with the Apple-vs-Linux pkg-config reasoning written in the manifest.
- **SwiftPushHub / SwiftPush:** the `// Justification:` comment on the single `nonisolated(unsafe)`; `FULLMUTEX`; redacted logging of failures with `privacy: .public` only on SQLite's own message; `PRAGMA foreign_keys = ON`.

### 3.3 Real bugs and unsafe patterns seen (not fixed; flagged for the owner)

1. **VaultMCP `DatabaseHandle.query` ignores how the loop ended.** `while sqlite3_step(stmt) == SQLITE_ROW { ... }` followed by `return rows`: a `SQLITE_BUSY` or error mid-iteration returns a *partial result as success*. Also `execute` accepts `SQLITE_ROW` as success.
2. **VaultMCP NULL and overflow traps.** `String(cString: sqlite3_column_text(...))` is passed a possibly-nil pointer for `SQLITE_TEXT` columns (it does not guard as the other wrappers do), and `Int32(nsData.length)` traps for a blob over 2 GiB. Closed with `sqlite3_close`, not `_v2`.
3. **VaultMCP thread-safety rests on a comment.** `SQLiteStore` is a plain `final class` marked `Sendable`; the handle is `@unchecked Sendable` "serialized through the VaultIndex actor"; the database is opened **without `FULLMUTEX`**, and `withTransaction` is a synchronous method on the class, so nothing in the type stops two callers interleaving statements inside one transaction. (Whether anything does call it that way is *unverified*; I read only the store.)
4. **The 0600 window.** In every wrapper that sets a mode, `sqlite3_open_v2(... CREATE)` and the schema `exec` create the file with the process umask (typically 0644) and *then* `setAttributes(0o600)`. For SwiftPushHub's outbox (the text of every alert) and the device registries (every device token) that is a window in which the file is world-readable. VaultMCP never restricts the file. Whether `-wal` and `-shm` sidecars inherit the main file's mode is *unverified* (I believe SQLite copies it; a test must prove it).
5. **No busy timeout in 8 of 12 wrappers** (all five SwiftPushHub stores, SwiftPush, SwiftDiagnosticsHub). The DiagnosticsHub proposal plans a separate `diag` CLI process reading the same file as the server: the first concurrent write fails *immediately* with `SQLITE_BUSY` and surfaces as `.storage`. Without WAL a reader blocks a writer too.
6. **No migrations in the five newest stores.** `CREATE TABLE IF NOT EXISTS` never alters an existing table: the first column added after a deployment makes every statement against the old file fail at prepare. Only VaultMCP and swift-oauth can evolve a schema.
7. **SwiftDiagnosticsHub silently corrupts out-of-range dates.** `milliseconds(_:)` returns `0` for a date that does not fit, i.e. the event is stored as 1970-01-01 and, because `expires_at` is also 0, purged at the next sweep. Its `Row` has no real/blob case: `SQLITE_FLOAT` and `SQLITE_BLOB` fall to the `default` branch and come back as *text*.
8. **Text-bound numbers and interpolated SQL (SwiftPushHub, SwiftPush).** Integers and booleans are bound as text and work only because the column has INTEGER affinity; an expression comparison without a column would compare as strings. `LIMIT \(limit)` and `IN (\(finished))` are interpolated (checked and from a closed enum today, so not injectable, but it is the pattern the safety rules should make impossible to write by accident). `columnNames(table:)` in SwiftDiagnosticsHub splices a name filtered by `Character.isLetter`, which accepts non-ASCII letters.
9. **Check-then-write races across processes.** `SQLiteEventOutbox.enqueue` (select id, then insert), `expireOverdue` and `purge` (select ids, then update/delete, to count them) are not in a transaction. The actor protects them within one process; a second process (CLI) does not honor the actor. `enqueue` would surface a duplicate as `.storage`, not `.duplicateID`. (Counts could use `sqlite3_changes` instead.)
10. **Inconsistent time storage.** Hubs: INTEGER milliseconds; FleetWatch: REAL seconds; VaultMCP: ISO strings. Each fine alone; a shared package should offer one typed helper and say which is the default.
11. **`sqlite3_open` (not `_v2`) in swift-oauth, 32-bit `column_int` for `user_version`** (grep only; *unverified* beyond that).
12. **Drifted copies.** `FleetWatch-infoplist/SQLiteDatabase.swift` has no `.null` parameter that `FleetWatch/SQLiteDatabase.swift` has (repo, diff): the copy is already behind.

## 4. Proposed Architecture

**New repository `SwiftSQLite`**, one library product plus one test-support product:

```
Sources/SwiftSQLite/
  SQLiteDatabase.swift        actor: open/close, execute, query, scalar, transaction
  SQL.swift                   SQL (literal-only statement text), SQLIdentifier
  SQLiteValue.swift           value enum, SQLiteBindable conformances
  SQLiteRow.swift             typed row reading
  SQLiteMigration.swift       Migration + runner
  SQLiteError.swift           typed error and result-code mapping
  FilePermissions.swift       create-with-0600 before SQLite opens the file
Sources/CSwiftSQLite/         system-library target, Linux only (see §9)
Sources/SwiftSQLiteTesting/   TemporaryDatabase, BusyLock, corrupt-file helpers (test-only product)
Tests/SwiftSQLiteTests/
```

`SQLiteDatabase` is the only type that touches the C API; everything else is a value type. Domain stores hold (or are) an actor that owns a `SQLiteDatabase`, or take the `SQLiteDatabase` actor directly and add no second layer of isolation. The package defines **no store protocol**: the `EventOutbox` / `DiagnosticsStore` protocols and their `InMemory*` twins stay in the domain packages.

## 5. API Surface

```swift
// MARK: Statement text: literals only
/// SQL text that can only be written as a string *literal*. An interpolated string does not compile,
/// so a value cannot be spliced into a statement by accident.
public struct SQL: ExpressibleByStringLiteral, Sendable, Equatable {
    public init(stringLiteral value: StaticString)
    /// `?, ?, ?` for an IN list or multi-row insert: structure is dynamic, values still bound.
    public static func placeholders(_ count: Int) -> SQL
    public static func + (lhs: SQL, rhs: SQL) -> SQL
}
/// A table or column name checked against `[A-Za-z_][A-Za-z0-9_]*` (ASCII) for the rare DDL that cannot bind a name.
public struct SQLIdentifier: Sendable, Equatable {
    public init(_ name: String) throws(SQLiteError)
}

// MARK: Values
public enum SQLiteValue: Sendable, Equatable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
    case null
}
/// What can be bound. Int widens to Int64 (never text); Bool is 0/1; Date is whole milliseconds since 1970 by
/// default (`Date.sqliteMilliseconds`), and throws rather than storing 0 when it does not fit.
public protocol SQLiteBindable: Sendable {
    func sqliteValue() throws(SQLiteError) -> SQLiteValue
}
extension Int: SQLiteBindable {}  extension Int64: SQLiteBindable {}  extension Bool: SQLiteBindable {}
extension Double: SQLiteBindable {}  extension String: SQLiteBindable {}  extension [UInt8]: SQLiteBindable {}
extension Date: SQLiteBindable {}  extension Optional: SQLiteBindable where Wrapped: SQLiteBindable {}

// MARK: Rows
public struct SQLiteRow: Sendable {
    public let columnNames: [String]
    public func integer(_ column: Int) throws(SQLiteError) -> Int64
    public func int(_ column: Int) throws(SQLiteError) -> Int            // Int(exactly:), throws .corrupt on overflow (watchOS)
    public func real(_ column: Int) throws(SQLiteError) -> Double
    public func text(_ column: Int) throws(SQLiteError) -> String
    public func blob(_ column: Int) throws(SQLiteError) -> [UInt8]
    public func bool(_ column: Int) throws(SQLiteError) -> Bool
    public func date(_ column: Int) throws(SQLiteError) -> Date          // milliseconds, the default
    public func optional<T>(_ column: Int, _ read: (SQLiteRow, Int) throws(SQLiteError) -> T) throws(SQLiteError) -> T?
    public func isNull(_ column: Int) -> Bool
    // Same set by name: row.text("token"). A missing name throws .noSuchColumn.
    public func text(_ name: String) throws(SQLiteError) -> String
    // ... integer/int/real/blob/bool/date by name likewise
}

// MARK: The database
public actor SQLiteDatabase {
    public struct Configuration: Sendable {
        public enum Access: Sendable { case readWrite, readOnly }
        public enum Journal: Sendable { case wal, delete }
        public enum Synchronous: Sendable { case full, normal }
        public var access: Access                  // default .readWrite
        public var fileMode: Int?                  // default 0o600; nil = leave to umask (documented as a choice)
        public var journal: Journal                // default .wal  (decision in §7)
        public var synchronous: Synchronous        // default .full
        public var busyTimeout: Duration           // default 5 s, matching FleetWatch and VaultMCP
        public var foreignKeys: Bool               // default true
        public init(...)
    }

    /// Opens, or creates, the database at `path`. For a new file the 0600 file is created *before* SQLite opens it.
    public init(path: URL, configuration: Configuration = .init()) throws(SQLiteError)
    /// A private in-memory database for tests. One connection; a second `inMemory()` is a different database.
    public static func inMemory(configuration: Configuration = .init()) throws(SQLiteError) -> SQLiteDatabase

    public struct ExecutionResult: Sendable, Equatable { public let changes: Int; public let lastInsertRowID: Int64 }

    @discardableResult
    public func execute(_ sql: SQL, _ parameters: [any SQLiteBindable] = []) throws(SQLiteError) -> ExecutionResult
    public func query(_ sql: SQL, _ parameters: [any SQLiteBindable] = []) throws(SQLiteError) -> [SQLiteRow]
    public func query<T>(_ sql: SQL, _ parameters: [any SQLiteBindable] = [],
                         map: (SQLiteRow) throws(SQLiteError) -> T) throws(SQLiteError) -> [T]
    public func first<T>(_ sql: SQL, _ parameters: [any SQLiteBindable] = [],
                         map: (SQLiteRow) throws(SQLiteError) -> T) throws(SQLiteError) -> T?
    /// DDL and multi-statement scripts (no parameters).
    public func executeScript(_ sql: SQL) throws(SQLiteError)

    /// `BEGIN IMMEDIATE`, run `body`, `COMMIT`; any thrown error rolls back and is rethrown. `body` is synchronous
    /// and isolated to this actor, so it cannot suspend while holding the write lock, and nothing else interleaves.
    public func transaction<T>(_ body: (isolated SQLiteDatabase) throws(SQLiteError) -> T) throws(SQLiteError) -> T

    // Introspection (read-only, parameters bound)
    public func userVersion() throws(SQLiteError) -> Int
    public func journalMode() throws(SQLiteError) -> String
    public func tableNames() throws(SQLiteError) -> [String]
    public func columnNames(table: String) throws(SQLiteError) -> [String]     // pragma_table_info(?)
    public func integrityCheck() throws(SQLiteError) -> [String]                // empty == ok
    public func close()                                                         // idempotent; later calls throw .closed
}

// MARK: Migrations
public struct SQLiteMigration: Sendable {
    public let version: Int                      // 1, 2, 3 ... strictly increasing, no gaps
    public let name: String
    public let steps: [SQL]                      // literal-only statements
    public init(version: Int, name: String, steps: [SQL])
    /// For data rewrites that need code: runs inside the migration's transaction.
    public init(version: Int, name: String, apply: @Sendable @escaping (isolated SQLiteDatabase) throws(SQLiteError) -> Void)
}
extension SQLiteDatabase {
    /// Brings the file to the highest version in `migrations`. Each migration, and the `user_version` stamp that
    /// follows it, are one transaction: a failure leaves the file at the previous version.
    /// - Throws: `.schemaTooNew` if the file is newer than `migrations`; `.migrationFailed(version:message:)`.
    /// - Returns: the versions applied (empty if already current).
    @discardableResult
    public func migrate(_ migrations: [SQLiteMigration]) throws(SQLiteError) -> [Int]
}

// MARK: Errors
public enum SQLiteError: Error, Sendable, Equatable, CustomStringConvertible {
    case cannotOpen(path: String, code: Int32, message: String)
    case permissions(path: String, message: String)          // could not create/restrict the file
    case busy(message: String)                               // SQLITE_BUSY after the timeout
    case locked(message: String)                             // SQLITE_LOCKED
    case readOnly(message: String)
    case constraint(message: String, extendedCode: Int32)    // unique, not-null, foreign key ... (no bound values)
    case notADatabase(message: String)                       // SQLITE_NOTADB / SQLITE_CORRUPT
    case prepare(message: String), bind(index: Int, message: String), step(code: Int32, message: String)
    case typeMismatch(column: Int, expected: String)         // row read of the wrong storage class
    case noSuchColumn(String), valueOutOfRange(String)       // Int overflow, Date not representable
    case schemaTooNew(stored: Int, supported: Int)
    case migrationFailed(version: Int, message: String)
    case invalidMigrations(String)                           // gap, duplicate, version <= 0
    case invalidIdentifier(String), closed
    public var resultCode: Int32? { get }
}
```

Domain stores map `SQLiteError` to their own error in one place (`catch let e as SQLiteError`), keeping `OutboxError.storage` etc. unchanged for their callers.

**Example (what SwiftPushHub's `due(at:limit:)` becomes):**

```swift
try await db.query("""
    SELECT id, client, received, expires, state, request, devices FROM events
    WHERE state = 'queued' AND expires > ? ORDER BY received, id LIMIT ?
    """, [now, limit], map: Self.decode)      // Date -> ms, Int -> Int64, both bound as integers
```

## 6. MCP Schema

**N/A.** A storage library with no tool surface; there is nothing for a model to call. (Servers built on it expose their own MCP tools.)

## 7. Constraints & Compliance

**Safety rules (each is a test in §11):**

1. **Parameter binding only.** `SQL` is `ExpressibleByStringLiteral` and not `ExpressibleByStringInterpolation`, so `"... \(value)"` does not compile; `LIMIT`, `OFFSET`, `IN (...)` lists and booleans are all bound (`SQL.placeholders(n)`). The two places SQLite cannot bind (a table/column name in DDL, a `PRAGMA user_version = N` integer) take a validated `SQLIdentifier` or an `Int`, never a `String` from elsewhere. There is deliberately no public initializer from an arbitrary `String`.
2. **File mode 0600 from creation.** For a new path the package creates the file with POSIX `open(O_CREAT|O_EXCL, 0o600)` *before* SQLite opens it (a zero-length file is an empty database: *unverified*, to be proven by a test), then verifies the mode after open with `stat`, and tests `-wal`/`-shm` sidecars. It does not call `umask` (process-global, racy under threads). An existing file is `chmod`ed to the configured mode. `fileMode: nil` opts out and is documented as a decision. The parent directory remains the caller's (FleetWatch's `ServerPaths` already does this).
3. **Int64 binding.** `Int` is always bound with `sqlite3_bind_int64`, never as text; reading an `Int` uses `Int(exactly:)` and throws rather than truncates, because `Int` is 32-bit on arm64_32 (watchOS 10 is in SwiftDiagnosticsHub's platform list). Numbers are never bound as text.
4. **Busy timeout.** `sqlite3_busy_timeout` set on every connection (default 5 s, the value FleetWatch and VaultMCP already chose). Transactions use `BEGIN IMMEDIATE` so a conflict is discovered at the start, as VaultMCP's reasoning says.
5. **FULLMUTEX.** Always on for read-write connections (cost is negligible with one actor, and it keeps a stray non-actor use safe); the open flags are `READWRITE|CREATE|FULLMUTEX` or `READONLY|FULLMUTEX`.
6. **Step results are checked.** `query` and `execute` finish only on `SQLITE_DONE`; any other terminal code is thrown (fixes bug 1 by construction). Text columns are nil-checked; blobs larger than `Int32.max` throw `valueOutOfRange`.
7. **Errors carry SQLite's message and code, never bound values.** (`sqlite3_errmsg` does not include them; the package never formats parameters into an error.)

**WAL decision.** Default `journal: .wal`, `synchronous: .full`; VaultMCP opts into `.normal` as it does today and says why. Reasons for WAL: the portfolio already runs a second process against the same file (VaultMCP voice instance, the planned `diag` CLI, FleetWatch's CLI per its busy-timeout comment), and WAL lets readers proceed during a write. Costs: `-wal`/`-shm` sidecar files (mode: see rule 2), no use on network filesystems, and a read-only connection cannot switch modes (it inherits the writer's, as VaultMCP notes). `.synchronous: .full` as the default because the outbox answers 202 only after the write (repo, DiagnosticsHub §3) and a lost commit there is a lost alert. This is an **owner decision** (§16 Q2).

**Concurrency (Swift 6 strict).** `SQLiteDatabase` is an `actor`. It holds one `OpaquePointer`, which is not `Sendable`, in:

```swift
// Justification: opened FULLMUTEX and only this actor's isolated methods and deinit touch the handle; it is never returned or stored elsewhere.
private nonisolated(unsafe) let handle: OpaquePointer
```

This is the **only** `nonisolated(unsafe)` (and no `@unchecked Sendable`) in the package, matching the comment all five portfolio actors already carry. It exists because an actor's `deinit` is nonisolated and must close the handle. Whether SE-0371 isolated deinit (a newer toolchain feature; its availability on the macOS 14 / iOS 17 floors is *unverified*) would let the property be a plain isolated `let` with **zero** unsafe markers is worth a spike before coding; if it works on every deployment target it replaces the justification. `SQLiteRow` and `SQLiteValue` copy data out of the statement, so no pointer escapes the call (PointerEscapeAuditor-clean: `withUnsafe*` is used only for blob binding and is not stored). `transaction`'s body takes `isolated SQLiteDatabase` and is synchronous, so it cannot hold a write lock across an `await`.

**Other house rules:** no force unwraps/`try!`/`as!`; typed throws `throws(SQLiteError)` as the portfolio's stores already do; all public API documented with DocC; division/size checks on `Int32` conversions.

## 8. Source & API Compatibility, and Migration Path

**Breaking changes:** none for existing callers; this is a new package. Each project adopts it **one store at a time**, behind its existing domain protocol, so callers of `EventOutbox`, `DeviceRegistry`, etc. are untouched. **Type-checking risk:** low; `[any SQLiteBindable]` parameter arrays are the one thing to watch for slow inference on large literals (*unverified*; measure in the spike).

**Adopting unversioned databases.** Every deployed file today (except VaultMCP's and swift-oauth's) has `user_version = 0` and a schema equal to the current `CREATE TABLE IF NOT EXISTS`. Migration 1 of each project is therefore *that same idempotent script*: on an existing file it is a no-op that stamps version 1, on a new file it creates the tables. (This is VaultMCP's "fresh versus unversioned legacy" lesson made the default, and it needs a migration test against a copy of a real file.)

| Project | Deletes | Replaces with | Risk |
|---|---|---|---|
| **SwiftDiagnosticsHub** (do first: just built, no deployed data worth keeping, and it is the pattern others copied) | `run`, `SQLValue`, `Row`, `SQLITE_TRANSIENT`, init/open code, `milliseconds`, ad-hoc `BEGIN/COMMIT` (~120 of 477 lines) | `SQLiteDatabase`, `migrate([v1])`, `transaction { }` | Low. Tools 6.4 -> keep until reconciled (§16 Q5). Its contract suite is the proof the swap preserved behavior. |
| **SwiftPushHub** (5 stores) | five copies of open/query/`SQLITE_TRANSIENT`/`milliseconds` (~40-50 lines each); the interpolated `LIMIT`/`IN` | `db.query(..., [Int, Date])` | Medium. Numbers move from text-bound to integer-bound: existing rows are INTEGER-affinity already so they compare equal (*unverified*; migration test on a copy of the live file). Gains a busy timeout and a version. Deployed (Teletran 2 per owner notes, *not re-verified*), so cut over with a backup. |
| **SwiftPush** (+ send-cli copy) | `SQLiteDeviceRegistry`'s open/query plumbing; the second copy becomes a dependency instead of a file copy | `SQLiteDatabase` + `PRAGMA foreign_keys` is now a default | Low-medium. **Apple-only today**; the package's Linux support does not change that. |
| **FleetWatch** (+ infoplist copy) | `SQLiteDatabase.swift` (the enum), `FleetStore`/`MachineRegistry` open and `execute`/`query`, the `documents` helpers move to a small FleetWatch type over `SQLiteDatabase` | `SQLiteDatabase` with `fileMode: 0o600`, REAL timestamps stay REAL (`.real`) | Medium. Many call sites (539 + 292 lines of stores); keep the JSON `documents` table in FleetWatch, not in SwiftSQLite. The `-infoplist` copy should be reconciled with `FleetWatch` first (it is behind, bug 12). |
| **VaultMCP** | `DatabaseHandle`, the manual bind/column code, `withTransaction`, `migrateIfNeeded`'s loop (not its *steps*), `SQLiteError` | `SQLiteDatabase(access: .readOnly)`, `migrate` | **Highest.** 1,325 lines incl. FTS5 triggers and embeddings; it is a `final class` used synchronously today, and moving to an actor makes call sites `async`. FTS5 availability is a property of the system library, not of this package (*unverified* on Linux). Last. |
| **swift-oauth** | its own `CSQLite` target and `OAuthStorage` open code; its migration *tests* become the model | `SwiftSQLite` | Medium. Throws plain `Error`s and is synchronous; also removes the `CSQLite` name clash SwiftPush documents. Optional, after VaultMCP. |

## 9. Platform and Linux (the backend section)

There is no compute backend; this section is the platform story.

- **Apple (verified in repo):** `import SQLite3` works against the SDK's universal libsqlite3, and SwiftPush's manifest explains why *not* to name pkg-config or Homebrew there (an arm64-only Homebrew copy breaks the x86_64 half of a universal build).
- **Linux (not verified by me):** the Swift toolchain does not ship an `SQLite3` module on Linux (*unverified: I did not build on Linux*); swift-oauth's manifest (repo) is evidence that a `.systemLibrary` target with `pkgConfig: "sqlite3"` and `.apt(["libsqlite3-dev"])` is what it needed. SwiftSQLite follows that exact pattern: `#if canImport(SQLite3) import SQLite3 #else import CSwiftSQLite #endif`, with the manifest's `#if os(Linux)` choosing the pkg-config form (and inheriting its caveat that `#if os` in a manifest is the *host*, which matters for cross-compiling, *unverified*). **The C target must be named uniquely (`CSwiftSQLite`, not `CSQLite`)**: SwiftPush's manifest says a copy named `CSQLite` "clashed with swift-oauth's in any package graph holding both."
- **What currently targets Linux:** nothing in the portfolio built on this survey. FleetWatch's "Linux" artifact is a bash script (repo: `fleetwatch-linux-scratch`), and every consumer's own Package.swift marks its SQLite use Apple-only or lists only Apple platforms. The owner's deployment host is a Mac (per notes). So **Linux support is a new capability, not a migration requirement**, and must be proven in CI (a Swift 6.2 Linux container with `libsqlite3-dev`, *unverified*) before anything claims it. Until then the package README says "Apple platforms; Linux in progress".
- **SQLite feature dependencies to test on each platform:** WAL, `pragma_table_info`, `INSERT ... ON CONFLICT DO UPDATE` (3.24), `RETURNING` (3.35, if adopted). Minimum SQLite version supported is an open question (§16 Q6). The SDK and distro versions are *unverified*.

## 10. Dependencies

**Internal:** none. **External:** none: Foundation and the system SQLite library only (`SQLite3` on Apple, `libsqlite3` on Linux). `swift-docc-plugin` as the documentation-only dependency, as every sibling package does. The test-support product depends on `SwiftSQLite` only. No SwiftDeterminism clock dependency: `Date` conversion takes the value, not `Date()`.

## 11. Test Strategy

Swift Testing, as the portfolio does.

**Reference truth:** SQLite's own documented behavior (result codes, `PRAGMA user_version`, `journal_mode` results), verified by an *independent* path: the `sqlite3` command-line tool run over the same file in tests that can shell out (macOS) or the raw C API in the test target (as VaultMCP's schema-version test stamps `user_version` directly, repo). Expected values are literals computed by hand, not produced by the code under test.

**Validation trace (required):** bind `Int64.max` (9223372036854775807) and `Int64.min`; read back with `integer(0)`; assert equality, and assert `SELECT typeof(?)` is `'integer'` (not `'text'`). Bind the integer `3_000_000_000`; read with `int(0)` is exact on 64-bit and the overflow path is tested by calling the underlying conversion with a value outside `Int32` to model arm64_32. Date `1970-01-01T00:00:01.5Z` binds as `1500`.

**Categories:**
- **Contract suite** (`SQLiteDatabaseContract`), parameterized over `.inMemory` and `.file(wal)` and `.file(delete)`, modeled on SwiftDiagnosticsHub's `StoreContractTests`: execute/query/first/scalar, every value type round-trips, NULL handling, `changes`/`lastInsertRowID`, transaction commit, rollback on throw, nested-error rollback, `close` idempotence.
- **Safety:** a string with `'; DROP TABLE x; --` stored and returned verbatim; a compile-fail test is not possible in Swift Testing, so the literal-only `SQL` rule is checked by the type's API (no `String` initializer) and by a source-scan test that no `\(` appears in a `SQL` literal in the package's own sources; new-file mode is `0o600` at creation (stat after open), `-wal`/`-shm` modes, existing 0644 file is tightened.
- **Fault injection:**
  - *Busy:* two `SQLiteDatabase` instances on one file; the first holds `BEGIN IMMEDIATE` (via the testing product's `BusyLock`); the second, `busyTimeout: .milliseconds(50)`, must throw `.busy` after roughly the timeout and *not* before (bound the elapsed time loosely to avoid flakes).
  - *Locked:* mapping only: a table-driven test of `SQLiteError(code:extendedCode:message:)` over every primary and extended code the package maps (no database needed, so no flake). Real `SQLITE_LOCKED` needs shared-cache and is out of scope (*unverified* that it is reachable otherwise).
  - *Corrupt:* a file of random bytes -> `.notADatabase` on first statement; a valid file truncated mid-page -> `.notADatabase` or `.constraint`-free failure surfaced from `integrityCheck`; a read-only-permission file -> `.readOnly`/`.cannotOpen`.
  - *Row type errors:* reading a text column as integer throws `.typeMismatch`, never traps.
  - *Truncated step:* a step failure after the first row (provoked by dropping a table between steps in a second connection, or by a busy writer) must throw, not return partial rows (the VaultMCP bug 1 regression).
- **Migrations:** fresh file runs 1..N and stamps N; file at version k runs k+1..N only; **an unversioned file with the legacy schema adopts migration 1 as a no-op**; a failing migration rolls back both its change and its stamp; `schemaTooNew` refuses and leaves the file unchanged; invalid migration lists (gap, duplicate, zero) throw `.invalidMigrations`; a data-rewrite migration (the swift-oauth shape) with a rollback. Test helper `migrate(upTo:)` lets a test build an *older* file the way swift-oauth's `schemaVersion:` parameter does, without a production-code hook (`SwiftSQLiteTesting` only).
- **Concurrency:** many concurrent `async` writers on one actor insert N rows; count is N, no `SQLITE_MISUSE`; builds with strict concurrency and no warnings.
- **Linux:** the same suite in a Linux container (*unverified, a CI deliverable*).

## 12. Architecture Decision Review

**ADR Check:**
- [ ] Reviewed `architecture_decisions.md` (not read for this draft; to do on approval)
- [ ] Supersedes an existing ADR? Unknown, *unverified*; SwiftPush's recorded decision to use the SDK's `SQLite3` module and not a system-library target on Apple platforms is the one to check (ADR numbering not read).
- [ ] New ADR required? **Yes.**

**New ADR draft:**
- Title: One shared dependency-free SQLite wrapper; SQLite is never a third-party package.
- Category: storage
- Key decision: portfolio stores use `SwiftSQLite` (system SQLite, actor-isolated, literal-only SQL, versioned migrations) instead of per-project wrappers or GRDB.

## 13. Adversarial Review

**Strongest case for a different approach.** *Just use GRDB* (it is already checked out in `Swift/GRDB.swift`, repo): it is the best-tested SQLite library for Swift, with a `DatabasePool` (WAL readers/writer), migrations (`DatabaseMigrator`), observation, typed records, and years of fixes for exactly the bugs in §3.3. Writing a wrapper is how the portfolio got five divergent copies. If the goal is correctness, a maintained library beats a new package of ours.

**Where this design is most likely wrong.**
- It assumes the stores stay *small and SQL-literal*. If a project wants query building, joins mapped to structs, or reactive observation, `SwiftSQLite` will grow into a worse GRDB. The line to hold: no ORM, no query DSL, no observation.
- It assumes one actor per file is enough. A read-heavy server (VaultMCP's search) serializes all reads behind that actor; GRDB's `DatabasePool` gives concurrent readers under WAL. We accepted the first design (one connection) because every current consumer does the same; a `readers: Int` pool is the obvious later extension (§15) and not designed here.
- Literal-only `SQL` could be too strict: dynamic filters (optional WHERE clauses) need composition. `SQL + SQL` and `placeholders` cover the cases seen; if a real case needs more, the escape hatch must stay explicit and greppable (`SQL(unsafeDynamic:)`) rather than being added silently.
- Typed throws on a public actor API may be rough for callers on older tooling or when bridging `async` and closures (*unverified*; the portfolio's stores already use it, which is mild evidence).
- `isolated` closure parameter for `transaction` may fail to compile or infer in some positions (*unverified*; spike first).

**What an experienced critic would say.** "You are re-implementing a subset of GRDB and will own its bugs forever." We are proceeding because the owner's stated constraints (zero third-party dependencies for small servers, Linux portability, the existing choice of the system module) and the size of the need (open, bind, step, migrate, transaction; roughly 600 lines) make a library the wrong *weight*, and because the safety properties we need (literal-only SQL, 0600 from creation, `Int64`, checked step) are policy choices a general library does not enforce. §14 puts the GRDB case fairly.

## 14. Alternatives Considered

**Alternative 1: Adopt GRDB.swift in every project.** Repo facts: `Swift/GRDB.swift` is present; its Package.swift is `swift-tools-version:6.1` and lists iOS 13 / macOS 10.15 / tvOS 13 minimum platforms; it compiles its own SQLite on Linux (`SQLITE_DISABLE_SNAPSHOT` defined for Linux) and keeps an *unverified-by-me* optional SQLCipher path. No portfolio project depends on it (`grep` of Package.swift files under Tools/ found no GRDB or SQLite.swift reference). *Pros:* mature; connection pool; migrator; records; observation; a large test suite. *Cons here:* a new third-party dependency (the owner wants none for small servers); it is large for what every consumer does with five statements; its `Row` / `Database` types are not `Sendable`-simple and its concurrency model (`DatabaseQueue`/`Pool`, closure-based) would be a *rewrite* of every store rather than a swap of plumbing; its Package.swift is 6.1 and the dependency surface and resolution on the hosts is unverified (*unverified*); it would not enforce literal-only SQL or file mode 0600 for us; supply-chain exposure on a service that holds device tokens. **When GRDB would be right:** a project that needs observation, joins mapped to types, or multiple concurrent readers (for example a future app-side store). Not rejected for apps, rejected for these servers.

**Alternative 2: SQLite.swift** (stephencelis). Same trade-off as GRDB with a typed query builder; a third-party dependency; no portfolio use found. Rejected for the same reasons; the DSL is the opposite of the literal-SQL style the portfolio uses.

**Alternative 3: Keep copying; just fix the copies.** Zero new package. Rejected: 12 wrappers means 12 fixes and each fix drifts (bug 12 shows it already did within a single project). This is the status quo and the reason for the proposal.

**Alternative 4: A free-function/`enum` toolkit like FleetWatch's `SQLiteDatabase`** (no actor; callers own the pointer). Smaller, but pushes handle ownership, the `nonisolated(unsafe)` and its justification back into every consumer (5+ places today). Rejected.

**Alternative 5: A shared *protocol* "SQLiteBackedStore" instead of a database type.** Rejected: the stores differ in domain, not plumbing.

**Alternative 6: Put it in an existing package (SwiftHTTPService, SwiftDeterminism, SwiftGraphStore).** Not read; *unverified* whether `SwiftGraphStore` already does anything with SQLite (Tools/ name suggests a different store). Rejected for coupling: every SQLite consumer would inherit an unrelated dependency graph.

## 15. Future Directions

- A reader pool under WAL (`readers: Int`) for read-heavy servers such as the vault index.
- `RETURNING` support and a `Codable` JSON-column helper (FleetWatch's `documents` pattern) if a second project wants it.
- Online backup (`sqlite3_backup_*`) for the outbox, and an `integrityCheck` health probe the hubs' status endpoints could call.
- A `SQLiteStore` conformance helper that generates the shared contract suite for a domain protocol and its in-memory twin.
- FTS5 convenience for VaultMCP if a second project needs search.
- A Windows or WASI story is not considered.

## 16. Open Questions

1. **Name and home:** `SwiftSQLite` as a sibling repo under `Tools/`? Public or private? (The Hubs are private.)
2. **WAL default and `synchronous` default** (§7): `.wal` + `.full` as proposed, or `.delete` for simplicity? Do you want `.normal` only where a file is a rebuildable cache (VaultMCP)?
3. **Time storage default:** milliseconds INTEGER (Hubs) as the package default, with REAL seconds (FleetWatch) via explicit `.real`?
4. **Is a Swift 6.2 isolated-deinit spike worth doing** to remove the one `nonisolated(unsafe)`? Depends on deployment floors (macOS 14 for VaultMCP/SwiftReleaseKit).
5. **Tools version:** SwiftSQLite at 6.2 (recommended, resolvable by every host in the portfolio per SwiftReleaseKit and SwiftPush manifests). Should SwiftDiagnosticsHub drop from 6.4 to 6.2 when it adopts the package? The host's current toolchain (reported 6.4.1 in notes, 6.3.3 earlier) should be re-checked with `swift --version` over ssh, not recited.
6. **Minimum SQLite version** to support (3.24 for upsert, 3.35 for `RETURNING`)? What do the macOS 14 SDK and the Linux target distro ship? (*unverified*)
7. **Linux:** is it a goal now, or only "do not preclude"? If a goal, which distro/image is the CI target?
8. **Is parent-directory creation in scope** (swift-oauth creates it; FleetWatch's `ServerPaths` sets directory 0700)? Proposed: out of scope.
9. **Migration order:** SwiftDiagnosticsHub first (proposed). Should VaultMCP be left on its own wrapper until last, or kept off the package entirely because it is a synchronous class with FTS5 and embeddings?
10. **Fix the bugs now in place?** Bugs 1 (VaultMCP partial rows), 4 (0600 window) and 5 (no busy timeout in the hubs, before the `diag` CLI exists) are live today. Do you want them patched in their repos ahead of the package, or accepted until migration? (Nothing was changed in this survey.)

## 17. Documentation Strategy

**Documentation Type:** API docs **and** a narrative article.

**Complexity Threshold Check:**
- Combines 3+ APIs? **Yes** (database, statements/values, rows, transactions, migrations, errors).
- Explanation needs 50+ lines? **Yes** (the safety rules, the WAL decision, adopting an unversioned database).
- Needs theory/background? **Yes** (why literal-only SQL, why `Int64`, the 0600 creation order).

**Articles (.docc), none matching a Swift symbol name:** `GettingStartedWithSQLite.md` (open, query, transaction), `SafetyRules.md` (the seven rules in §7 with the incident each prevents), `AdoptingAnExistingDatabase.md` (migration 1 as the idempotent baseline; the migration-test technique), `PlatformNotes.md` (Apple, Linux, WAL and file permissions). README states the supported platforms plainly and that Linux is unverified until CI exists. CHANGELOG, master plan and the portfolio's `shared_packages.md` entry updated at the first release, per the doc-housekeeping rule.
