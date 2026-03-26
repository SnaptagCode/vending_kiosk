import 'package:json_annotation/json_annotation.dart';

enum VendingPrintJobType {
  @JsonValue('ARBITRARY')
  arbitrary,
  @JsonValue('REPRINT')
  reprint,
}
