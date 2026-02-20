class ErrorLogEntry {
  final DateTime timestamp;
  final String type;
  final String message;
  final String? errorCode;

  ErrorLogEntry({
    required this.timestamp,
    required this.type,
    required this.message,
    this.errorCode,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }
}
