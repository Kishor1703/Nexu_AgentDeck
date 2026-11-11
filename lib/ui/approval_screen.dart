import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../runtime/agent_runtime.dart';
import '../runtime/models.dart';

class ApprovalScreen extends StatefulWidget {
  const ApprovalScreen(this.rt, {super.key});
  final AgentRuntime rt;
  @override
  State<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends State<ApprovalScreen> {
  final _pin = TextEditingController();
  Timer? _t;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.rt.addListener(_check);
    _t = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void dispose() {
    widget.rt.removeListener(_check);
    _t?.cancel();
    _pin.dispose();
    super.dispose();
  }

  // Close as soon as the approval is resolved (approved, rejected or Stop).
  void _check() {
    if (widget.rt.pending == null && !_closed && mounted) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _approve() async {
    final r = await widget.rt.approve(pinCode: _pin.text);
    if (!mounted) return;
    switch (r) {
      case ApproveResult.ok:
        break;
      case ApproveResult.badPin:
        _toast('Wrong PIN');
      case ApproveResult.tooEarly:
        _toast('Please wait for the countdown');
      case ApproveResult.notPending:
        _toast('This request is no longer pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = widget.rt;
    final p = rt.pending;
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final waited = rt.now().difference(p.shownAt).inMilliseconds;
    final remaining = ((p.policy.delaySeconds * 1000 - waited) / 1000).ceil().clamp(0, 99);
    final pinOk = !p.policy.needsPin || RegExp(r'^\d{4}$').hasMatch(_pin.text);
    final canApprove = remaining == 0 && pinOk;
    final danger = p.permission == Permission.danger;
    final level = p.permission.name.toUpperCase();

    return PopScope(
      canPop: false, // must Approve, Reject or Stop
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Approval needed'),
          backgroundColor: danger ? Colors.red.shade100 : null,
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
          Row(children: [
            Chip(
              label: Text('$level permission'),
              backgroundColor: danger ? Colors.red.shade200 : Colors.orange.shade200,
            ),
          ]),
          const SizedBox(height: 8),
          Text('Review this action', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 4),
          Text(p.call.tool, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Arguments', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(const JsonEncoder.withIndent('  ').convert(p.call.args),
                style: const TextStyle(fontFamily: 'monospace')),
          ),
          const SizedBox(height: 8),
          const Text("Model's reason", style: TextStyle(fontWeight: FontWeight.bold)),
          Text(p.call.reason, style: Theme.of(context).textTheme.bodyLarge),
          if (p.policy.warning)
            _banner(Colors.orange, Icons.warning_amber,
                'WARNING: this step was proposed right after untrusted tool output. '
                'The text may have tricked the agent. Only approve if YOU want this.'),
          if (danger)
            _banner(Colors.red, Icons.block,
                'This action CANNOT be undone.'),
          if (p.policy.needsPin) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: rt.pin.isSet ? 'Enter your 4-digit PIN' : 'Create a 4-digit PIN',
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: canApprove ? _approve : null,
            child: Text(remaining > 0 ? 'Approve (wait ${remaining}s)' : 'Approve'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: rt.reject, child: const Text('Reject')),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: rt.stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('STOP'),
          ),
        ]),
      ),
    );
  }

  Widget _banner(MaterialColor c, IconData i, String t) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.shade50, border: Border.all(color: c.shade700)),
        child: Row(children: [
          Icon(i, color: c.shade800),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: TextStyle(color: c.shade900, fontWeight: FontWeight.w600))),
        ]),
      );
}
