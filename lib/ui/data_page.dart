import 'package:flutter/material.dart';

import '../runtime/agent_runtime.dart';
import 'chat_page.dart' show hms;

class DataPage extends StatelessWidget {
  const DataPage(this.rt, {super.key});
  final AgentRuntime rt;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Data')),
        body: ListenableBuilder(
          listenable: rt,
          builder: (context, _) {
            final d = rt.data;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.account_balance_wallet_outlined,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(child: Text('Available balance', style: TextStyle(fontWeight: FontWeight.w600))),
                    Text('${d.credits}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 5),
                    Text('credits', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
              const _Header('Tasks'),
              if (d.tasks.isEmpty) const ListTile(title: Text('No tasks yet')),
              for (final t in d.tasks)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary),
                    title: Text(t.title),
                    subtitle: Text('Due ${t.due}'),
                  ),
                ),
              const _Header('Outbox'),
              if (d.outbox.isEmpty) const ListTile(title: Text('No messages sent')),
              for (final m in d.outbox.reversed)
                Card(child: ListTile(
                  leading: const Icon(Icons.outbox_outlined),
                  title: Text('To ${m.to}',
                      style: TextStyle(decoration: m.recalled ? TextDecoration.lineThrough : null)),
                  subtitle: Text('${m.text}\n${hms(m.sentAt)}${m.recalled ? ' · recalled' : ''}'),
                  isThreeLine: true,
                )),
            ]);
          },
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10, left: 4),
        child: Text(t.toUpperCase(), style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.1, color: Theme.of(context).colorScheme.primary)),
      );
}
