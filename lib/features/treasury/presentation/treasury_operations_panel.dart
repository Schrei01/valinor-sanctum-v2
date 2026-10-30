import '../../../core/presentation/grouped_number_formatter.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../inventory/presentation/inventory_widgets.dart';
import '../../workspace/domain/business_profile.dart';
import '../application/treasury_operation_controller.dart';
import '../domain/treasury_operation_store.dart';
import '../domain/treasury_store.dart';

class TreasuryOperationsPanel extends StatefulWidget {
  const TreasuryOperationsPanel({
    super.key,
    required this.controller,
    required this.profile,
    this.onConfirmed,
  });

  final TreasuryOperationController controller;
  final BusinessProfile profile;
  final VoidCallback? onConfirmed;

  @override
  State<TreasuryOperationsPanel> createState() =>
      _TreasuryOperationsPanelState();
}

class _TreasuryOperationsPanelState extends State<TreasuryOperationsPanel> {
  late int _confirmedVersion;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _confirmedVersion = widget.controller.confirmedVersion;
    widget.controller.addListener(_changed);
    if (widget.controller.snapshot == null && !widget.controller.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.controller.load());
      });
    }
  }

  @override
  void didUpdateWidget(covariant TreasuryOperationsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _listen();
    }
  }

  void _changed() {
    if (widget.controller.confirmedVersion == _confirmedVersion) return;
    _confirmedVersion = widget.controller.confirmedVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onConfirmed?.call();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _open(
    TreasuryOperationKind kind, {
    TreasuryOperationCommand? correction,
  }) async {
    if (widget.controller.formLocked || widget.controller.loadError != null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _OperationDialog(
        controller: widget.controller,
        profile: widget.profile,
        kind: kind,
        correction: correction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final accounts =
          controller.snapshot?.accounts ?? const <TreasuryAccount>[];
      final enabled = !controller.formLocked && controller.loadError == null;
      return Column(
        key: const Key('treasury-operations'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                key: const Key('treasury-register-expense'),
                onPressed:
                    enabled &&
                        accounts.any(
                          (account) =>
                              account.role == TreasuryAccountRole.cash ||
                              account.role == TreasuryAccountRole.nequi,
                        )
                    ? () => _open(TreasuryOperationKind.expense)
                    : null,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Registrar gasto'),
              ),
              OutlinedButton.icon(
                key: const Key('treasury-transfer'),
                onPressed: enabled && accounts.length >= 2
                    ? () => _open(TreasuryOperationKind.transfer)
                    : null,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transferir dinero'),
              ),
              OutlinedButton.icon(
                key: const Key('treasury-investment-refund'),
                onPressed:
                    enabled &&
                        (controller.snapshot?.investmentMinor ?? 0) > 0 &&
                        accounts.any(
                          (a) =>
                              a.role == TreasuryAccountRole.cash ||
                              a.role == TreasuryAccountRole.nequi,
                        )
                    ? () => _open(TreasuryOperationKind.investmentRefund)
                    : null,
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('Registrar devolución'),
              ),
              if (controller.loading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (controller.loadError != null) ...[
            const SizedBox(height: 12),
            InventoryNotice(
              key: const Key('treasury-operation-load-error'),
              text: controller.loadError!,
              onRetry: controller.busy ? null : controller.load,
            ),
          ],
          if (controller.operationNotice != null) ...[
            const SizedBox(height: 12),
            InventoryNotice(
              key: const Key('treasury-operation-notice'),
              text: controller.operationNotice!,
              kind: InventoryNoticeKind.information,
            ),
          ],
          if (controller.operationError != null) ...[
            const SizedBox(height: 12),
            InventoryNotice(
              key: const Key('treasury-operation-error'),
              text: controller.operationError!,
            ),
          ],
          for (final pending in controller.pendingOperations) ...[
            const SizedBox(height: 12),
            Card(
              key: ValueKey('treasury-pending-${pending.command.commandId}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending.command.kind == TreasuryOperationKind.expense
                          ? 'Gasto pendiente de confirmar'
                          : pending.command.kind ==
                                TreasuryOperationKind.investmentRefund
                          ? 'Devolución de inversión pendiente'
                          : 'Transferencia pendiente de confirmar',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${pending.sourceAccountName}'
                      '${pending.destinationAccountName == null ? '' : ' → ${pending.destinationAccountName}'} · '
                      '${inventoryMoney(pending.command.amountMinor, widget.profile)}',
                    ),
                    Text(pending.command.reason),
                    if (pending.command.note != null)
                      Text(pending.command.note!),
                    if (pending.rejectionReason != null)
                      Text(pending.rejectionReason!),
                    const SizedBox(height: 8),
                    if (pending.status == 'rejected')
                      OutlinedButton(
                        onPressed: controller.busy
                            ? null
                            : () async {
                                final corrected = await controller
                                    .discardRejected(pending.command.commandId);
                                if (corrected && mounted) {
                                  await _open(
                                    pending.command.kind,
                                    correction: pending.command,
                                  );
                                }
                              },
                        child: const Text('Corregir'),
                      )
                    else
                      FilledButton(
                        onPressed: controller.busy
                            ? null
                            : () => controller.retry(pending.command.commandId),
                        child: const Text('Reintentar'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _OperationDialog extends StatefulWidget {
  const _OperationDialog({
    required this.controller,
    required this.profile,
    required this.kind,
    this.correction,
  });

  final TreasuryOperationController controller;
  final BusinessProfile profile;
  final TreasuryOperationKind kind;
  final TreasuryOperationCommand? correction;

  @override
  State<_OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<_OperationDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _sourceId;
  String? _destinationId;
  String _reason = 'Arriendo';

  bool get _expense => widget.kind == TreasuryOperationKind.expense;
  bool get _refund => widget.kind == TreasuryOperationKind.investmentRefund;
  bool get _transfer => widget.kind == TreasuryOperationKind.transfer;

  List<TreasuryAccount> get _accounts =>
      widget.controller.snapshot?.accounts ?? const [];

  @override
  void initState() {
    super.initState();
    final command = widget.correction;
    final sources = _accounts.where(
      (account) =>
          _transfer ||
          account.role == TreasuryAccountRole.cash ||
          account.role == TreasuryAccountRole.nequi,
    );
    _sourceId = command?.sourceAccountId ?? sources.firstOrNull?.id;
    _destinationId = command?.destinationAccountId;
    if (command != null) {
      _amount.text = Money.fromMinorUnits(
        command.amountMinor,
        currency: widget.profile.currencyCode,
        scale: widget.profile.moneyScale,
      ).formatEsCo(groupThousands: false);
      _note.text = command.note ?? '';
      if (_expense) _reason = command.reason;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int _parseAmount() => Money.parseEsCo(
    _amount.text,
    currency: widget.profile.currencyCode,
    scale: widget.profile.moneyScale,
  ).minorUnits;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final confirmed = await widget.controller.record(
      kind: widget.kind,
      sourceAccountId: _sourceId!,
      destinationAccountId: _transfer ? _destinationId : null,
      amountMinor: _parseAmount(),
      reason: _expense
          ? _reason
          : _refund
          ? 'Devolución de inversión'
          : 'Transferencia',
      note: _note.text,
    );
    if (confirmed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final sources = _accounts
          .where(
            (account) =>
                _transfer ||
                account.role == TreasuryAccountRole.cash ||
                account.role == TreasuryAccountRole.nequi,
          )
          .toList();
      final source = sources
          .where((account) => account.id == _sourceId)
          .firstOrNull;
      final destinations = _accounts
          .where((account) => account.id != _sourceId)
          .toList();
      final destinationId =
          destinations.any((account) => account.id == _destinationId)
          ? _destinationId
          : null;
      final locked = controller.formLocked;
      return AlertDialog(
        title: Text(
          _expense
              ? 'Registrar gasto'
              : _refund
              ? 'Devolver inversión'
              : 'Transferir dinero',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('treasury-operation-source'),
                    initialValue: source?.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: !_transfer
                          ? 'Pagar desde'
                          : 'Cuenta de origen',
                    ),
                    items: [
                      for (final account in sources)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: locked
                        ? null
                        : (value) => setState(() {
                            _sourceId = value;
                            if (_destinationId == value) _destinationId = null;
                          }),
                    validator: (_) =>
                        source == null ? 'Elige una cuenta.' : null,
                  ),
                  if (source != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Saldo disponible: ${inventoryMoney(source.balanceMinor, widget.profile)}',
                      key: const Key('treasury-operation-balance'),
                    ),
                  ],
                  if (_refund) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Inversión por recuperar: ${inventoryMoney(controller.snapshot?.investmentMinor ?? 0, widget.profile)}',
                      key: const Key('treasury-refund-outstanding'),
                    ),
                  ],
                  if (_transfer) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      key: const Key('treasury-operation-destination'),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('destination-$_sourceId-$destinationId'),
                        initialValue: destinationId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Cuenta de destino',
                        ),
                        items: [
                          for (final account in destinations)
                            DropdownMenuItem(
                              value: account.id,
                              child: Text(account.name),
                            ),
                        ],
                        onChanged: locked
                            ? null
                            : (value) => setState(() => _destinationId = value),
                        validator: (_) => destinationId == null
                            ? 'Elige una cuenta de destino distinta.'
                            : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('treasury-operation-amount'),
                    controller: _amount,
                    inputFormatters: [const GroupedNumberFormatter()],
                    enabled: !locked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Valor',
                      prefixText: '${widget.profile.currencyCode} ',
                    ),
                    validator: (_) {
                      try {
                        final value = _parseAmount();
                        if (value <= 0) {
                          return 'Escribe un valor mayor que cero.';
                        }
                        if (source != null && value > source.balanceMinor) {
                          return 'El saldo de ${source.name} no alcanza.';
                        }
                        if (_refund &&
                            value >
                                (controller.snapshot?.investmentMinor ?? 0)) {
                          return 'Supera la inversión pendiente.';
                        }
                        return null;
                      } catch (_) {
                        return 'Escribe un valor válido, con coma decimal.';
                      }
                    },
                  ),
                  if (_expense) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('treasury-operation-reason'),
                      initialValue: _reason,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Motivo'),
                      items: [
                        for (final reason in const [
                          'Arriendo',
                          'Aseo',
                          'Servicios',
                          'Otro',
                        ])
                          DropdownMenuItem(value: reason, child: Text(reason)),
                      ],
                      onChanged: locked
                          ? null
                          : (value) => setState(() => _reason = value!),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('treasury-operation-note'),
                    controller: _note,
                    enabled: !locked,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Observación (opcional)',
                    ),
                  ),
                  if (controller.operationError != null)
                    Text(
                      controller.operationError!,
                      key: const Key('treasury-dialog-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (locked && controller.pendingOperations.isNotEmpty)
                    const Text(
                      'Esta solicitud se conserva. Cierra este formulario para reintentar o corregir desde Tesorería.',
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: controller.confirming
                ? null
                : () => Navigator.of(context).pop(),
            child: Text(locked ? 'Cerrar' : 'Cancelar'),
          ),
          FilledButton(
            key: const Key('treasury-operation-submit'),
            onPressed: locked || controller.loadError != null ? null : _submit,
            child: Text(
              _expense
                  ? 'Registrar gasto'
                  : _refund
                  ? 'Registrar devolución'
                  : 'Transferir',
            ),
          ),
        ],
      );
    },
  );
}
