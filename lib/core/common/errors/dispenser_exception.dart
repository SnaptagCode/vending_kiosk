/// 카드 배출기 관련 예외
class DispenserException implements Exception {
  final String message;

  const DispenserException(this.message);

  @override
  String toString() => message;
}
