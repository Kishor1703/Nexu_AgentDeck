import 'models.dart';

/// What the runtime requires before a tool call may execute.
class Policy {
  const Policy({
    required this.needsApproval,
    required this.needsPin,
    required this.warning,
    required this.delaySeconds,
  });
  final bool needsApproval;
  final bool needsPin;
  final bool warning; // proposed right after untrusted tool output (A7)
  final int delaySeconds;
}

/// A1 + A7. [tainted] = the step was proposed right after an untrusted result.
Policy policyFor(Permission p, {required bool tainted}) => switch (p) {
      Permission.safe => Policy(needsApproval: false, needsPin: false, warning: tainted, delaySeconds: 0),
      Permission.write => Policy(needsApproval: true, needsPin: tainted, warning: tainted, delaySeconds: 0),
      Permission.danger => Policy(needsApproval: true, needsPin: true, warning: tainted, delaySeconds: 5),
    };
