import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'audit.dart';
import 'mock_model.dart';
import 'models.dart';
import 'pin.dart';
import 'policy.dart';
import 'storage.dart';
import 'tools.dart';
import 'validator.dart';

enum RunStatus { running, awaitingApproval, done, rejected, stopped, failed, budget }

enum StepKind { thinking, proposed, approved, rejected, executed, result, error, finalAnswer, halted, stopped }

enum ApproveResult { ok, notPending, tooEarly, badPin }

enum _Decision { approved, rejected, stopped }

class RunStep {
  RunStep({
    required this.runId,
    required this.kind,
    required this.text,
    required this.time,
    this.untrusted = false,
    this.warning = false,
    this.tool,
    this.refId,
    this.irreversible = false,
  });
  final String runId, text;
  final StepKind kind;
  final DateTime time;
  final bool untrusted, warning, irreversible;
  final String? tool, refId;
  bool undone = false;
}

class AgentRun {
  AgentRun(this.id, this.request);
  final String id, request;
  final List<RunStep> steps = [];
  RunStatus status = RunStatus.running;
  String? finalText;
  bool get isActive => status == RunStatus.running || status == RunStatus.awaitingApproval;
}

class PendingApproval {
  PendingApproval(this.runId, this.call, this.permission, this.policy, this.shownAt);
  final String runId;
  final ToolCall call;
  final Permission permission;
  final Policy policy;
  final DateTime shownAt;
  final Completer<_Decision> _c = Completer<_Decision>();
  bool get resolved => _c.isCompleted;
}

class _Session {
  _Session(this.run);
  final AgentRun run;
  bool stopped = false;
}

/// The agent runtime: validation, permissions, budget, stop, undo and audit.
/// No Flutter widgets in here, so it is unit-testable without a screen.
///
/// Concurrency: Dart runs one isolate, so the methods below never interleave
/// mid-way except at `await`. Every decision goes through ONE Completer that
/// can only be completed once, and `_Session.stopped` is re-checked after
/// every `await` and right before any tool mutates data. Whichever of
/// Stop / Approve runs first wins; the loser is a no-op.
class AgentRuntime extends ChangeNotifier {
  AgentRuntime({
    required this.storage,
    required this.model,
    required this.data,
    required this.audit,
    required this.pin,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.faulty = false,
    this.fixedSeed = false,
  })  : _now = clock ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  static const maxToolCalls = 5;
  static const maxDangerCalls = 1;
  static const recallWindow = Duration(seconds: 30);

  final Storage storage;
  final AuditLog audit;
  final PinService pin;
  AgentModel model;
  AppData data;
  bool faulty, fixedSeed;
  final List<AgentRun> runs = [];
  PendingApproval? pending;
  _Session? _session;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  DateTime now() => _now();
  bool get busy => _session != null;

  static Future<AgentRuntime> load(Storage st) async {
    var data = AppData.fresh();
    var audit = AuditLog();
    var faulty = false, fixed = false;
    try {
      final raw = await st.read('data');
      if (raw != null) data = AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    try {
      final raw = await st.read('audit');
      if (raw != null) audit = AuditLog.fromJson(jsonDecode(raw) as List);
    } catch (_) {}
    try {
      final raw = await st.read('settings');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        faulty = m['faulty'] == true;
        fixed = m['fixedSeed'] == true;
      }
    } catch (_) {}
    final pin = PinService(st);
    await pin.load();
    return AgentRuntime(
      storage: st,
      model: _buildModel(faulty, fixed),
      data: data,
      audit: audit,
      pin: pin,
      faulty: faulty,
      fixedSeed: fixed,
    );
  }

  static AgentModel _buildModel(bool faulty, bool fixed) =>
      MockModel(faulty: faulty, rng: fixed ? Random(42) : Random());

  // ---------------------------------------------------------------- runs

  Future<void> start(String request) async {
    if (_session != null || request.trim().isEmpty) return;
    final run = AgentRun(newId(), request.trim());
    runs.add(run);
    final s = _Session(run);
    _session = s;
    _log(run.id, 'run_started', {'request': run.request});
    notifyListeners();
    try {
      await _loop(s);
    } catch (e) {
      // The app must never crash because of a run.
      _log(run.id, 'internal_error', {'error': e.toString()});
      _finish(s, RunStatus.failed, 'Agent failed');
    } finally {
      if (identical(_session, s)) _session = null;
      notifyListeners();
    }
  }

  Future<void> _loop(_Session s) async {
    final run = s.run;
    final obs = <Observation>[];
    var calls = 0, dangerCalls = 0, failures = 0;

    while (true) {
      if (s.stopped) return;
      _step(run, StepKind.thinking, 'Thinking…');
      await _sleep(const Duration(milliseconds: 350));
      if (s.stopped) return;
      final raw = await model.next(ModelContext(run.request, List.unmodifiable(obs)));
      if (s.stopped) return;

      final out = parseModelOutput(raw);
      if (out is InvalidOutput) {
        // A2: log, retry the model once; second consecutive failure ends the run.
        failures++;
        _step(run, StepKind.error, 'Invalid model output: ${out.error}');
        _log(run.id, 'validation_error', {'error': out.error, 'raw': _clip(raw), 'attempt': failures});
        if (failures >= 2) {
          _finish(s, RunStatus.failed, 'Agent failed');
          return;
        }
        continue;
      }
      failures = 0;

      if (out is FinalOutput) {
        final fromTool = obs.any((o) => !o.rejected && out.text.contains(o.text));
        _finish(s, RunStatus.done, out.text, untrusted: fromTool);
        return;
      }

      final call = (out as ProposalOutput).call;
      final def = toolRegistry[call.tool]!;

      // A3: budget.
      final isDanger = def.permission == Permission.danger;
      if (calls >= maxToolCalls || (isDanger && dangerCalls >= maxDangerCalls)) {
        _log(run.id, 'budget_halt', {'tool': call.tool, 'calls': calls, 'dangerCalls': dangerCalls});
        _finish(s, RunStatus.budget, 'Budget reached');
        return;
      }
      calls++;
      if (isDanger) dangerCalls++;

      // A7: anything proposed right after a tool result is "tainted".
      final tainted = obs.isNotEmpty && !obs.last.rejected;
      final policy = policyFor(def.permission, tainted: tainted);
      _step(run, StepKind.proposed, 'Proposed ${call.tool}(${jsonEncode(call.args)}) — ${call.reason}',
          warning: policy.warning, tool: call.tool);
      _log(run.id, 'proposal', {
        'tool': call.tool,
        'args': call.args,
        'reason': call.reason,
        'permission': def.permission.name,
        'afterUntrustedResult': tainted,
        'needsApproval': policy.needsApproval,
        'needsPin': policy.needsPin,
      });

      if (policy.needsApproval) {
        final decision = await _awaitApproval(s, call, def.permission, policy);
        if (decision == _Decision.stopped || s.stopped) return;
        _log(run.id, 'decision', {'tool': call.tool, 'decision': decision.name});
        if (decision == _Decision.rejected) {
          // A4: tool does not run; model gives a final answer; run ends.
          _step(run, StepKind.rejected, 'You rejected ${call.tool}. It did not run.');
          obs.add(Observation(call.tool, 'Rejected by user', rejected: true));
          final next = parseModelOutput(await model.next(ModelContext(run.request, List.unmodifiable(obs))));
          if (s.stopped) return;
          _finish(s, RunStatus.rejected,
              next is FinalOutput ? next.text : 'Okay, I did not run ${call.tool}.');
          return;
        }
        _step(run, StepKind.approved, 'You approved ${call.tool}.');
      } else {
        _log(run.id, 'decision', {'tool': call.tool, 'decision': 'auto_safe'});
      }

      // Simulated latency: Stop can land here and cancels the tool.
      await _sleep(const Duration(milliseconds: 400));
      if (s.stopped) return;
      // ---- commit point: synchronous, no await between the check and the mutation.
      final r = def.run(data, call.args, _now());
      _persistData();
      _log(run.id, 'execution', {'tool': call.tool, 'args': call.args, 'result': r.text, 'refId': r.refId});
      _step(run, StepKind.executed, 'Executed ${call.tool}',
          tool: call.tool, refId: r.refId, irreversible: isDanger);
      _step(run, StepKind.result, r.text, untrusted: true);
      obs.add(Observation(call.tool, r.text));
    }
  }

  Future<_Decision> _awaitApproval(_Session s, ToolCall call, Permission perm, Policy pol) async {
    final p = PendingApproval(s.run.id, call, perm, pol, _now());
    pending = p;
    s.run.status = RunStatus.awaitingApproval;
    notifyListeners();
    final d = await p._c.future;
    if (identical(pending, p)) pending = null;
    if (!s.stopped && s.run.isActive) s.run.status = RunStatus.running;
    notifyListeners();
    return d;
  }

  /// A1 is enforced HERE (delay + PIN), not only in the UI.
  Future<ApproveResult> approve({String? pinCode}) async {
    final p = pending, s = _session;
    if (p == null || s == null || s.stopped || p.resolved) return ApproveResult.notPending;
    if (_now().difference(p.shownAt) < Duration(seconds: p.policy.delaySeconds)) {
      return ApproveResult.tooEarly;
    }
    if (p.policy.needsPin) {
      if (pinCode == null || !PinService.isValidFormat(pinCode)) return ApproveResult.badPin;
      if (!pin.isSet) {
        await pin.setPin(pinCode); // first use creates the PIN
      } else if (!pin.verify(pinCode)) {
        return ApproveResult.badPin;
      }
    }
    // Re-check after the await above: Stop may have won the race.
    if (s.stopped || p.resolved || !identical(pending, p)) return ApproveResult.notPending;
    p._c.complete(_Decision.approved);
    return ApproveResult.ok;
  }

  bool reject() {
    final p = pending, s = _session;
    if (p == null || s == null || s.stopped || p.resolved) return false;
    p._c.complete(_Decision.rejected);
    return true;
  }

  /// A5: cancels immediately, including a pending approval or a tool in flight.
  void stop() {
    final s = _session;
    if (s == null || s.stopped) return;
    s.stopped = true;
    final p = pending;
    pending = null;
    if (p != null && !p._c.isCompleted) p._c.complete(_Decision.stopped);
    _log(s.run.id, 'stop', {'pendingTool': p?.call.tool});
    _finish(s, RunStatus.stopped, 'Stopped by you. No further tools will run.');
    _session = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- undo (A6)

  bool undoTask(RunStep step) {
    if (step.tool != 'create_task' || step.undone || step.refId == null) return false;
    final i = data.tasks.indexWhere((t) => t.id == step.refId);
    if (i < 0) return false;
    final t = data.tasks.removeAt(i);
    step.undone = true;
    _persistData();
    _log(step.runId, 'undo', {'tool': 'create_task', 'task': t.title});
    notifyListeners();
    return true;
  }

  int recallSecondsLeft(RunStep step) {
    if (step.tool != 'send_message' || step.undone) return 0;
    final i = data.outbox.indexWhere((m) => m.id == step.refId);
    if (i < 0) return 0;
    final left = recallWindow - _now().difference(data.outbox[i].sentAt);
    return left.isNegative ? 0 : left.inSeconds + 1;
  }

  bool recallMessage(RunStep step) {
    if (recallSecondsLeft(step) <= 0) return false;
    final m = data.outbox.firstWhere((m) => m.id == step.refId);
    m.recalled = true;
    step.undone = true;
    _persistData();
    _log(step.runId, 'recall', {'tool': 'send_message', 'to': m.to});
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- settings

  void configureMock({required bool faulty, required bool fixedSeed}) {
    this.faulty = faulty;
    this.fixedSeed = fixedSeed;
    model = _buildModel(faulty, fixedSeed);
    unawaited(storage.write('settings', jsonEncode({'faulty': faulty, 'fixedSeed': fixedSeed})));
    notifyListeners();
  }

  /// Resets tasks, outbox and wallet. The audit log is deliberately NOT reset.
  void resetDemoData() {
    stop();
    data = AppData.fresh();
    runs.clear();
    _persistData();
    _log('system', 'reset_demo_data', {});
    notifyListeners();
  }

  // ---------------------------------------------------------------- helpers

  RunStep _step(AgentRun r, StepKind kind, String text,
      {bool untrusted = false, bool warning = false, String? tool, String? refId, bool irreversible = false}) {
    final st = RunStep(
        runId: r.id, kind: kind, text: text, time: _now(), untrusted: untrusted,
        warning: warning, tool: tool, refId: refId, irreversible: irreversible);
    r.steps.add(st);
    notifyListeners();
    return st;
  }

  void _finish(_Session s, RunStatus status, String text, {bool untrusted = false}) {
    final run = s.run;
    if (!run.isActive) return;
    run.status = status;
    run.finalText = text;
    final kind = switch (status) {
      RunStatus.done || RunStatus.rejected => StepKind.finalAnswer,
      RunStatus.stopped => StepKind.stopped,
      _ => StepKind.halted,
    };
    _step(run, kind, text, untrusted: untrusted);
    _log(run.id, 'run_ended', {'status': status.name, 'message': text});
  }

  void _log(String runId, String type, Map<String, dynamic> details) {
    audit.append(_now(), runId, type, details);
    unawaited(storage.write('audit', jsonEncode(audit.toJson())));
    notifyListeners();
  }

  void _persistData() => unawaited(storage.write('data', jsonEncode(data.toJson())));

  String _clip(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}
