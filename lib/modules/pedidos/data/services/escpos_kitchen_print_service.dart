import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../domain/entities/kitchen_printer_config.dart';
import '../../domain/entities/operational_order.dart';
import '../../domain/entities/order_ticket_document.dart';
import '../../domain/services/kitchen_print_service.dart';

class EscPosKitchenPrintService implements KitchenPrintService {
  const EscPosKitchenPrintService();

  @override
  Future<void> print({
    required KitchenPrinterConfig printer,
    required OrderTicketDocument ticket,
  }) async {
    switch (printer.connectionType) {
      case KitchenPrinterConnectionType.network:
        await _printOverNetwork(printer: printer, ticket: ticket);
      case KitchenPrinterConnectionType.bluetooth:
        throw const ValidationException(
          'Bluetooth termico ainda nao esta disponivel nesta versao. Use uma impressora ESC/POS em rede.',
        );
    }
  }

  Future<void> _printOverNetwork({
    required KitchenPrinterConfig printer,
    required OrderTicketDocument ticket,
  }) async {
    final host = printer.host?.trim();
    if (host == null || host.isEmpty) {
      throw const ValidationException(
        'Configure o IP da impressora de cozinha antes de imprimir.',
      );
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        printer.port,
        timeout: const Duration(seconds: 5),
      );
      socket.add(
        _buildBytes(
          ticket: ticket,
          charactersPerLine: printer.charactersPerLine,
        ),
      );
      await socket.flush();
      await socket.close();
    } on SocketException catch (error) {
      throw ValidationException(
        'Nao foi possivel conectar na impressora ${printer.displayName}. Verifique IP, porta e rede.',
        cause: error,
      );
    } on TimeoutException catch (error) {
      throw ValidationException(
        'A conexao com a impressora demorou demais. Confira se ela esta ligada e acessivel na rede.',
        cause: error,
      );
    } catch (error) {
      throw ValidationException(
        'Falha ao enviar o ticket para a impressora termica.',
        cause: error,
      );
    } finally {
      await socket?.close();
    }
  }

  List<int> _buildBytes({
    required OrderTicketDocument ticket,
    required int charactersPerLine,
  }) {
    final writer = _EscPosWriter(charactersPerLine: charactersPerLine);
    writer.initialize();
    writer.center();
    if (ticket.businessName?.trim().isNotEmpty == true) {
      writer.bold(true);
      writer.text(ticket.businessName!.trim());
      writer.bold(false);
    }
    writer.text(ticket.title);
    writer.feed();
    writer.doubleSize();
    writer.text('Pedido #${ticket.orderId}');
    writer.normalSize();
    writer.text(_statusLabel(ticket.status));
    writer.text(AppFormatters.shortDateTime(ticket.updatedAt));
    writer.separator();
    writer.left();

    for (final line in ticket.lines) {
      writer.bold(true);
      writer.doubleSize();
      writer.text(
        '${AppFormatters.quantityFromMil(line.quantityMil)}x ${line.productName}',
      );
      writer.normalSize();
      writer.bold(false);

      for (final modifier in line.modifiers) {
        final modifierLabel = [
          if (modifier.groupName?.trim().isNotEmpty ?? false)
            '${modifier.groupName}:',
          modifier.optionName,
        ].join(' ');
        writer.indented(modifierLabel);
      }

      if (line.notes?.trim().isNotEmpty ?? false) {
        writer.indented('OBS: ${line.notes!.trim()}');
      }

      writer.separator();
    }

    if (ticket.orderNotes?.trim().isNotEmpty ?? false) {
      writer.bold(true);
      writer.text('OBS GERAL');
      writer.bold(false);
      writer.text(ticket.orderNotes!.trim());
      writer.separator();
    }

    writer.text('Itens: ${ticket.totalUnits}');
    for (final footerLine in ticket.footerLines) {
      writer.feed();
      writer.text(footerLine);
    }
    writer.feed(lines: 4);
    writer.cut();
    return writer.bytes;
  }

  String _statusLabel(OperationalOrderStatus status) {
    switch (status) {
      case OperationalOrderStatus.draft:
        return 'Rascunho';
      case OperationalOrderStatus.open:
        return 'Aberto';
      case OperationalOrderStatus.inPreparation:
        return 'Em preparo';
      case OperationalOrderStatus.ready:
        return 'Pronto';
      case OperationalOrderStatus.delivered:
        return 'Entregue';
      case OperationalOrderStatus.canceled:
        return 'Cancelado';
    }
  }
}

class _EscPosWriter {
  _EscPosWriter({required this.charactersPerLine});

  final int charactersPerLine;
  final List<int> bytes = <int>[];

  void initialize() => bytes.addAll(const <int>[0x1B, 0x40]);

  void left() => bytes.addAll(const <int>[0x1B, 0x61, 0x00]);

  void center() => bytes.addAll(const <int>[0x1B, 0x61, 0x01]);

  void bold(bool enabled) =>
      bytes.addAll(<int>[0x1B, 0x45, enabled ? 0x01 : 0x00]);

  void normalSize() => bytes.addAll(const <int>[0x1D, 0x21, 0x00]);

  void doubleSize() => bytes.addAll(const <int>[0x1D, 0x21, 0x11]);

  void feed({int lines = 1}) {
    for (var index = 0; index < lines; index++) {
      bytes.add(0x0A);
    }
  }

  void separator() => text('-' * charactersPerLine);

  void indented(String value) {
    for (final line in _wrap('  $value')) {
      text(line);
    }
  }

  void text(String value) {
    for (final line in _wrap(value)) {
      bytes.addAll(latin1.encode(_normalize(line)));
      bytes.add(0x0A);
    }
  }

  void cut() => bytes.addAll(const <int>[0x1D, 0x56, 0x42, 0x00]);

  List<String> _wrap(String value) {
    final normalized = value.trimRight();
    if (normalized.isEmpty) {
      return const <String>[''];
    }

    final words = normalized.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= charactersPerLine) {
        current = candidate;
        continue;
      }

      if (current.isNotEmpty) {
        lines.add(current);
      }

      if (word.length <= charactersPerLine) {
        current = word;
        continue;
      }

      var remaining = word;
      while (remaining.length > charactersPerLine) {
        lines.add(remaining.substring(0, charactersPerLine));
        remaining = remaining.substring(charactersPerLine);
      }
      current = remaining;
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }
    return lines;
  }

  String _normalize(String value) {
    var normalized = value;
    normalized = normalized.replaceAll(
      RegExp('[\u00E1\u00E0\u00E3\u00E2\u00E4]'),
      'a',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00C1\u00C0\u00C3\u00C2\u00C4]'),
      'A',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00E9\u00E8\u00EA\u00EB]'),
      'e',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00C9\u00C8\u00CA\u00CB]'),
      'E',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00ED\u00EC\u00EE\u00EF]'),
      'i',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00CD\u00CC\u00CE\u00CF]'),
      'I',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00F3\u00F2\u00F5\u00F4\u00F6]'),
      'o',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00D3\u00D2\u00D5\u00D4\u00D6]'),
      'O',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00FA\u00F9\u00FB\u00FC]'),
      'u',
    );
    normalized = normalized.replaceAll(
      RegExp('[\u00DA\u00D9\u00DB\u00DC]'),
      'U',
    );
    normalized = normalized.replaceAll(RegExp('[\u00E7]'), 'c');
    normalized = normalized.replaceAll(RegExp('[\u00C7]'), 'C');
    return normalized;
  }
}
