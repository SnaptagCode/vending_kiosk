class KioskLogRequest {
  final int? logId;
  final int machineId;
  final String title;
  final String content;

  KioskLogRequest({
    required this.machineId,
    required this.title,
    required this.content,
  }) : logId = null;

  KioskLogRequest.withLogId({
    required int this.logId,
    required this.machineId,
    required this.title,
    required this.content,
  });
}
