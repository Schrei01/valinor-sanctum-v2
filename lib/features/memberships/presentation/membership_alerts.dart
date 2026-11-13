import 'package:flutter/material.dart';
import '../domain/membership.dart';

class MembershipAlerts extends StatelessWidget {
  const MembershipAlerts({
    super.key,
    required this.members,
    required this.now,
    required this.onOpen,
  });
  final List<Membership> members;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final expiring = members
        .where(
          (m) =>
              m.ends != null &&
              !m.ends!.isAfter(membershipDay(now).add(const Duration(days: 3))),
        )
        .toList();
    final birthdays =
        members.where((m) => m.birthdayNoticeAt(now) != null).toList()
          ..sort((a, b) {
            final days = a
                .daysUntilBirthday(now)!
                .compareTo(b.daysUntilBirthday(now)!);
            return days != 0
                ? days
                : a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    Widget banner(String key, String title, IconData icon, Color color) =>
        Material(
          key: ValueKey(key),
          color: color,
          child: ListTile(
            dense: true,
            leading: Icon(icon),
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpen,
          ),
        );
    String extra(int count) => count > 3 ? '; y ${count - 3} más' : '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (expiring.isNotEmpty)
          banner(
            'membership-expiry-alert',
            'Membresías: ${expiring.take(3).map((m) => '${m.name} · ${m.statusAt(now)}').join('; ')}${extra(expiring.length)}',
            Icons.card_membership_outlined,
            const Color(0xffffe6b8),
          ),
        if (birthdays.isNotEmpty)
          banner(
            'membership-birthday-alert',
            'Cumpleaños: ${birthdays.take(3).map((m) => '${m.name} · ${m.birthdayNoticeAt(now)}').join('; ')}${extra(birthdays.length)}',
            Icons.cake_outlined,
            const Color(0xffd9f0e1),
          ),
      ],
    );
  }
}
