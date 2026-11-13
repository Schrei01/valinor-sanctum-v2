import 'package:flutter/material.dart';
import '../../debtors/domain/debtors_store.dart';
import '../../inventory/domain/inventory_store.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../quick_sales/domain/quick_sales_store.dart';
import '../../../core/domain/money.dart';
import '../domain/membership.dart';

const _birthMonths = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

String membershipDate(DateTime? day) => day == null
    ? '—'
    : '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';

String _voucherMoney(Membership m, int amount) => Money.fromMinorUnits(
  amount,
  currency: m.currencyCode,
  scale: m.moneyScale,
).formatEsCo(includeCurrency: true);

class MembershipBenefitsPanel extends StatelessWidget {
  const MembershipBenefitsPanel({super.key, required this.member});
  final Membership member;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc(),
        active = member.activeAt(DateTime.now().toUtc());
    final birthday = member.birthdayNoticeAt(now);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? const Color(0xffd9f0e1) : const Color(0xffffe5da),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (birthday != null) Text(birthday),
          Text(
            'Mensualidad Élfica · ${member.statusAt(now)}\n${membershipDate(member.starts)} al ${membershipDate(member.ends)}',
          ),
          Text('Acceso ${active ? 'ilimitado' : 'sin vigencia'}'),
          Text(
            'Bono disponible: ${_voucherMoney(member, active ? member.voucherRemainingMinor : 0)}\nRedimido: ${_voucherMoney(member, member.voucherUsedMinor)}',
          ),
        ],
      ),
    );
  }
}

class MembershipsPage extends StatefulWidget {
  const MembershipsPage({
    super.key,
    required this.store,
    required this.debtors,
    required this.sales,
    required this.onEnroll,
    this.onPeopleChanged,
  });
  final MembershipStore store;
  final DebtorsStore debtors;
  final QuickSalesStore sales;
  final Future<void> Function(String personId) onEnroll;
  final VoidCallback? onPeopleChanged;
  @override
  State<MembershipsPage> createState() => _MembershipsPageState();
}

class _MembershipsPageState extends State<MembershipsPage> {
  List<Membership> members = [];
  List<DebtorSummary> people = [];
  QuickSalesSnapshot? data;
  bool busy = false;
  String? error;
  String search = '';
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final m = await widget.store.load(),
          p = await widget.debtors.load(),
          s = await widget.sales.load();
      if (mounted) {
        setState(() {
          members = m;
          people = p.debtors;
          data = s;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Membership? member]) async {
    final name = TextEditingController(text: member?.name ?? ''),
        email = TextEditingController(text: member?.email ?? ''),
        day = TextEditingController(text: member?.birthDay?.toString() ?? '');
    int? birthMonth = member?.birthMonth;
    String? personId = member?.personId, dialogError;
    bool saving = false;
    final form = GlobalKey<FormState>();
    final commandId = InventoryIds.next();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            member == null ? 'Registrar persona' : 'Datos de la persona',
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (member == null) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Persona ya registrada (opcional)',
                        ),
                        items: [
                          for (final p in people.where((p) => p.isActive))
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: saving
                            ? null
                            : (id) {
                                update(() {
                                  personId = id;
                                  name.text = people
                                      .singleWhere((p) => p.id == id)
                                      .name;
                                  final saved = members
                                      .where((m) => m.personId == id)
                                      .firstOrNull;
                                  email.text = saved?.email ?? '';
                                  day.text = saved?.birthDay?.toString() ?? '';
                                  birthMonth = saved?.birthMonth;
                                });
                              },
                      ),
                      const SizedBox(height: 24),
                    ],
                    TextFormField(
                      controller: name,
                      enabled: personId == null && !saving,
                      maxLength: 120,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Escribe el nombre' : null,
                    ),
                    TextFormField(
                      controller: email,
                      enabled: !saving,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico (opcional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: day,
                            enabled: !saving,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Día de nacimiento',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('membership-birth-month-$personId'),
                            initialValue: birthMonth ?? 0,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Mes de nacimiento',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 0,
                                child: Text('Sin especificar'),
                              ),
                              for (var i = 0; i < _birthMonths.length; i++)
                                DropdownMenuItem(
                                  value: i + 1,
                                  child: Text(_birthMonths[i]),
                                ),
                            ],
                            onChanged: saving
                                ? null
                                : (value) => update(() {
                                    birthMonth = value == 0 ? null : value;
                                  }),
                          ),
                        ),
                      ],
                    ),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      if (day.text.isNotEmpty &&
                          int.tryParse(day.text) == null) {
                        update(() => dialogError = 'Revisa el día y mes.');
                        return;
                      }
                      update(() => saving = true);
                      try {
                        await widget.store.savePerson(
                          commandId: commandId,
                          personId: personId,
                          name: name.text,
                          email: email.text,
                          birthDay: int.tryParse(day.text),
                          birthMonth: birthMonth,
                        );
                        if (context.mounted) {
                          widget.onPeopleChanged?.call();
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          update(() {
                            dialogError = '$e';
                            saving = false;
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Guardando…' : 'Guardar datos'),
            ),
          ],
        ),
      ),
    );
    // Dialog route animations may still reference these controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    email.dispose();
    day.dispose();
    if (mounted) await reload();
  }

  Future<void> history(Membership member) async {
    final rows = await widget.store.history(member.personId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Historial · ${member.name}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rows.isEmpty) const Text('Sin inscripciones confirmadas.'),
                for (final r in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.name),
                    subtitle: Text(r.detail),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Membresías', style: Theme.of(context).textTheme.headlineMedium),
          FilledButton.icon(
            onPressed: busy ? null : edit,
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Registrar persona'),
          ),
          IconButton(
            onPressed: busy ? null : reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar membresías',
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Mensualidad Élfica · COP 109.000 · Un mes calendario\nAcceso ilimitado, Bono de COP 30.000 para consumir en tienda durante el período.',
      ),
      if (error != null) InventoryNotice(text: error!),
      const SizedBox(height: 16),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Buscar persona',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
      ),
      if (busy) const LinearProgressIndicator(),
      if (!busy && members.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Registra una persona y pulsa Inscribir para cobrar su mensualidad desde Ventas.',
          ),
        ),
      for (final m in members.where(
        (m) => m.name.toLowerCase().contains(search),
      ))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  [
                    if (m.email.isNotEmpty) m.email,
                    if (m.birthDay != null)
                      'Cumpleaños: ${m.birthDay}/${m.birthMonth}',
                  ].join(' · '),
                ),
                MembershipBenefitsPanel(member: m),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                await widget.onEnroll(m.personId);
                              } catch (e) {
                                if (mounted) setState(() => error = '$e');
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      child: Text(
                        m.periodId == null
                            ? 'Inscribir en Ventas'
                            : 'Renovar en Ventas',
                      ),
                    ),
                    TextButton(
                      onPressed: () => edit(m),
                      child: const Text('Editar datos'),
                    ),
                    TextButton(
                      onPressed: () => history(m),
                      child: const Text('Historial'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
