import 'package:vending_kiosk/presentation/print/state/printer_log.dart';

class PrintReply {
  PrinterLog? printerLog;
  String errorMsg = '';

  PrintReply({
    errorMsg = '',
    required this.printerLog,
  });
}
