# Testing summary
Run `flutter test`. 17 tests in `test/runtime_test.dart` cover A1 (permissions, delay, PIN), A2 (retry and
failure), A3 (5 calls, 1 danger), A4, A5 (stop, Stop/Approve race in both orders), A6, A7 (Trapville),
audit tamper detection and persistence.

**Results / bugs found: FILL IN after you run the tests and the manual checks below.**
Manual checklist: Trapville run (banner, PIN gate, 5s delay), Stop on pending approval, faulty mode with seed,
close and reopen app (tasks, outbox, wallet, audit persist), recall after 30s, audit copy as JSON.
