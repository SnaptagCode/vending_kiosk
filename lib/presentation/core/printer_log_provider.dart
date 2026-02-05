import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vending_kiosk/presentation/print/state/printer_log.dart';

class PrinterLogNotifier extends Notifier<PrinterLog?> {
  @override
  PrinterLog? build() => null;

  void update(PrinterLog log) {
    state = log;
  }

  void clear() {
    state = null;
  }

  bool get hasLog => state != null;
}

final printerLogProvider = NotifierProvider<PrinterLogNotifier, PrinterLog?>(
  PrinterLogNotifier.new,
);
