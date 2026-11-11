import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One immutable audit record, chained to the previous one by hash.
class AuditEntry {
  const AuditEntry(this.seq, this.time, this.runId, this.type, this.details, this.prevHash, this.hash);

  factory AuditEntry.create(int seq, DateTime time, String runId, String type,
      Map<String, dynamic> details, String prevHash) {
    final d = Map<String, dynamic>.from(jsonDecode(jsonEncode(details)) as Map);
    return AuditEntry(seq, time, runId, type, d, prevHash, computeHash(seq, time, runId, type, d, prevHash));
  }

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
      j['seq'], DateTime.parse(j['time']), j['runId'], j['type'],
      Map<String, dynamic>.from(j['details']), j['prevHash'], j['hash']);

  final int seq;
  final DateTime time;
  final String runId, type, prevHash, hash;
  final Map<String, dynamic> details;

  static String computeHash(int seq, DateTime t, String runId, String type,
          Map<String, dynamic> details, String prev) =>
      sha256
          .convert(utf8.encode('$seq|${t.toIso8601String()}|$runId|$type|${jsonEncode(details)}|$prev'))
          .toString();

  bool get intact => hash == computeHash(seq, time, runId, type, details, prevHash);

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'time': time.toIso8601String(),
        'runId': runId,
        'type': type,
        'details': details,
        'prevHash': prevHash,
        'hash': hash,
      };
}

/// Append-only. No public API edits or removes entries; [entries] is an
/// unmodifiable view; [verify] detects tampering of persisted data.
class AuditLog {
  AuditLog([List<AuditEntry>? entries]) : _e = entries ?? [];
  factory AuditLog.fromJson(List<dynamic> j) =>
      AuditLog(j.map((e) => AuditEntry.fromJson(Map<String, dynamic>.from(e))).toList());

  final List<AuditEntry> _e;
  List<AuditEntry> get entries => List.unmodifiable(_e);

  AuditEntry append(DateTime t, String runId, String type, Map<String, dynamic> details) {
    final prev = _e.isEmpty ? 'GENESIS' : _e.last.hash;
    final entry = AuditEntry.create(_e.length + 1, t, runId, type, details, prev);
    _e.add(entry);
    return entry;
  }

  bool verify() {
    var prev = 'GENESIS';
    for (final e in _e) {
      if (e.prevHash != prev || !e.intact) return false;
      prev = e.hash;
    }
    return true;
  }

  List<Map<String, dynamic>> toJson() => _e.map((e) => e.toJson()).toList();
  String toJsonString() => const JsonEncoder.withIndent('  ')
      .convert({'chainVerified': verify(), 'entries': toJson()});
}
