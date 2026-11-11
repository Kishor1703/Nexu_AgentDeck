# NEXU AgentDeck (Flutter)

A human-in-the-loop AI agent app: a deterministic mock model proposes tool calls and a
safety runtime (validation, permissions, budget, stop, undo, audit) decides what may run.

## Prerequisites
Flutter 3.22+ (Dart 3.3+), Android Studio / Xcode, an emulator or device.

## Setup & run
```bash
# this repo ships lib/, test/ and pubspec.yaml; generate the platform folders once:
flutter create --platforms=android,ios --project-name nexu_agentdeck .
rm -f test/widget_test.dart      # generated sample test, not ours
flutter pub get
flutter test                     # runtime tests
flutter run                      # run on device/emulator
flutter build apk --release      # APK -> build/app/outputs/flutter-apk/app-release.apk
```
Before building, edit `lib/about_config.dart`

## Architecture
```
lib/runtime/   pure Dart, no widgets (testable without a screen)
  agent_runtime.dart  run engine: state machine, approvals, budget, stop, undo
  validator.dart      parses/validates raw model JSON (A2)
  policy.dart         permission rules (A1, A7)
  tools.dart          the six simulated tools + registry
  mock_model.dart     script from section 5 + faulty mode (seedable)
  audit.dart          append-only, hash-chained audit log
  pin.dart            salted-hash PIN
  storage.dart        Storage interface (SharedPreferences / in-memory for tests)
lib/ui/        chat, approval screen, data, audit, settings/about
```
**State management:** a single `ChangeNotifier` (`AgentRuntime`) + `ListenableBuilder`.
Why: one source of truth for runs/pending approval, no extra dependency, and the UI is a pure
function of the runtime, so Stop/Approve can never disagree with what is on screen.

## Technical explanation
- **One run:** `start()` -> log `run_started` -> loop: *Thinking* -> model returns raw JSON ->
  validate (A2) -> final answer ends the run, or a proposal -> budget check (A3) -> policy (A1/A7)
  -> log `proposal` -> SAFE auto-runs, otherwise *Awaiting approval* -> Approve/Reject (logged)
  -> *Executed* (log) -> *Result* (untrusted) -> next model step -> final answer / halt.
- **Untrusted text:** tool results are only ever put into `Observation`s and shown in an amber
  "UNTRUSTED" box. Nothing parses them into calls: only the model's JSON goes through
  `parseModelOutput`. Whatever is proposed right after a tool result is flagged, shows a warning
  banner and needs the PIN even for WRITE tools. The Trapville case is covered by a test.
- **Stop + Approve at once:** one `Completer` per approval (can only complete once) and a
  per-run `stopped` flag re-checked after every `await` and right before the tool mutates data.
  First call wins, the other is a no-op (`notPending`). Tests cover both orders.
- **Audit log:** no edit/delete API or UI; `entries` is an unmodifiable view; entries are
  hash-chained (SHA-256) so changes to the stored log are detected and shown. Reset demo data
  never touches it.
- **Real LLM, safely:** call it from a backend (no API key in the app), constrain output with
  tool/JSON schemas, keep the same validator/policy layer, treat all retrieved text as data
  (separate it from instructions), rate-limit and server-side re-check permissions, keep the PIN
  and approvals on-device, store the audit log server-side and add timeouts/cancellation.
- **AI usage disclosure:** *EDIT THIS HONESTLY.* This codebase was generated with AI assistance
  (Claude) from the brief, then reviewed by me. List what you wrote/changed yourself here.

## Feature completion
Complete: A–H, rules A1–A7, About screen, tests.
Simulated: all tools, weather, wallet, outbox (local only).
Not done / limitations: PIN is in SharedPreferences (salted hash, but a 4-digit PIN is brute-forceable;
production should use the Keystore/Keychain + lockout); the hash chain is tamper-*evident* not
tamper-*proof* on a rooted device; chat history of runs is not persisted (the audit log is);
PIN can't be changed after first creation; no real LLM.
