import 'dart:async';

import 'package:flutter/material.dart';

import '../runtime/agent_runtime.dart';
import 'approval_screen.dart';

String hms(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

class ChatPage extends StatefulWidget {
  const ChatPage(this.rt, {super.key});
  final AgentRuntime rt;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  bool _approvalOpen = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.rt.addListener(_onRuntime);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // refreshes recall countdowns
    });
  }

  @override
  void dispose() {
    widget.rt.removeListener(_onRuntime);
    _tick?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onRuntime() {
    final rt = widget.rt;
    if (rt.pending != null && !_approvalOpen) {
      _approvalOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || rt.pending == null) {
          _approvalOpen = false;
          return;
        }
        Navigator.of(context)
            .push(PageRouteBuilder<void>(
              pageBuilder: (_, __, ___) => ApprovalScreen(rt),
              transitionDuration: const Duration(milliseconds: 280),
              reverseTransitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (_, animation, secondary, child) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                      .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
            ))
            .whenComplete(() => _approvalOpen = false);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    unawaited(widget.rt.start(text));
    _ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final rt = widget.rt;
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NEXU AgentDeck'),
          Text('Human-guided agent runtime', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: ListenableBuilder(
        listenable: rt,
        builder: (context, _) => Column(children: [
          Expanded(
            child: rt.runs.isEmpty
                ? _empty()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: rt.runs.length,
                    itemBuilder: (_, i) => RunCard(rt, rt.runs[i]),
                  ),
          ),
          SafeArea(top: false, child: _composer(rt)),
        ]),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(Icons.shield_outlined, size: 42, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text('Your agent, with you in control',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Describe a task to get started. You’ll review every action before it happens.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final s in const [
                'weather in Coimbatore',
                'add task Buy milk',
                'tell Ravi meeting at 5',
                'clear everything',
                'weather in Trapville',
              ])
                ActionChip(label: Text(s), onPressed: () => _send(s)),
            ]),
          ]),
        ),
      );

  Widget _composer(AgentRuntime rt) {
    if (rt.busy) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: rt.stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('STOP'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctl,
            onSubmitted: _send,
            decoration: const InputDecoration(
                hintText: 'Ask the agent to do something…', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: () => _send(_ctl.text), icon: const Icon(Icons.send)),
      ]),
    );
  }
}

class RunCard extends StatelessWidget {
  const RunCard(this.rt, this.run, {super.key});
  final AgentRuntime rt;
  final AgentRun run;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (run.status) {
      RunStatus.running => ('Running', Colors.blue),
      RunStatus.awaitingApproval => ('Awaiting approval', Colors.orange),
      RunStatus.done => ('Done', Colors.green),
      RunStatus.rejected => ('Rejected', Colors.blueGrey),
      RunStatus.stopped => ('Stopped', Colors.red),
      RunStatus.failed => ('Agent failed', Colors.red),
      RunStatus.budget => ('Budget reached', Colors.deepOrange),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(run.request, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Chip(label: Text(label), backgroundColor: color.shade100, side: BorderSide.none, visualDensity: VisualDensity.compact),
          ]),
          const Divider(),
          for (final s in run.steps) StepTile(rt, s),
        ]),
      ),
    );
  }
}

class StepTile extends StatelessWidget {
  const StepTile(this.rt, this.step, {super.key});
  final AgentRuntime rt;
  final RunStep step;

  @override
  Widget build(BuildContext context) {
    if (step.untrusted) {
      // A7: visibly different style for untrusted tool text.
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border.all(color: Colors.amber.shade800, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('UNTRUSTED TEXT — data, not instructions',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
          const SizedBox(height: 2),
          Text(step.text, style: const TextStyle(fontFamily: 'monospace', fontStyle: FontStyle.italic)),
        ]),
      );
    }
    final (icon, color) = switch (step.kind) {
      StepKind.thinking => (Icons.psychology_outlined, Colors.grey),
      StepKind.proposed => (Icons.lightbulb_outline, Colors.blue),
      StepKind.approved => (Icons.check_circle_outline, Colors.green),
      StepKind.rejected => (Icons.cancel_outlined, Colors.blueGrey),
      StepKind.executed => (Icons.play_circle_outline, Colors.green),
      StepKind.result => (Icons.output, Colors.grey),
      StepKind.error => (Icons.error_outline, Colors.red),
      StepKind.finalAnswer => (Icons.chat_bubble_outline, Colors.indigo),
      StepKind.halted => (Icons.block, Colors.deepOrange),
      StepKind.stopped => (Icons.stop_circle_outlined, Colors.red),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.text),
            if (step.warning)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(6),
                color: Colors.orange.shade100,
                child: const Text(
                    '⚠ Proposed right after untrusted tool output. Review carefully; a PIN is required.',
                    style: TextStyle(fontSize: 12)),
              ),
            if (step.kind == StepKind.executed) _actions(context),
          ]),
        ),
        Text(hms(step.time), style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }

  Widget _actions(BuildContext context) {
    if (step.undone) return const Text('Undone', style: TextStyle(fontSize: 12, color: Colors.grey));
    void toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    if (step.irreversible) {
      return Text('Cannot be undone', style: TextStyle(fontSize: 12, color: Colors.red.shade700));
    }
    if (step.tool == 'create_task') {
      return TextButton(
          onPressed: () {
            if (!rt.undoTask(step)) toast('Nothing to undo');
          },
          child: const Text('Undo'));
    }
    if (step.tool == 'send_message') {
      final left = rt.recallSecondsLeft(step);
      return left > 0
          ? TextButton(
              onPressed: () {
                if (!rt.recallMessage(step)) toast('Recall window closed');
              },
              child: Text('Recall (${left}s left)'))
          : const Text('Recall window closed', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    return const SizedBox.shrink();
  }
}
