import 'package:flutter/material.dart';

import '../about_config.dart';
import '../runtime/agent_runtime.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage(this.rt, {super.key});
  final AgentRuntime rt;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListenableBuilder(
          listenable: rt,
          builder: (context, _) => ListView(children: [
            SwitchListTile(
              title: const Text('Faulty mock model (~15%)'),
              subtitle: const Text('Randomly returns broken output to test validation and retry'),
              value: rt.faulty,
              onChanged: (v) => rt.configureMock(faulty: v, fixedSeed: rt.fixedSeed),
            ),
            SwitchListTile(
              title: const Text('Fixed random seed'),
              subtitle: const Text('Makes faulty output repeatable for testing (seed 42)'),
              value: rt.fixedSeed,
              onChanged: (v) => rt.configureMock(faulty: rt.faulty, fixedSeed: v),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.red),
              title: const Text('Reset demo data'),
              subtitle: const Text('Tasks, outbox and wallet. The audit log is never deleted.'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Reset demo data?'),
                    content: const Text('Tasks, outbox and wallet return to their starting values.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
                    ],
                  ),
                );
                if (ok == true) rt.resetDemoData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () => Navigator.of(context).push(PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const AboutPage(),
                transitionDuration: const Duration(milliseconds: 260),
                transitionsBuilder: (_, animation, secondary, child) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
                        .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
              )),
            ),
          ]),
        ),
      );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('About')),
        body: ListView(padding: const EdgeInsets.all(16), children: const [
          Text('NEXU AgentDeck', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text('Mobile Developer practical assessment'),
          Divider(height: 32),
          ListTile(title: Text('Candidate'), subtitle: Text(candidateFullName)),
          ListTile(title: Text('Task received'), subtitle: Text(taskReceivedAt)),
        ]),
      );
}
