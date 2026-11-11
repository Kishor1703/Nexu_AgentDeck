import 'dart:convert';

import 'models.dart';
import 'tools.dart';

/// Parses and validates raw model output. Never throws.
ModelOutput parseModelOutput(String raw) {
  dynamic j;
  try {
    j = jsonDecode(raw);
  } catch (_) {
    return InvalidOutput('Output is not valid JSON');
  }
  if (j is! Map) return InvalidOutput('Output must be a JSON object');

  if (j.containsKey('final')) {
    final f = j['final'];
    return (f is String && f.trim().isNotEmpty)
        ? FinalOutput(f)
        : InvalidOutput('"final" must be non-empty text');
  }
  for (final k in const ['tool', 'args', 'reason']) {
    if (!j.containsKey(k)) return InvalidOutput('Missing field "$k"');
  }
  final tool = j['tool'];
  if (tool is! String) return InvalidOutput('"tool" must be text');
  final def = toolRegistry[tool];
  if (def == null) return InvalidOutput('Unknown tool "$tool"');
  final args = j['args'];
  if (args is! Map) return InvalidOutput('"args" must be an object');
  final reason = j['reason'];
  if (reason is! String || reason.trim().isEmpty) {
    return InvalidOutput('"reason" must be non-empty text');
  }
  final cleanArgs = args.map((k, v) => MapEntry(k.toString(), v));
  final err = def.validate(cleanArgs);
  if (err != null) return InvalidOutput('$tool: $err');
  return ProposalOutput(ToolCall(tool, cleanArgs, reason));
}
