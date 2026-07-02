import 'package:vending_kiosk/core/data/models/response/payment_response.dart';

/// KSCAT 환불(취소) 응답코드 → 한글 사유 매핑. 필요 시 줄만 추가/삭제하면 확장 가능.
const Map<String, String> kRefundReasonByCode = {
  '7001': '이미 취소된 거래',
  '7002': '이미 매입된 거래',
  '7003': '원거래 없음',
  '7803': '재조회 요망',
  '7978': '가맹점 해지',
  '7979': '가맹점 미등록/해지/거래정지',
  '8038': 'Data Format 오류',
  '8380': '카드사 장애 무응답/지연(timeout)',
  '8381': '전산장애(KSNET 문의)',
  '1000': '거래 취소됨(취소 버튼)',
  '1001': '전문 오류',
  '1003': '이전거래 미완료',
  '1004': '시간 초과',
  '1099': '기타 오류',
};

/// 환불 실패 시 노출할 한글 사유를 반환한다. 미매핑 코드는 코드번호로 노출한다.
String refundReasonFor(PaymentResponse? p) {
  if (p == null) return '확인필요';

  final respCode = p.respCode;
  if (respCode != null && kRefundReasonByCode.containsKey(respCode)) {
    return kRefundReasonByCode[respCode]!;
  }

  final res = p.res;
  if (kRefundReasonByCode.containsKey(res)) {
    return kRefundReasonByCode[res]!;
  }

  final code = (respCode != null && respCode.isNotEmpty) ? respCode : res;
  return '확인필요 (코드: $code)';
}
