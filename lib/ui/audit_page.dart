import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../runtime/agent_runtime.dart';
import 'chat_page.dart' show hms;

/// Read-only view: there is no edit or delete control anywhere.
class AuditPage extends StatelessWidget {
  const AuditPage(this.rt, {super.key});
  final AgentRuntime rt;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Audit log'), actions: [
          IconButton(
            tooltip: 'Copy as JSON',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: rt.audit.toJsonString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Audit log copied as JSON')));
              }
            },
          ),
        ]),
        body: ListenableBuilder(
          listenable: rt,
          builder: (context, _) {
            final entries = rt.audit.entries.reversed.toList();
            final ok = rt.audit.verify();
            if (entries.isEmpty) return const Center(child: Text('No activity yet'));
            return Column(children: [
              Container(
                width: double.infinity,
                color: ok ? Colors.green.shade50 : Colors.red.shade100,
                padding: const EdgeInsets.all(8),
                child: Text(
                    ok ? '✔ ${entries.length} entries · hash chain verified'
                       : '✖ Tampering detected: hash chain broken',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      title: Text('${e.type}  ·  ${hms(e.time)}'),
                      subtitle: Text('run ${e.runId.length > 6 ? e.runId.substring(e.runId.length - 6) : e.runId}\n'
                          '${jsonEncode(e.details)}',
                          maxLines: 4, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                    );
                  },
                ),
              ),
            ]);
          },
        ),
      );
}
