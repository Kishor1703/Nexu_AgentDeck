enum Permission { safe, write, danger }

class ToolCall {
  const ToolCall(this.tool, this.args, this.reason);
  final String tool;
  final Map<String, dynamic> args;
  final String reason;
}

/// Result of parsing/validating the raw string a model returned.
sealed class ModelOutput {}

class ProposalOutput extends ModelOutput {
  ProposalOutput(this.call);
  final ToolCall call;
}

class FinalOutput extends ModelOutput {
  FinalOutput(this.text);
  final String text;
}

class InvalidOutput extends ModelOutput {
  InvalidOutput(this.error);
  final String error;
}

/// What the model has seen so far in a run (tool results are UNTRUSTED data).
class Observation {
  const Observation(this.tool, this.text, {this.rejected = false});
  final String tool;
  final String text;
  final bool rejected;
}

class ModelContext {
  const ModelContext(this.request, this.observations);
  final String request;
  final List<Observation> observations;
}

abstract class AgentModel {
  /// Returns a raw JSON string: a proposal or {"final": "..."}.
  Future<String> next(ModelContext ctx);
}

int _idCounter = 0;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idCounter++).toRadixString(36)}';

class TaskItem {
  TaskItem({required this.id, required this.title, required this.due});
  final String id, title, due;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'due': due};
  factory TaskItem.fromJson(Map<String, dynamic> j) =>
      TaskItem(id: j['id'], title: j['title'], due: j['due']);
}

class OutboxMessage {
  OutboxMessage({
    required this.id,
    required this.to,
    required this.text,
    required this.sentAt,
    this.recalled = false,
  });
  final String id, to, text;
  final DateTime sentAt;
  bool recalled;
  Map<String, dynamic> toJson() => {
        'id': id,
        'to': to,
        'text': text,
        'sentAt': sentAt.toIso8601String(),
        'recalled': recalled,
      };
  factory OutboxMessage.fromJson(Map<String, dynamic> j) => OutboxMessage(
        id: j['id'],
        to: j['to'],
        text: j['text'],
        sentAt: DateTime.parse(j['sentAt']),
        recalled: j['recalled'] == true,
      );
}

class AppData {
  AppData({required this.tasks, required this.outbox, required this.credits});
  final List<TaskItem> tasks;
  final List<OutboxMessage> outbox;
  int credits;

  factory AppData.fresh() => AppData(tasks: [
        TaskItem(id: 'seed1', title: 'Review quarterly report', due: 'Fri 5:00 PM'),
        TaskItem(id: 'seed2', title: 'Book team lunch', due: 'Sat 12:00 PM'),
      ], outbox: [], credits: 1000);

  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'outbox': outbox.map((m) => m.toJson()).toList(),
        'credits': credits,
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        tasks: (j['tasks'] as List)
            .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        outbox: (j['outbox'] as List)
            .map((e) => OutboxMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        credits: j['credits'] as int,
      );
}
