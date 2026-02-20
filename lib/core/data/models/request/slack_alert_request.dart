/// POST /v1/internal/slack-alert 요청 body
class SlackAlertRequest {
  final String type;
  final String message;

  const SlackAlertRequest({
    required this.type,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'message': message,
      };
}
