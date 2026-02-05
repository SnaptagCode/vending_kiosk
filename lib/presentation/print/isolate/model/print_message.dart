import 'package:vending_kiosk/presentation/print/isolate/print_path.dart';

class PrintMessage {
  PrintImageBuffer printPath;
  bool isSingleMode;

  PrintMessage({
    required this.isSingleMode,
    required this.printPath,
  });
}
