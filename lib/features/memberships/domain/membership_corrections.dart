import 'membership.dart';

class CorrectMembershipPerson {
  const CorrectMembershipPerson({
    required this.commandId,
    required this.expected,
    required this.name,
    required this.email,
    this.birthDay,
    this.birthMonth,
    this.start,
  });
  final String commandId, name, email;
  final Membership expected;
  final int? birthDay, birthMonth;
  final DateTime? start;
}

abstract interface class MembershipCorrectionsStore {
  Future<void> correctPerson(CorrectMembershipPerson command);
}
