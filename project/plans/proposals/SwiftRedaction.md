# Design Proposal: SwiftRedaction (one shared package for secret and PII scrubbing)

**Status:** PROPOSED 2026-11-09. Owner: one reusable package holding the shared patterns with the two policies on top, and any other project doing similar work migrated later. Written in the KEXPPower repository for review; **on approval it moves to the new sibling repository `SwiftRedaction`** (created from the development-guidelines template as a sibling directory, not nested). Nothing in any existing repository was modified to write this.

**Decisions by the owner, 2026-11-09 (these settle §16; where the text below differs, this block wins):**
1. **Shape:** a standalone shared package (`Tools/SwiftRedaction`), not fixes in place.
2. **Engine:** Swift Regex is preferred. It still backtracks, so the input-length cap and a measurement on both macOS and Linux stay; the matcher stays behind a protocol so the engine can change if the measurement says so.
3. **`.appLog` gets the `key=value` rule:** "better to be safe", accepting that it will also redact harmless text such as `token: expired`.
4. **The app-specific-password (4-4-4-4) rule:** configurable, with the context required before it fires a policy setting; measure its false positives on real logs before choosing a default.
5. **Dependencies between the owner's packages:** git URL.
6. **Default line cap for `.appLog`:** accepted as proposed (SwiftDiagnosticsHub's scrubber is at 4,096 UTF-8 bytes today).
7. **Git SHAs:** a 40-hex git SHA is **not** redacted (the build-to-commit link needs them); longer hex runs (keys, SHA-256 digests) still are.
8. **Linux:** no host right now; the geo-audit host on fly.io is a possible later one.

**Facts marked (repo) were read on 2026-11-09. Anything about code I did not open, about hosts, or about runtime behavior I did not measure is marked *unverified*.** One measurement was taken (§9): a throwaway script in the session scratchpad, outside every repo.

---

## 1. Objective

One Foundation-only Swift package, `SwiftRedaction`, that removes secret-shaped and personal-looking text from strings, with:

- a **rule catalogue**: named, individually tested patterns (JWT, Bearer, PEM, password assignment, email, home path, IP, ...);
- a **policy** that chooses which rules apply, in what style the replacement is written, and what happens to an input that is too long;
- deterministic, idempotent `redact(_:)` for a `String` and for `[String]` lines;
- a **report** of which rules fired and how often, never the secret, for audits;
- two shipped policies, `.buildTool` and `.appLog`;
- a **test-support product** that asserts a secret-shaped fixture appears in no string, file or `Data` handed to it.

`SwiftReleaseKit` and `SwiftDiagnosticsHub` then delete their own copies. Other projects migrate later.

## 2. Motivation

- Two scrubbers exist and have diverged. `Redactor` (SwiftReleaseKit) and `LogScrubber` (SwiftDiagnosticsHub) cover **nearly disjoint** sets of shapes (§3.3), so a fix or a new shape added to one is not in the other.
- A third and fourth shape of the same problem already exist as copies: **the access-path redactor was written four times** (§3.4). SwiftMCPServer's own source says so: "four consumers with four copies of this is the failure the access log exists to avoid."
- Each copy has its own gaps and its own test style. A privacy claim ("no secret reaches the log") is only as strong as the weakest copy's tests.
- The owner is about to ship TestFlight log upload (SwiftDiagnosticsHub) where log lines are **attacker-influenced** (anything a peer sends can be logged). That makes the performance and worst-case behavior of the scrubber a security matter (§9), and one real quadratic case was found and measured.

## 3. Survey of existing code

### 3.1 The two main implementations (read fully, with their tests)

| | `Redactor` (repo: `Tools/SwiftReleaseKit/Sources/SwiftReleaseKit/Redactor.swift`, 55 lines) | `LogScrubber` (repo: `Tools/SwiftDiagnosticsHub/Sources/SwiftDiagnosticsKit/LogScrubber.swift`, 94 lines) |
|---|---|---|
| Purpose | captured xcodebuild / notarytool output before run logs | app log lines before a TestFlight upload |
| Engine | Swift Regex literals (`/.../`), `String.replace` | `NSRegularExpression`, rules compiled once into a `static let` |
| Shape | `struct Redactor: Sendable, Equatable`, instance holds caller `secrets` | `enum LogScrubber`, static, 16 declared rules |
| Replacement | uniform `[REDACTED]` (and `[REDACTED PRIVATE KEY]`) | typed: `[token]`, `[uuid]`, `[hex]`, `[email]`, `[ip]`, `[music-id]`, `/Users/[user]` |
| PEM private key (also truncated, no END) | yes | no |
| JWT | yes (min 5 chars per segment) | yes (any length) |
| `Bearer <opaque>` | **no** (only if the value is a JWT) | yes |
| password/secret/token as flag, `k=v`, `k: v`, JSON | **yes** | **no** (only Apple Music labelled tokens) |
| Apple app-specific password `xxxx-xxxx-xxxx-xxxx` | yes | no |
| Apple Music user/developer token label | covered incidentally by the `token` rule | yes, by rule |
| UUID / long hex / long base64 | no (UUID deliberately survives: issuer IDs) | yes |
| email, `/Users`, `/home`, `/var/mobile`, MusicKit ids, IPv4, IPv6 | no | yes |
| caller-supplied literal secrets | yes (`secrets:`) | no |
| argv helper | `redactArguments` (value after a secret-named flag replaced outright) | no |
| Idempotent | by construction, **not tested** | by construction, tested on one line |
| Input length cap | none | none (the uploader's cap, if any, was not read: *unverified*) |
| Which rule fired | not reported | not reported |

Deliberate survivors in `Redactor` (repo, pinned by its test `identifiersSurvive`): key ID, issuer ID (a UUID), team ID, notary profile name, the *path* of a `.p8` file including `/Users/me/...`. `LogScrubber` would remove the issuer UUID and the `/Users/me` part of that very line, so the two policies genuinely differ and the shared catalogue must not apply every rule to both.

### 3.2 Tests, as they stand

- `RedactorTests` (repo, 8 tests): PEM whole and truncated; six password shapes as an `arguments:` test; JWT; app-specific password; the identifiers-survive equality; literal secrets with an empty string ignored; argv. Every leak assertion is `!redacted.contains(fixture)`. **No** idempotence test, **no** false-positive corpus beyond the one identifiers line, **no** length or adversarial test, no test of `Equatable`.
- `LogScrubberTests` (repo, 11 tests): one test per category using a `removes(_:from:)` helper, an eight-line "ordinary lines survive exactly" corpus, one idempotence line, and `patternsCompile` (declared count equals compiled count, so a typo cannot silently disable a category; this is a good idea the package should keep). **No** adversarial or length test, no negative cases for the identifier rules (§3.5), no Linux evidence.
- Both are Swift Testing; neither has a fixture file shared with the other.

### 3.3 Real bugs and gaps (found by reading; not fixed)

1. **`LogScrubber` email rule is quadratic. Measured.** `[A-Za-z0-9._%+-]+@...` on a run of `a` with no `@`: 5,000 chars 0.36 s, 10,000 chars 1.43 s, 20,000 chars 5.85 s (`-O`, `NSRegularExpression`, macOS 27, throwaway script in the scratchpad). Quadratic: a 64 KB line would take on the order of a minute. A peer that gets one long unbroken token logged can stall the uploader's scrub. (Linux/ICU timing *unverified*; the shape of the pattern is the same.)
2. **`LogScrubber` fails open.** `stringByReplacingMatches` gives no error channel; if ICU gives up on a pattern (its backtrack/time limits) the line comes back unmodified. That behavior of ICU limits is *unverified here*, but the design must not depend on it: a scrubber's failure mode must be "remove the line", not "send the line".
3. **`LogScrubber` has no generic `key=value` rule.** `password=hunter2`, `api_key=short`, `access_token=abc123` in a log line pass through unless the value happens to be a JWT or a 40+ character mixed-case run. This is exactly what `Redactor` covers.
4. **`Redactor` has no `Bearer <opaque token>` rule**; only a JWT-shaped bearer is caught. `Authorization: Bearer abc123` survives.
5. **`Redactor` app-specific-password rule is `\b[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}\b`**: any four lowercase four-letter words joined by hyphens (`some-test-case-name` is 4-4-4-4) is redacted. False positive in build output (test names, slugs). Apple's format is lowercase letters only, so the shape is right, the context is missing.
6. **`Redactor` quoted values with spaces leak the tail**: the value class is `[^\s"',}]+`, so `password: "hunter two"` redacts `hunter` and keeps `two"`. Same for `--password "a b"`, depending on how the shell/tool printed it.
7. **`Redactor` literal secrets are applied in caller order, shortest-first possible**: `["abc", "abcdef"]` leaves `def`. A literal secret that is a substring of the placeholder (`RED`) corrupts `[REDACTED]`, breaking idempotence. Neither is tested.
8. **`Redactor` truncated-PEM rule and lazy complete-PEM rule are O(blocks x length)** when a text holds many `BEGIN ... PRIVATE KEY` lines with no `END`: each attempt scans to the end. Bounded by the captured output, which is not attacker-controlled the way a log line is. Not measured (the one attempt was folded into an edited test script and its count is not reliable, so no figure is claimed).
9. **`Redactor` flag/assignment rules start with `[a-z-]*` / `[a-z_-]*` after `\b`**: on `a-a-a-a-...` every hyphen is a word boundary, so each start scans to the end. Quadratic in the worst case for the same reason as item 1; Swift Regex's cost not measured here (*unverified*).
10. **`LogScrubber` music-id rule `\b[ilp]\.[A-Za-z0-9]{8,}\b`** matches identifier-like text such as `p.sharedInstance` or `l.localizedName` (a single letter, a dot, 8+ alphanumerics, after a word boundary). Rare in real lines, untested either way.
11. **`LogScrubber` hex rule removes 40-hex git SHAs** (32+ hex digits), and the base64 rule can match a 40+ character CamelCase identifier containing a digit (a mangled name). The doc says it "errs towards removing too much", so this is by design, but it is not in the tests, and it removes information the owner may want in a bug report (the commit).
12. **`LogScrubber` Bearer rule's `\s+` crosses newlines**, so a multi-line chunk passed whole (not per line) eats the next line's first word. The uploader maps per line (repo, `logChunk.lines.map(LogScrubber.scrub)`), so today this is latent.
13. **`LogScrubber` music-token template rewrites `Music-User-Token: x` to `Music-User-Token=[token]`** (colon becomes equals). Harmless, idempotent, but a byte-compat detail a migration must keep or deliberately change.
14. **Sendable:** `LogScrubber` stores `NSRegularExpression` values in statics; that compiles under Swift 6.4 here, which implies the SDK marks the class `Sendable`; whether the Swift 6.2 toolchain / Linux corelibs does is *unverified*. `Redactor` stores only `[String]`, trivially Sendable; its regex literals are built on each call.

### 3.4 The rest of the portfolio (grep over `Tools`, KEXPPower, `WineTaster 4`; most hits are one-liners; files named below were opened unless marked)

| Where | What it does | Belongs in the shared package? |
|---|---|---|
| `SwiftMCPServer/.../AccessLog/AccessRecord.swift` `AccessPathRedactor` (repo) | request path -> log-safe path: known routes verbatim, credential segments of a registered route -> `:token`, anything else -> first segment (clipped to 64) + `:unmatched`; at most 16 segments | **Yes, as a structural `PathRedaction` helper, later phase.** Same algorithm as the next three |
| `SwiftPushHub/.../HubAccessLog.swift` `HubAccessPathRedactor` (repo) | the same, "trimmed to what the hub needs"; its doc names the MCP one as the model | Yes (copy #2) |
| `VaultMCP/Sources/AskTheHouse/AskAccess.swift` `redact` (repo) | the same, one known route | Yes (copy #3) |
| `FleetWatch/.../FleetAccess.swift` `FleetAccessPath.redact` (repo) | the same plus fixed list and three parameterized prefixes (`/enroll/:code`, ...) | Yes (copy #4); the parameterized prefixes show the API needs "known templates" |
| `SwiftMCPServer/.../Logging/LoggingConfiguration.swift` `sanitizeForLogging` (repo) | four regexes (`bm_...` API keys, Bearer, `access_token=`, `client_secret=`), **built with `try? NSRegularExpression` on every call**, silent skip on failure | **Yes, replaced by rules** (`apiKeyPrefix` configurable, Bearer, secretAssignment). Copy #5, with the per-call compilation cost |
| `SwiftMCPClient/.../Transport/HTTPOrigin.swift` `redactedURL`, `couldBeCredential` (repo, read in part) | URL -> no userinfo, no query, no fragment, path segments kept only if they look *ordinary* (an allowlist of shapes, "asked the safe way round") | **Idea yes, code later.** The allowlist-of-ordinary philosophy is better than any secret-shaped blacklist for URL segments; a candidate for a `URLRedaction` helper once the core exists. Stays in MCPClient for now (its tests pin its exact output) |
| `SwiftMCPClient/Tests/.../TransportErrorRedactionTests.swift` (repo) | fails a request on purpose and asserts **every rendering of the error** (`String(describing:)`, `String(reflecting:)`, `localizedDescription`) lacks the watched value | **The model for the testing helper** (§5.5) |
| `SwiftTLSKit/.../PrivateKeyFileDigest.swift` (repo, grep) | a type that describes itself as `<redacted>` | No: type-level redaction (`CustomStringConvertible`), the right tool at the source |
| `swift-oauth/.../TokenResponse.swift` (repo, grep) | `description` prints `<redacted>` for tokens | No: type-level, same reason |
| `SwiftPush/.../Device.swift` `redacted` (repo, grep) | a device token shown as its first N hex digits and an ellipsis | No: type-level; a truncation style, not a pattern |
| `SwiftReleaseKit/.../RunDiagnostics.swift`, `ReleasePipeline.swift` (repo, grep) | consumers of `Redactor` (`diagnostics.redact(...)`) | Consumers; migrate with the package |
| `SwiftDiagnosticsKit/.../DiagnosticsUploader.swift` (repo, grep) | consumer of `LogScrubber`: scrubs log lines and `.text` field values | Consumer; migrate |
| `quality-gate-swift/Sources/KeychainSecretsChecker` (repo, header read) | a SwiftSyntax checker that flags credentials written to `UserDefaults` | **No.** A checker's rules find secrets in *source*; they do not scrub text |
| `quality-gate-corpus-kit/.../TelemetryWriter.swift` `sanitizedURL` (grep) | confines a path inside a base directory | No: path-traversal containment, unrelated despite the name |
| `SwiftHTTPService/.../NetworkBlock.swift` `masked`; `SwiftTLSKit/.../ClientHandshakeFailure.swift` masks | network and bit masks | No: false hits |
| `ijs-dashboard-server` (`Identity/`, `Passkeys/EnrolmentStore.swift` flagged by the grep, *not opened*) | the owner says it deliberately avoids leaking host paths | *Unverified.* Not opened; check before claiming it is a consumer |
| `swift-cli-kit-auth`, `SwiftCLIKit` `SecureField`, `Ignite` `Property`, `panLAN`, `StackMapKit`, `quality-gate-swift` `SkippedTestAge`/`CorpusWriteQueue`/etc. | matched by the grep (UI secure field, CSS `mask`, other) | Not opened; *unverified*, assumed unrelated |
| `KEXPPower` and `WineTaster 4` hits (`privacy: .private`, `mask` in views) | `os.Logger` privacy annotations and UI masks | Not opened; *unverified*. The annotation is the platform's own redaction and stays |

**The pattern to take from this table:** four of five "other" implementations are *structural* (path segments, URL parts, types), not regex scrubbing. The package owns the regex catalogue and policy engine first; the structural helpers are a second module so a project that wants only one does not link the other.

## 4. Proposed Architecture

**New repository `SwiftRedaction`** (sibling of the others), `// swift-tools-version: 6.2` (what `SwiftReleaseKit` uses; the hosts all resolve it; `SwiftDiagnosticsHub` uses 6.4 and can depend on a 6.2 package). Platforms `.iOS(.v17)`, `.macOS(.v14)` (the app targets iOS 17; Linux needs no declaration).

```
Sources/
  Redaction/                 core: Rule, RuleID, RuleCatalogue, RedactionPolicy, Redactor, Report
    Rules/                   one file per rule family, each with its named fixtures in doc comments
    Policies/                BuildToolPolicy.swift, AppLogPolicy.swift
  RedactionPaths/            (phase 2) structural access-path and URL helpers
  RedactionTestSupport/      leak assertions for strings, files, Data, error renderings
Tests/
  RedactionTests/            per-rule, per-policy, idempotence, adversarial, byte-compat suites
  RedactionTestSupportTests/ the helper detects a planted leak (a helper that never fails is the common bug)
```

**Layering:** `Redaction` depends on Foundation only. `RedactionTestSupport` depends on `Redaction` and on swift-testing (`Testing`); apps never link it, only test targets do (precedent in the portfolio: `SwiftTLSKitTestSupport`, repo).

## 5. API Surface

### 5.1 Rules

```swift
public struct RuleID: RawRepresentable, Hashable, Sendable { public let rawValue: String }   // .jwt, .bearer, ...

public struct Rule: Sendable {
    public let id: RuleID
    public let summary: String                 // one line, for docs and reports
    public let uniformReplacement: String      // e.g. "[REDACTED]"
    public let typedReplacement: String        // e.g. "[token]"
}

public enum RuleCatalogue {
    public static let all: [Rule]              // fixed order; the order IS the algorithm
    public static func rule(_ id: RuleID) -> Rule?
}
```

Catalogue (ids; `B` = in `.buildTool`, `A` = in `.appLog`):

| Rule | B | A | Source |
|---|---|---|---|
| `pemPrivateKey` (whole, and truncated to end) | yes | yes | Redactor |
| `jwt` | yes | yes | both (one pattern, the stricter bounded one) |
| `bearer` | yes (new) | yes | LogScrubber |
| `secretFlag` (`--password X`, `--token=X`) | yes | no | Redactor |
| `secretAssignment` (`password=`, `token:`, JSON) | yes | opt-in, see Q3 | Redactor |
| `appSpecificPassword` (`xxxx-xxxx-xxxx-xxxx`) | yes | no | Redactor (with a context guard, §3.3 item 5) |
| `appleMusicToken` (labelled) | no | yes | LogScrubber |
| `apiKeyPrefix(prefix:)` (e.g. `bm_`) | per project | per project | SwiftMCPServer |
| `uuid` | **no** (issuer IDs survive) | yes | LogScrubber |
| `longHex` | no | yes | LogScrubber |
| `longBase64` | no | yes | LogScrubber |
| `email` (rewritten linear, §9) | no | yes | LogScrubber |
| `homePath` (`/Users`, `/home`, `/var/mobile`) | no (`.p8` path survives) | yes | LogScrubber |
| `musicID` | no | yes | LogScrubber |
| `ipv4`, `ipv6` | no | yes | LogScrubber |
| `literalSecret` (caller's strings) | yes | n/a | Redactor |

### 5.2 Policy

```swift
public struct RedactionPolicy: Sendable {
    public enum Style: Sendable { case uniform, typed }          // "[REDACTED]" vs "[token]", "[ip]", ...
    public enum OverlongInput: Sendable { case replaceWhole(String)   // fail closed (default)
                                          case truncateThenRedact(maxLength: Int) }
    public let rules: [RuleID]            // a SET; the engine always applies in catalogue order
    public let style: Style
    public let maxInputLength: Int        // default 4_096 characters per line for .appLog
    public let overlong: OverlongInput
    public init(rules: [RuleID], style: Style, maxInputLength: Int = 4096,
                overlong: OverlongInput = .replaceWhole("[line too long]"))
    public func adding(literalSecrets: [String]) -> RedactionPolicy
    public static let buildTool: RedactionPolicy
    public static let appLog: RedactionPolicy
}
```

`init` validates (§11): every replacement token must not match any rule in the same policy (idempotence by construction), and a rule listed twice is an error.

### 5.3 Redaction

```swift
public struct Redactor: Sendable {                     // one compiled engine per policy
    public init(_ policy: RedactionPolicy)
    public func redact(_ text: String) -> String
    public func redact(lines: [String]) -> [String]
    public func redactArguments(_ argv: [String]) -> [String]        // value after a secret-named flag replaced outright
    public func report(_ text: String) -> RedactionReport            // text + which rules fired
}

public struct RedactionReport: Sendable, Equatable {
    public let output: String
    public let fired: [RuleID: Int]       // counts only. Never the matched text, never offsets that could be used to recover it.
    public let overlong: Bool
}
```

`report` and `redact` share one code path (`redact(x) == report(x).output` is a test) so an audit cannot disagree with production.

### 5.4 Convenience (so call sites stay one line)

```swift
public extension Redactor { static let buildTool = Redactor(.buildTool); static let appLog = Redactor(.appLog) }
```

### 5.5 Test support

```swift
public struct Leak: Sendable, CustomStringConvertible { let secretLabel: String; let location: String }  // description never prints the secret

public func findLeaks(of secrets: [Secret], in strings: [String]) -> [Leak]
public func findLeaks(of secrets: [Secret], inFileAt url: URL) throws -> [Leak]
public func findLeaks(of secrets: [Secret], in data: Data) -> [Leak]          // raw bytes + UTF-8 decoded
public func findLeaks(of secrets: [Secret], inRenderingsOf error: any Error) -> [Leak]  // describing, reflecting, localizedDescription
public func expectNoLeaks(...)                                                // wraps findLeaks in #expect with a message naming the label, never the value

public struct Secret: Sendable { init(label: String, value: String) }         // also matches its base64, percent-encoded and hex forms
```

The helper searches the raw value **and its base64, percent-encoded and hex encodings** (a secret that was re-encoded before logging is still a leak). A message names the fixture's *label* and where it was found, never the value, so a failing privacy test does not itself write the secret into CI logs.

## 6. MCP Schema

**N/A for the library.** It is a local text filter. If a CLI (`swift-redact`, stdin to stdout, `--policy buildTool|appLog`, `--report` for fired rules as JSON) is later wanted, the report is:

```json
{ "policy": "appLog", "fired": { "jwt": 1, "ipv4": 2 }, "overlong": false }
```

No MCP tool is proposed: sending text to a tool to be scrubbed would defeat the point.

## 7. Constraints & Compliance

- **Concurrency:** all public types are `Sendable` values. A compiled expression is wrapped in one small `final class CompiledRule: @unchecked Sendable` only if the toolchain's `NSRegularExpression` is not already `Sendable` (*unverified on 6.2 / Linux*); then `// Justification:` goes on the line above, inline, as the gate's ConcurrencyAuditor requires. `NSRegularExpression` is documented immutable and thread-safe (*from memory, unverified*), which is the premise of the wrapper.
- **Determinism:** rule order is the catalogue's order, not the policy's list order; same input and policy give the same output on every host.
- **Idempotence:** `redact(redact(x)) == redact(x)` is a requirement, enforced in `RedactionPolicy.init` (replacement tokens cannot match any enabled rule) and by a property test over the whole fixture corpus.
- **Fail closed:** an input longer than `maxInputLength`, or a rule that fails to compile at construction, is an error at construction or a replaced line, never a pass-through. (Both existing copies fail open on a bad pattern in at least one path: `Redactor` cannot, literals compile at build; `LogScrubber` drops a failed rule from `compiled`, and relies on a test to notice.)
- **No force unwraps**, no `try!`; rule patterns are validated by a test per rule and again at `Redactor.init` (which throws `RedactionError.invalidRule(id)`).
- **What a scrubber can never guarantee (state this in the README and DocC, first page):**
  1. It works by **shape**. A secret with no recognizable shape (a short human-chosen password in prose, a name, an address, a free-text note) passes. Shape rules also pass a secret that has been transformed (split across lines, interleaved, URL-encoded, reversed).
  2. It cannot know what is *personal*. A show name is fine; a diary entry typed into a text field is not, and no regex tells them apart.
  3. It removes what it recognizes **today**; a new token format is invisible until a rule exists. `literalSecrets` exists because the caller who holds a secret is the only party who knows it.
  4. Redacting after the fact is **defense in depth**. The privacy line in SwiftDiagnosticsHub is enforced by **types** (a `logChunk` is only accepted for TestFlight; events are schema-registered; a `FieldValue.text` field is refused on the same terms), and that stays the primary control. A scrubber that is the *only* control is a design bug.
  5. A false positive is a cost (a lost commit SHA); a false negative is a leak. Defaults favor removal; policies may relax per rule, in code, visibly.

## 8. Source & API Compatibility, and Migration

New repository: nothing to break. Migration is two independent, reviewed PRs, each behind its **existing tests moved to the package** (the byte-compat gate):

**SwiftReleaseKit**
- Deletes: the body of `Redactor.swift` (regexes, `redactArguments`, literal loop). Keeps a ~10-line `public struct Redactor` wrapper over `SwiftRedaction.Redactor(.buildTool.adding(literalSecrets:))` and the `Redactor.placeholder` constant, so `RunDiagnostics`, `ReleasePipeline` and any external caller (*unverified: only grep hits in those two files were seen*) do not change; the wrapper is removed in a later release.
- Tests: `RedactorTests` move verbatim to `Tests/RedactionTests/BuildToolPolicyTests.swift` (they use `[REDACTED]` and `a [REDACTED] b [REDACTED]`, so `.buildTool` uses `.uniform` style and byte-identical output on every existing assertion is the acceptance test). ReleaseKit keeps one smoke test that `RunDiagnostics` output contains no fixture secret, using `expectNoLeaks`.
- Risk: **low.** `.buildTool` is a superset of today's behavior plus `bearer` and the 4-4-4-4 guard. The guard is the one deliberate narrowing (§3.3 item 5): it must still catch the `abcd-efgh-ijkl-mnop` test fixture, so the guard is context (preceded by a password/credential word, or in an `app-specific` message), and that is exactly the kind of choice to settle with the owner (Q4).

**SwiftDiagnosticsHub**
- Deletes: `LogScrubber`'s rules, compilation, and the `declaredRuleCount` / `compiledRuleCount` test hooks (moved into the package). Keeps `public enum LogScrubber { static func scrub(_:) }` as a one-line forward to `Redactor.appLog.redact`, so `DiagnosticsUploader` is unchanged.
- Tests: `LogScrubberTests` move verbatim to `AppLogPolicyTests`; the "ordinary lines survive exactly" corpus becomes a shared fixture that **both** policies are run against (`.buildTool` must also leave them alone).
- Risk: **medium.** (a) The app now has an external package dependency (a sibling repo; the dependency mechanism between the owner's repos is *unverified*, Q5). (b) `.appLog` must reproduce output byte-for-byte on the existing tests including the `Music-User-Token:` -> `=` rewrite and the `Bearer [token]` form (§3.3 item 13); a golden-output suite over the old scrubber's results on a fixed corpus is run once against the old and new implementations before the old one is deleted. (c) Behavior changes that are intended (the email rule becomes linear, the length cap, `secretAssignment` if adopted) are listed in the CHANGELOG as changes, not hidden.

**Other consumers (later, one at a time, each its own proposal or PR):** SwiftMCPServer `sanitizeForLogging` (replace with rules; removes per-call regex compilation), then the four access-path redactors via the structural module, then others found by a re-run of the survey.

## 9. Backend Abstraction: regex engine, performance, ReDoS

**Not compute-intensive; included because the choice of engine is the main technical decision.**

| | Swift Regex (`/.../`, `Regex<...>`) | `NSRegularExpression` |
|---|---|---|
| Availability | Swift 5.7+ runtime; **macOS 13+, iOS 16+**; on Linux it ships with the toolchain (`_StringProcessing`) so it is present wherever Swift 6.2 is; fine for macOS 14 and the iOS 17 target | all Apple platforms for years; Linux in swift-corelibs-foundation (ICU bundled). *Linux behavior of lookbehind and Unicode properties unverified* |
| Syntax | regex literals need Swift 6 language mode or `-enable-bare-slash-regex`; builder DSL available | strings with ICU syntax (lookbehind `(?<!...)`, lookahead, `{n,}`; both existing scrubbers' patterns already rely on lookaround) |
| Matching unit | `Character` (grapheme cluster) by default: `\w`, `\b`, `[a-z]` semantics differ from ICU on combining sequences | UTF-16 code units, ICU semantics |
| Cost | pattern parsed/compiled each time a literal is evaluated unless held in a stored `Regex` value (`Redactor` today re-evaluates literals inside `redact`); backtracking engine, **reported to be slower than ICU on large inputs (*unverified; measure in step 1*)** | compile once, reuse (`LogScrubber` does); fast scanning; known ICU limits (stack/time) that silently stop matching (*unverified here*) |
| Failure mode | none for time; no limit | **silent no-match when a limit trips**, i.e. fail open |
| Sendable | `Regex` is Sendable in recent toolchains (*unverified for 6.2*) | see §7 |

**Recommendation:** `NSRegularExpression`, each rule compiled **once** at `Redactor.init`, because the existing, working scrubber already uses it, its lookaround is what the better patterns need, and the Swift Regex alternative has a runtime floor and a per-evaluation cost with no safety advantage. Decide finally after a 1-day measurement spike in step 1 (same fixture corpus, both engines, macOS and Linux), recorded in the master plan. The engine sits behind an internal `PatternMatcher` protocol so a rule can instead be a **hand-written linear scanner**, which the dangerous shapes should be.

**ReDoS and bounds (log lines are attacker-influenced):**
1. **Length cap first, fail closed.** Before any regex runs, a line over `maxInputLength` (default 4,096 characters for `.appLog`, much larger for `.buildTool` where input is a captured tool log, processed in chunks) is replaced whole (`[line too long]`) or truncated then redacted. This alone turns the measured 20,000-character, 5.9 s email case into a bounded cost, and does so whether or not any pattern is quadratic.
2. **Linear patterns.** Every rule is reviewed for: no nested quantifiers; every unbounded `+`/`*` run starts at a position guarded by a lookbehind or anchor so a failed start does not rescan the same run (`longBase64` already does this with `(?<![A-Za-z0-9+/])`; `email` and `secretFlag`'s `[a-z-]*` do not). `email` is rewritten as: find `@`, expand left over local-part characters (capped at 64, per RFC), expand right over the domain (capped at 255). That is a single pass and is not a regex.
3. **Quantifier bounds** where the format allows (`{1,64}` for a local part; JWT segments `{5,2048}`), so a single match cannot be arbitrarily long.
4. **A worst-case test per rule**: a 1 MB run of that rule's own character class, of the class plus a near-miss suffix, and a repeated near-miss prefix; each must finish under a time limit (Swift Testing `.timeLimit`), on every CI host. This test is what would have caught the email rule.
5. **Never loop on matches in Swift** (`while let match = ...`) without advancing; use `stringByReplacingMatches` once per rule so there is one pass per rule, `rules.count` passes per line (16 today, cheap at a 4 KB cap).

**Output of rules on already-redacted text** must not re-match (§7 idempotence), and a rule's replacement must not create a new match across the seam with neighboring text; a property test over random concatenations checks it.

## 10. Dependencies

- Internal: none (new package).
- External: Foundation only in `Redaction`. `RedactionTestSupport` imports `Testing`. **No** swift-argument-parser, no swift-log, no SwiftSyntax, no BusinessMath. Cross-platform: Apple platforms and Linux. No `Security`, `os`, `CryptoKit` import (a CryptoKit/Crypto dependency to hash literal secrets for comparison was considered and rejected: it adds nothing the report needs).

## 11. Test Strategy

Red first, Swift Testing, as the existing suites. **The existing 19 tests (8 + 11) become the first 19 tests of the package, moved unchanged, and must pass before anything new is added** (the byte-compat gate).

**Test categories**
- **Per rule (golden):** each rule has a named suite: positive fixtures (must be removed), negative fixtures (must survive), boundary (min/max length, case), Unicode neighbors. Fixtures live in one `Fixtures/` directory shared by both policies, each labeled with the rule that owns it.
- **Policy:** `.buildTool` keeps the identifiers line unchanged (key ID, issuer UUID, team ID, profile name, `.p8` path); `.appLog` removes the issuer UUID and the home path from that very line (the two policies provably differ on a shared fixture).
- **Idempotence:** for every fixture and every policy, `redact(redact(x)) == redact(x)`; plus random concatenations of fixtures.
- **Determinism:** shuffled `rules:` in a policy gives identical output; repeated runs identical; (Linux and macOS compared by the same golden file).
- **Report:** `fired` counts match for a known line; the report never contains a fixture secret (asserted with the package's own helper); `redact(x) == report(x).output`.
- **Fail closed:** an over-length line is replaced; an invalid rule makes `init` throw; no test path returns an input unmodified after an error.
- **Adversarial / performance:** §9 item 4, per rule, with a time limit; a 1 MB single-line input per policy completes under the limit.
- **False-positive corpus:** a checked-in file of realistic ordinary lines (the eight-line corpus extended with build output, test names, git SHAs, Swift identifiers, URLs); both policies are expected to leave specified subsets alone, so a loosened rule that starts eating them fails a test. SHAs and CamelCase identifiers are included so the §3.3 item 11 trade-off is a stated, tested decision, not an accident.
- **Test-support self-test:** `findLeaks` must fail on a planted leak in a string, in a file, in `Data`, in an error's `reflecting` rendering, and in a base64-encoded form; and pass on clean input. (A privacy helper that cannot fail is the standard defect.)
- **`patternsCompile` kept** (declared equals compiled), now at `init` as a thrown error plus a test that every catalogue rule constructs.

**Reference truth:** each rule's fixtures cite the format's source: JWT RFC 7519 section 3 (three base64url segments), PEM RFC 7468 (`-----BEGIN ... -----`), email RFC 5321 length limits (64 local, 255 domain), UUID RFC 4122, IPv4/IPv6 RFC 4291 text forms, Apple's documented `xxxx-xxxx-xxxx-xxxx` app-specific password format (the format's shape is from the existing code; Apple's page not re-checked: *unverified*). Fixtures are synthetic; **no real credential is ever committed** (the existing JWT fixtures are synthetic: repo).

**Validation trace (becomes golden assertions):**
- `redact("peer 10.0.1.114 reset")` with `.appLog` -> `"peer [ip] reset"` (repo: the example in `LogScrubber`'s doc).
- `redact("a s3cr3t-value b s3cr3t-value")` with `.buildTool.adding(literalSecrets: ["s3cr3t-value", ""])` -> `"a [REDACTED] b [REDACTED]"` (repo test).
- `redactArguments(["notarytool","store-credentials","--password","hunter2xyz","--team-id","BNDA9Y6YV9"])` -> `[..., "--password", "[REDACTED]", "--team-id", "BNDA9Y6YV9"]` (repo test).
- The identifiers line is unchanged by `.buildTool` and changed by `.appLog` (repo fixture from `identifiersSurvive`).

**Not testable offline, checked by hand and recorded:** Linux behavior on a Linux host (does one exist in the owner's fleet? *unverified*; CI on one is a step-1 acceptance), and real-device log upload end to end (stays in SwiftDiagnosticsHub).

## 12. Architecture Decision Review

- **ADR:** one package, two policies, a catalogue of named rules. A rule's id is part of the public API (it appears in reports); renaming one is a breaking change.
- **ADR:** fail closed (overlong input and construction errors never pass text through). This changes `LogScrubber`'s behavior; stated in the CHANGELOG.
- **ADR:** `NSRegularExpression` compiled once per `Redactor`, behind an internal matcher protocol; Swift Regex re-evaluated after the measurement spike.
- **ADR:** the scrubber is defense in depth; types are the privacy line. The README says so before it says anything else.
- **Layering:** core has no policy knowledge of any app; apps add rules (`apiKeyPrefix`) and literal secrets through the policy, never by forking a pattern.
- Supersedes nothing in this repo's `architecture_decisions.md`; the owning repos' ADRs about scrubbing (SwiftDiagnosticsHub `DiagnosticsHub.md` section 12) are *amended* to reference the package (not read beyond that proposal).

## 13. Adversarial Review

**Strongest case for a different approach:** do not share. Two scrubbers with different jobs and different policies are small (55 and 94 lines); a shared package adds a dependency, a version to coordinate and a repository to maintain, and the *policy* differences (UUIDs survive in one, die in the other) are most of the code. A reviewer would say: fix the two real bugs in place (the quadratic email rule, the missing Bearer rule) and stop. It is a fair case: this proposal costs a repo for about 150 lines of logic.

**Where this design is most likely wrong:**
- It assumes the two policies are *subsets of one catalogue*. If `.appLog` ends up needing per-rule options (a different hex length, a different path rule) the catalogue becomes a configuration language, which is where shared libraries go to die. Mitigation: rules are not parameterized in v1 except `apiKeyPrefix` and literals; a third policy that needs a parameter is the signal to stop and re-design.
- It assumes byte-compatibility is achievable while changing the email rule from a regex to a scanner. The edge cases of the old regex (a trailing dot, consecutive dots, `%`) must be matched or consciously changed; the golden corpus is the only protection, so its breadth matters more than any other test.
- It assumes `NSRegularExpression` behaves identically on Linux. Unverified; lookbehind support in ICU is expected, not seen.
- It accepts an **external dependency in every app** for a privacy feature. A dependency can be compromised or break; it is small and Foundation-only, which lowers but does not remove the risk.

**What an experienced critic would say:** "You are building a regex catalogue and calling it a privacy control; the actual control is not logging secrets." True, and the proposal says so in section 7 (types are the privacy line). We proceed because a net under the type system is cheap, two copies already exist, and a measured quadratic bug in an attacker-reachable path is itself the argument for one well-tested implementation.

## 14. Alternatives Considered

1. **Fix both in place, no shared package.** Advantage: no dependency, no new repo. Disadvantage: the two diverge again; the access-path redactor has already been copied four times, which is the evidence that "just copy it" is the actual workflow. Rejected, but this is the main alternative.
2. **Merge into an existing package** (SwiftDiagnosticsKit exports it; ReleaseKit imports that). Advantage: no new repo. Disadvantage: a build tool depending on a TestFlight client library; the Kit is app-side and linked into apps. Rejected.
3. **Swift Regex only, no NSRegularExpression.** Advantage: Swift-native, no ICU. Disadvantage: runtime floor, per-evaluation cost unless stored, no failure advantage (§9). Kept as the spike's second candidate.
4. **Allowlist instead of blacklist for log lines** (keep only tokens matching "ordinary" shapes; the approach `HTTPOrigin.couldBeCredential` takes for URL segments). Advantage: strictly safer against unknown secret shapes. Disadvantage: destroys the usefulness of free-text log lines (the point of uploading them) and is harder to explain; useful for **URLs and paths** (so it lands in the structural module), not for prose.
5. **Type-level redaction only** (`Redacted<T>` wrappers like `PrivateKeyFileDigest`, `TokenResponse`). Right at the source, already used, but cannot help with text that arrives as a string (tool output, peer-supplied log lines). Complementary, not an alternative; the README links to it as the first line of defense.
6. **Rely on `os.Logger` `privacy: .private`.** Platform-provided, but redacts only at *read* time on a device, does nothing for the string once exported (a TestFlight upload is exactly that case), and does not exist on Linux. Complementary.

## 15. Future Directions

- A `RedactionPaths` module for the access-path shape (`known`, `templates`, `credentialSegments`, a segment cap) replacing four copies, and a URL helper built on the "ordinary shape" allowlist.
- A `swift-redact` CLI (stdin filter, `--report`) for ad hoc scrubbing of a log before pasting it into an issue.
- A **corpus feedback loop**: the quality-gate corpus telemetry could sample *rule hit counts* (never text) to show which rules fire in the wild, using the report type.
- A `Redactor` that streams (a `redact(into:)` over a `FileHandle`) for large captured build logs.
- Entropy-based detection as an *opt-in*, reported rule, to catch unknown token shapes (false-positive cost likely high).
- Adding `quality-gate` support: a checker that flags `print`/`os_log` of a variable named like a secret, outside this package (the existing `KeychainSecretsChecker` is the model; it would stay in quality-gate).

## 16. Open Questions

1. **Share or fix in place** (the §13 counter-case)? *Recommendation:* share, starting with the core and the two policies only; defer the structural module until the core has shipped once.
2. **Engine:** `NSRegularExpression` as recommended, or Swift Regex after the spike? *Recommendation:* decide on measured numbers on both macOS and a Linux host.
3. **Should `.appLog` get `secretAssignment`** (so `password=hunter2` in an app log is removed)? It closes gap 3 but would also redact benign text such as `token: expired` or `tokens=5`. *Recommendation:* yes, with a value-shape requirement (the value must contain a digit or be 8+ characters), tested with a false-positive corpus.
4. **The 4-4-4-4 app-specific-password guard** (§3.3 item 5): how much context should be required? *Recommendation:* require a nearby credential word or the `app-specific` phrase; accept a missed bare password in build output, since notarytool prompts for it rather than printing it (*unverified*).
5. **How do the owner's packages depend on each other** (git URL and tag, local path, a private registry)? This decides the migration step for the apps. Not found in the files read.
6. **Default `maxInputLength` for `.appLog`**: 4,096? What does `DiagnosticsUploader` already cap a line at (not read)?
7. **Git SHAs:** keep removing 32+ hex (current `LogScrubber`), or allow exactly 40-hex preceded by a commit-ish label so a build's commit survives in bug reports (the DiagnosticsHub proposal wants a build-to-commit link)?
8. **Should `redactArguments` replace a value after a secret-named flag even when the next argument is itself a flag** (`--password --team-id X`)? Today it blanks the next element unconditionally, dropping the flag.
9. **Linux:** which host runs the Linux test pass, if any?
10. **Name:** `SwiftRedaction` (product `Redaction`) versus `SwiftScrub`. The portfolio uses "redact" in six places and "scrub" in two; *recommendation:* Redaction.

## 17. Documentation Strategy

**Documentation Type:** Narrative Article Required.

- Combines 3+ APIs (rules, policies, report, test support): Yes. Explanation over 50 lines: Yes. Needs background (what a scrubber can never do, ReDoS, why fail-closed): Yes.
- **Articles** (`.docc`, names matching no symbol): `WhatRedactionCannotDo.md` (the five limits of §7, first in the catalog), `WritingARule.md` (linear patterns, the worst-case test, fixtures), `ChoosingAPolicy.md` (the two shipped policies and how to derive a third), `TestingForLeaks.md` (the helper, with the error-renderings pattern from MCPClient).
- Every rule's DocC comment carries its positive and negative fixtures as examples; a `RuleCatalogue` table in the README is generated from the catalogue, so docs cannot drift from it.
- Also: README (status, platforms, "defense in depth" first), CHANGELOG with link references, master plan, one ADR per decision in §12, a migration note in each consuming repo's changelog, and the doc-housekeeping reconciliation before the first tag.
