part of 'sqlite_stock_intake_store.dart';

PreparedPurchaseBatch _preparedBatch(Map<String, Object?> row) {
  final payload =
      jsonDecode(row['canonical_payload'] as String) as Map<String, dynamic>;
  final at = DateTime.parse(row['occurred_at_utc'] as String).toUtc();
  return PreparedPurchaseBatch(
    command: PurchaseBatchCommand(
      commandId: row['command_id'] as String,
      categoryId: row['category_id'] as String,
      paymentOptionId: row['payment_option_id'] as String,
      totalPaidMinor: row['total_paid_minor'] as int,
      occurredAtUtc: at,
      items: [
        for (final line in payload['items'] as List)
          SqliteStockIntakeStore._prepared({
            'command_id': line['input']['commandId'],
            'canonical_payload': jsonEncode({'input': line['input']}),
            'occurred_at_utc': row['occurred_at_utc'],
            'prepared_at_utc': row['prepared_at_utc'],
            'status': 'prepared',
          }).command,
      ],
    ),
    status: row['status'] as String,
    preparedAtUtc: DateTime.parse(row['prepared_at_utc'] as String).toUtc(),
    rejectionReason: row['rejection_reason'] as String?,
  );
}

StockIntakeCommand _settlementCommand(StockIntakeCommand item, int cost) =>
    StockIntakeCommand(
      commandId: item.commandId,
      productId: item.productId,
      expectedProduct: item.expectedProduct,
      productName: item.productName,
      sku: item.sku,
      categoryId: item.categoryId,
      supplierId: item.supplierId,
      supplierName: item.supplierName,
      totalPurchasePriceMinor: cost,
      listPriceMinor: item.listPriceMinor,
      quantity: item.quantity,
      paymentOptionId: item.paymentOptionId,
      occurredAtUtc: item.occurredAtUtc,
    );

extension _BatchPersistence on SqliteStockIntakeStore {
  Map<String, Object?> _batchPayload(PurchaseBatchCommand command) {
    command.validate();
    SqliteStockIntakeStore._id(command.commandId);
    final costs = command.settlementCosts;
    return {
      'version': 1,
      'commandId': command.commandId,
      'categoryId': command.categoryId,
      'paymentOptionId': command.paymentOptionId,
      'totalPaidMinor': command.totalPaidMinor,
      'occurredAtUtc': command.occurredAtUtc.toIso8601String(),
      'items': [
        for (var index = 0; index < command.items.length; index++)
          {
            'input': SqliteStockIntakeStore._input(command.items[index]),
            'declaredCostMinor': command.items[index].totalCostMinor,
            'settlementCostMinor': costs[index],
          },
      ],
    };
  }

  Future<PreparedPurchaseBatch> _batchPrepare(
    PurchaseBatchCommand command,
  ) async {
    final payload = jsonEncode(_batchPayload(command));
    return _database.database.transaction((txn) async {
      final prior = await txn.query(
        'purchase_batch_requests',
        where: 'command_id=?',
        whereArgs: [command.commandId],
      );
      if (prior.isNotEmpty) {
        final saved =
            jsonDecode(prior.single['canonical_payload'] as String)
                as Map<String, dynamic>;
        saved.remove('profile');
        saved.remove('payment');
        if (jsonEncode(saved) != payload) {
          throw const StockIntakeValidationException(
            'El identificador corresponde a otra compra.',
          );
        }
        return _preparedBatch(prior.single);
      }
      await SqliteStockIntakeStore._unused(txn, command.commandId);
      for (final id in [
        command.commandId,
        ...command.items.map((item) => item.commandId),
      ]) {
        final reservations = await txn.rawQuery(
          'SELECT command_id FROM purchase_batch_requests WHERE command_id=? UNION ALL SELECT child_command_id FROM purchase_batch_items WHERE child_command_id=?',
          [id, id],
        );
        if (reservations.isNotEmpty) {
          throw const StockIntakeValidationException(
            'Un identificador ya pertenece a otra compra.',
          );
        }
      }
      final profile = await SqliteStockIntakeStore._profile(txn);
      final category = await SqliteStockIntakeStore._category(
        txn,
        command.categoryId,
      );
      final option = await SqliteStockIntakeStore._option(
        txn,
        command.paymentOptionId,
      );
      await SqliteStockIntakeStore._funds(
        txn,
        option,
        command.totalPaidMinor,
        command.occurredAtUtc,
      );
      for (final item in command.items) {
        await SqliteStockIntakeStore._unused(txn, item.commandId);
        await SqliteStockIntakeStore._checkProduct(
          txn,
          item.productId,
          SqliteStockIntakeStore._input(item)['expectedProduct']
              as Map<String, Object?>?,
          name: item.productName,
        );
        await SqliteStockIntakeStore._checkSku(txn, item.sku, item.productId);
      }
      final row = <String, Object?>{
        'command_id': command.commandId,
        'canonical_payload': payload,
        'category_id': command.categoryId,
        'category_name_snapshot': category['name'],
        'payment_option_id': command.paymentOptionId,
        'payment_label_snapshot': option['paymentOptionLabel'],
        'items_total_minor': command.itemsTotalMinor,
        'total_paid_minor': command.totalPaidMinor,
        'occurred_at_utc': command.occurredAtUtc.toIso8601String(),
        'prepared_at_utc': DateTime.now().toUtc().toIso8601String(),
        'status': 'prepared',
      };
      // Capture profile/payment identities in the canonical payload so a change
      // while pending cannot silently redirect the whole payment.
      final body = jsonDecode(payload) as Map<String, dynamic>;
      body['profile'] = {
        'id': profile.profileId,
        'currency': profile.currencyCode,
        'scale': profile.moneyScale,
      };
      body['payment'] = option;
      row['canonical_payload'] = jsonEncode(body);
      await txn.insert('purchase_batch_requests', row);
      final allocations = command.settlementCosts;
      for (var index = 0; index < command.items.length; index++) {
        await txn.insert('purchase_batch_items', {
          'batch_id': command.commandId,
          'sequence': index,
          'child_command_id': command.items[index].commandId,
          'declared_cost_minor': command.items[index].totalCostMinor,
          'settlement_cost_minor': allocations[index],
        });
      }
      return _preparedBatch(row);
    }, exclusive: true);
  }

  Future<void> _batchConfirm(String id) async {
    SqliteStockIntakeStore._id(id);
    try {
      await _database.database.transaction((txn) async {
        final rows = await txn.query(
          'purchase_batch_requests',
          where: 'command_id=?',
          whereArgs: [id],
        );
        if (rows.length != 1) {
          throw const StockIntakeValidationException(
            'No existe la compra pendiente.',
          );
        }
        final row = rows.single;
        if (row['status'] == 'confirmed') return;
        if (row['status'] != 'prepared') {
          throw const StockIntakeValidationException(
            'La compra debe corregirse antes de registrarla.',
          );
        }
        final command = _preparedBatch(row).command;
        final body =
            jsonDecode(row['canonical_payload'] as String)
                as Map<String, dynamic>;
        final savedInput = Map<String, dynamic>.from(body)
          ..remove('profile')
          ..remove('payment');
        if (jsonEncode(savedInput) != jsonEncode(_batchPayload(command))) {
          throw const StockIntakeValidationException(
            'La compra no coincide con la solicitud guardada.',
          );
        }
        final profile = await SqliteStockIntakeStore._profile(txn);
        if (jsonEncode(body['profile']) !=
            jsonEncode({
              'id': profile.profileId,
              'currency': profile.currencyCode,
              'scale': profile.moneyScale,
            })) {
          throw const StockIntakeValidationException(
            'Cambió la configuración de la compra.',
          );
        }
        final option = await SqliteStockIntakeStore._option(
          txn,
          command.paymentOptionId,
        );
        if (jsonEncode(body['payment']) != jsonEncode(option)) {
          throw const StockIntakeValidationException(
            'Cambió la cuenta de pago. Revisa la compra.',
          );
        }
        final category = await SqliteStockIntakeStore._category(
          txn,
          command.categoryId,
        );
        if (category['name'] != row['category_name_snapshot']) {
          throw const StockIntakeValidationException(
            'Cambió la categoría. Revisa la compra.',
          );
        }
        await SqliteStockIntakeStore._funds(
          txn,
          option,
          command.totalPaidMinor,
          command.occurredAtUtc,
        );
        final costs = command.settlementCosts;
        // All children share this exclusive transaction: no product, price,
        // stock, cash or investment effect survives if a later item fails.
        for (var index = 0; index < command.items.length; index++) {
          final child = _settlementCommand(command.items[index], costs[index]);
          await _prepareInTransaction(txn, child, batchId: id);
          await _confirm(txn, child.commandId);
        }
        await txn.update(
          'purchase_batch_requests',
          {'status': 'confirmed'},
          where: 'command_id=?',
          whereArgs: [id],
        );
      }, exclusive: true);
    } catch (error) {
      final message = switch (error) {
        StockIntakeValidationException e => e.message,
        InventoryValidationException e => e.message,
        SupplierPaymentsValidationException e => e.message,
        InvestmentValidationException e => e.message,
        _ => null,
      };
      if (message == null) rethrow;
      await _database.database.transaction((txn) async {
        await txn.update(
          'purchase_batch_requests',
          {'status': 'rejected', 'rejection_reason': message},
          where: "command_id=? AND status='prepared'",
          whereArgs: [id],
        );
      }, exclusive: true);
      throw StockIntakeValidationException(message);
    }
  }

  Future<void> _batchDiscard(String id) =>
      _database.database.transaction((txn) async {
        final rows = await txn.query(
          'purchase_batch_requests',
          where: 'command_id=?',
          whereArgs: [id],
        );
        if (rows.length == 1 && rows.single['status'] == 'discarded') return;
        if (rows.length != 1 || rows.single['status'] != 'rejected') {
          throw const StockIntakeValidationException(
            'Solo se puede corregir una compra rechazada.',
          );
        }
        await txn.update(
          'purchase_batch_requests',
          {'status': 'discarded'},
          where: 'command_id=?',
          whereArgs: [id],
        );
      }, exclusive: true);
}
