import 'dart:isolate';

import 'package:vending_kiosk/presentation/print/isolate/model/has_send_port.dart';

class PreparePrintingMessage implements HasSendPort {
  @override
  SendPort sendPort;

  PreparePrintingMessage({
    required this.sendPort,
  });
}
