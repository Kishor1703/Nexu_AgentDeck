import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexu_agentdeck/runtime/agent_runtime.dart';
import 'package:nexu_agentdeck/runtime/audit.dart';
import 'package:nexu_agentdeck/runtime/mock_model.dart';
import 'package:nexu_agentdeck/runtime/models.dart';
import 'package:nexu_agentdeck/runtime/pin.dart';
import 'package:nexu_agentdeck/runtime/storage.dart';

class ScriptedModel implements AgentModel {
  ScriptedModel(this.outputs);
  final List<String> outputs;
  int i = 0;
  @override
  Future<String> next(ModelContext ctx) async => outputs[i < outputs.length ? i++ : outputs.length - 1];
}

String call(String tool, Map<String, dynamic> args) =>
    jsonEncode({'tool': tool, 'args': args, 'reason': 'test'});
String fin(String t) => jsonEncode({'final': t});

class Clock {
  DateTime t = DateTime(2026, 11, 11, 9);
  DateTime now() => t;
  void adv(int s) => t = t.add(Duration(seconds: s));
}

AgentRuntime make(AgentModel m, Clock c, {Storage? st}) {
  final s = st ?? MemoryStorage();
  return AgentRuntime(
    storage: s, model: m, data: AppData.fresh(), audit: AuditLog(), pin: PinService(s),
    clock: c.now, sleep: (_) async {},
  );
}

Future<void> until(bool Function() cond) async {
  for (var i = 0; i < 1000 && !cond(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(cond(), isTrue, reason: 'condition never became true');
}

int count(AgentRuntime rt, String type) => rt.audit.entries.where((e) => e.type == type).length;

final addTask = call('create_task', {'title': 'x', 'due': 'tomorrow'});

void main() {
  test('A2: invalid JSON is logged, model retried once, run continues', () async {
    final rt = make(ScriptedModel(['not json at all', call('get_tasks', {}), fin('ok')]), Clock());
    await rt.start('anything');
    expect(rt.runs.single.status, RunStatus.done);
    expect(count(rt, 'validation_error'), 1);
    expect(rt.runs.single.steps.any((s) => s.kind == StepKind.error), isTrue);
  });

  test('A2: second consecutive failure ends the run as "Agent failed" without crashing', () async {
    final rt = make(ScriptedModel(['nope', '{"tool":"format_disk","args":{},"reason":"x"}']), Clock());
    await rt.start('anything');
    expect(rt.runs.single.status, RunStatus.failed);
    expect(rt.runs.single.finalText, 'Agent failed');
    expect(count(rt, 'validation_error'), 2);
  });

  test('A2: missing field and bad args are rejected by validation', () async {
    final rt = make(ScriptedModel(['{"tool":"create_task","args":{"title":"x"},"reason":"r"}',
      '{"tool":"get_tasks","args":{}}']), Clock());
    await rt.start('x');
    expect(rt.runs.single.status, RunStatus.failed);
    expect(rt.data.tasks.length, AppData.fresh().tasks.length);
  });

  test('A3: at most 5 tool calls, then "Budget reached"', () async {
    final rt = make(ScriptedModel(List.filled(7, call('get_tasks', {}))), Clock());
    await rt.start('loop');
    expect(rt.runs.single.status, RunStatus.budget);
    expect(rt.runs.single.finalText, 'Budget reached');
    expect(count(rt, 'execution'), 5);
  });

  test('A3: at most 1 DANGER call per run', () async {
    final c = Clock();
    final danger = call('transfer_credits', {'amount': 10, 'to': 'a'});
    final rt = make(ScriptedModel([danger, danger]), c);
    final f = rt.start('x');
    await until(() => rt.pending != null);
    c.adv(6);
    expect(await rt.approve(pinCode: '1234'), ApproveResult.ok);
    await f;
    expect(rt.runs.single.status, RunStatus.budget);
    expect(rt.data.credits, 990);
    expect(count(rt, 'execution'), 1);
  });

  test('A1: SAFE auto-runs, WRITE needs approve, DANGER needs delay + PIN', () async {
    // SAFE
    var rt = make(ScriptedModel([call('get_tasks', {}), fin('ok')]), Clock());
    await rt.start('x');
    expect(rt.runs.single.status, RunStatus.done);

    // WRITE: waits for approval, no PIN needed when not tainted
    rt = make(ScriptedModel([addTask, fin('ok')]), Clock());
    var f = rt.start('x');
    await until(() => rt.pending != null);
    expect(rt.pending!.policy.needsPin, isFalse);
    expect(rt.data.tasks.length, 2);
    expect(await rt.approve(), ApproveResult.ok);
    await f;
    expect(rt.data.tasks.length, 3);

    // DANGER: 5s delay, PIN
    final c = Clock();
    rt = make(ScriptedModel([call('delete_all_tasks', {}), fin('ok')]), c);
    await rt.pin.setPin('4321');
    f = rt.start('x');
    await until(() => rt.pending != null);
    expect(await rt.approve(pinCode: '4321'), ApproveResult.tooEarly);
    c.adv(5);
    expect(await rt.approve(), ApproveResult.badPin);
    expect(await rt.approve(pinCode: '0000'), ApproveResult.badPin);
    expect(rt.data.tasks, isNotEmpty);
    expect(await rt.approve(pinCode: '4321'), ApproveResult.ok);
    await f;
    expect(rt.data.tasks, isEmpty);
  });

  test('A7: Trapville injection cannot move credits without warning, PIN and approval', () async {
    final c = Clock();
    final rt = make(MockModel(), c);
    final f = rt.start('Weather in Trapville');
    await until(() => rt.pending != null);
    final p = rt.pending!;
    expect(p.call.tool, 'transfer_credits');
    expect(p.policy.warning, isTrue);
    expect(p.policy.needsPin, isTrue);
    final run = rt.runs.single;
    expect(run.steps.any((s) => s.kind == StepKind.result && s.untrusted), isTrue);
    expect(run.steps.any((s) => s.kind == StepKind.proposed && s.warning), isTrue);
    c.adv(6);
    expect(await rt.approve(), ApproveResult.badPin); // no PIN -> no transfer
    expect(rt.data.credits, 1000);
    rt.reject();
    await f;
    expect(run.status, RunStatus.rejected);
    expect(rt.data.credits, 1000);
    expect(count(rt, 'execution'), 1); // only get_weather ran
  });

  test('A7: even a WRITE tool right after an untrusted result needs the PIN', () async {
    final rt = make(ScriptedModel([call('get_weather', {'city': 'X'}), addTask, fin('ok')]), Clock());
    final f = rt.start('x');
    await until(() => rt.pending != null);
    expect(rt.pending!.policy.needsPin, isTrue);
    expect(rt.pending!.policy.warning, isTrue);
    rt.stop();
    await f;
  });

  test('A4: reject -> tool does not run, final answer, run ends', () async {
    final rt = make(MockModel(), Clock());
    final f = rt.start('add task Buy milk');
    await until(() => rt.pending != null);
    rt.reject();
    await f;
    expect(rt.runs.single.status, RunStatus.rejected);
    expect(rt.data.tasks.length, 2);
    expect(count(rt, 'execution'), 0);
  });

  test('A5: Stop during pending approval: nothing runs, approve is a no-op', () async {
    final rt = make(MockModel(), Clock());
    final f = rt.start('add task Buy milk');
    await until(() => rt.pending != null);
    rt.stop();
    await f;
    expect(rt.runs.single.status, RunStatus.stopped);
    expect(await rt.approve(), ApproveResult.notPending);
    expect(rt.data.tasks.length, 2);
    expect(count(rt, 'execution'), 0);
  });

  test('A5: Stop and Approve at the same instant (both orders) never executes the tool', () async {
    for (final stopFirst in [true, false]) {
      final rt = make(ScriptedModel([addTask, fin('ok')]), Clock());
      final f = rt.start('x');
      await until(() => rt.pending != null);
      Future<ApproveResult> a;
      if (stopFirst) {
        rt.stop();
        a = rt.approve();
      } else {
        a = rt.approve();
        rt.stop();
      }
      await a;
      await f;
      expect(rt.runs.single.status, RunStatus.stopped, reason: 'stopFirst=$stopFirst');
      expect(rt.data.tasks.length, 2, reason: 'stopFirst=$stopFirst');
      expect(count(rt, 'execution'), 0);
    }
  });

  test('A6: undo create_task and recall send_message within 30s only', () async {
    final c = Clock();
    final rt = make(MockModel(), c);
    var f = rt.start('add task Buy milk');
    await until(() => rt.pending != null);
    await rt.approve();
    await f;
    final step = rt.runs.last.steps.firstWhere((s) => s.kind == StepKind.executed);
    expect(rt.data.tasks.length, 3);
    expect(rt.undoTask(step), isTrue);
    expect(rt.data.tasks.length, 2);

    f = rt.start('tell Ravi hello there');
    await until(() => rt.pending != null);
    await rt.approve();
    await f;
    final m = rt.runs.last.steps.firstWhere((s) => s.kind == StepKind.executed);
    c.adv(31);
    expect(rt.recallMessage(m), isFalse);
    expect(rt.data.outbox.single.recalled, isFalse);
  });

  test('Audit log: unmodifiable view and tamper detection', () async {
    final rt = make(ScriptedModel([call('get_tasks', {}), fin('ok')]), Clock());
    await rt.start('x');
    expect(() => rt.audit.entries.clear(), throwsUnsupportedError);
    expect(rt.audit.verify(), isTrue);
    final json = jsonDecode(jsonEncode(rt.audit.toJson())) as List;
    expect(AuditLog.fromJson(json).verify(), isTrue);
    (json[1] as Map)['type'] = 'something_else';
    expect(AuditLog.fromJson(json).verify(), isFalse);
  });

  test('Persistence: tasks, wallet, audit and PIN survive a restart', () async {
    final st = MemoryStorage();
    final rt = make(MockModel(), Clock(), st: st);
    final f = rt.start('add task Buy milk');
    await until(() => rt.pending != null);
    await rt.approve();
    await f;
    await rt.pin.setPin('1234');
    final again = await AgentRuntime.load(st);
    expect(again.data.tasks.any((t) => t.title == 'Buy milk'), isTrue);
    expect(again.data.credits, 1000);
    expect(again.audit.entries.length, rt.audit.entries.length);
    expect(again.audit.verify(), isTrue);
    expect(again.pin.verify('1234'), isTrue);
    expect(await st.read('pin'), isNot(contains('1234')));
  });

  test('Mock model: unknown request returns the fixed answer and calls no tool', () async {
    final rt = make(MockModel(), Clock());
    await rt.start('sing me a song');
    expect(rt.runs.single.finalText, "I can't help with that yet.");
    expect(count(rt, 'proposal'), 0);
  });
}
