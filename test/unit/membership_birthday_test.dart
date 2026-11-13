import 'package:flutter_test/flutter_test.dart';
import 'package:valinor_sanctum_2/features/memberships/domain/membership.dart';

Membership person(int? day, int? month) => Membership(
  personId: 'person',
  name: 'Persona',
  email: '',
  birthDay: day,
  birthMonth: month,
);

void main() {
  test(
    'birthday window includes seven days before and the day itself without a membership',
    () {
      final p = person(20, 11);
      expect(p.periodId, isNull);
      expect(p.birthdayNoticeAt(DateTime.utc(2026, 11, 12, 17)), isNull);
      expect(
        p.birthdayNoticeAt(DateTime.utc(2026, 11, 13, 17)),
        'Cumpleaños en 7 días',
      );
      expect(
        p.birthdayNoticeAt(DateTime.utc(2026, 11, 19, 17)),
        'Cumpleaños mañana',
      );
      expect(
        p.birthdayNoticeAt(DateTime.utc(2026, 11, 20, 17)),
        'Cumpleaños hoy',
      );
      expect(p.birthdayNoticeAt(DateTime.utc(2026, 11, 21, 17)), isNull);
    },
  );
  test('next birthday crosses December and respects Bogota midnight', () {
    final p = person(4, 1);
    expect(p.daysUntilBirthday(DateTime.utc(2026, 12, 28, 4, 59)), 8);
    expect(p.daysUntilBirthday(DateTime.utc(2026, 12, 28, 5)), 7);
    expect(p.birthdayNoticeAt(DateTime.utc(2027, 1, 4, 5)), 'Cumpleaños hoy');
  });
  test('February 29 is observed on February 28 outside leap years', () {
    final p = person(29, 2);
    expect(p.daysUntilBirthday(DateTime.utc(2027, 2, 21, 17)), 7);
    expect(p.birthdayNoticeAt(DateTime.utc(2027, 2, 28, 17)), 'Cumpleaños hoy');
    expect(p.daysUntilBirthday(DateTime.utc(2028, 2, 28, 17)), 1);
    expect(p.birthdayNoticeAt(DateTime.utc(2028, 2, 29, 17)), 'Cumpleaños hoy');
  });
  test('missing and invalid birthdays do not produce alerts', () {
    for (final p in [
      person(null, null),
      person(3, null),
      person(null, 3),
      person(31, 4),
      person(0, 1),
      person(1, 13),
    ]) {
      expect(p.birthdayNoticeAt(DateTime.utc(2026, 11, 13, 17)), isNull);
    }
  });
}
