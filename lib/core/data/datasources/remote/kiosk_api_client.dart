import 'package:dio/dio.dart';
import 'package:vending_kiosk/core/data/models/response/alert_definition_response.dart';
import 'package:vending_kiosk/core/data/models/response/back_photo_card_response.dart';
import 'package:vending_kiosk/core/data/models/response/back_photo_status_response.dart';
import 'package:vending_kiosk/core/data/models/response/create_order_response.dart';
import 'package:vending_kiosk/core/data/models/response/create_print_response.dart';
import 'package:vending_kiosk/core/data/models/response/kiosk_machine_info.dart';
import 'package:vending_kiosk/core/data/models/response/nominated_photo_list.dart';
import 'package:vending_kiosk/core/data/models/response/order_list_response.dart';
import 'package:vending_kiosk/core/data/models/response/update_order_response.dart';
import 'package:vending_kiosk/core/data/models/response/update_print_response.dart';
import 'package:vending_kiosk/core/data/models/response/card_stock_consume_response.dart';
import 'package:vending_kiosk/core/data/models/response/card_stock_recharge_response.dart';
import 'package:vending_kiosk/core/data/models/response/machine_card_stock_response.dart';
import 'package:vending_kiosk/core/data/models/response/machine_maintenance_response.dart';
import 'package:vending_kiosk/core/data/models/response/create_vending_order_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_order_status_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_status_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_list_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_reprint_response.dart';
import 'package:retrofit/retrofit.dart';

part 'kiosk_api_client.g.dart';

@RestApi()
abstract class KioskApiClient {
  factory KioskApiClient(Dio dio, {String baseUrl}) = _KioskApiClient;

  // Health Check
  @GET('/v1/health-check')
  Future<String> healthCheck();

  @GET('/v1/kiosk-event/front-photo-list')
  Future<NominatedPhotoList> getFrontPhotoList({
    @Query('kioskEventId') required int kioskEventId,
  });

  @GET('/v1/machine/info/vending')
  Future<KioskMachineInfo> getKioskMachineInfoByKey({
    @Query('machineId') int? machineId,
    @Query('uniqueKey') String? uniqueKey,
  });

  @GET('/v1/machine/maintenance')
  Future<MachineMaintenanceResponse> getMachineMaintenance({
    @Query('machineId') required int machineId,
    @Query('uniqueKey') required String uniqueKey,
  });

  @GET('/v1/machine/card-stock')
  Future<MachineCardStockResponse> getMachineCardStock({
    @Query('machineId') required int machineId,
    @Query('uniqueKey') String? uniqueKey,
  });

  @POST('/v1/machine/card-stock/consume')
  Future<CardStockConsumeResponse> consumeCardStock({
    @Body() required Map<String, dynamic> body,
  });

  @POST('/v1/machine/card-stock/recharge')
  Future<CardStockRechargeResponse> rechargeCardStock({
    @Body() required Map<String, dynamic> body,
  });

  @GET('/v1/kiosk-event/back-photo')
  Future<BackPhotoCardResponse> getBackPhotoCard({
    @Query('kioskEventId') required int kioskEventId,
    @Query('photoAuthNumber') required String photoAuthNumber,
  });

  @POST('/v1/kiosk-event/update-back-photo-status')
  Future<BackPhotoStatusResponse> updateBackPhotoStatus({
    @Body() required Map<String, dynamic> body,
  });

  @GET('/v1/order/list')
  Future<OrderListResponse> getOrders({
    @Query('pageSize') required int pageSize,
    @Query('currentPage') required int currentPage,
    @Query('kioskMachineId') int? kioskMachineId,
  });

  @POST('/v1/order')
  Future<CreateOrderResponse> createOrder({
    @Body() required Map<String, dynamic> body,
  });

  @PATCH('/v1/order/{orderId}')
  Future<UpdateOrderResponse> updateOrder({
    @Path('orderId') required int orderId,
    @Body() required Map<String, dynamic> body,
  });

  @POST('/v1/print')
  Future<CreatePrintResponse> createPrint({
    @Body() required Map<String, dynamic> body,
  });

  @PATCH('/v1/print/{printedPhotoCardId}')
  Future<UpdatePrintResponse> updatePrint({
    @Path('printedPhotoCardId') required int printedPhotoCardId,
    @Body() required Map<String, dynamic> body,
  });

  @POST('/v1/machine/log')
  Future<void> updatePrintLog({
    @Body() required Map<String, dynamic> body,
  });

  @GET('/v1/error-code')
  Future<List<AlertDefinitionResponse>> getAlertDefinitions();

  @POST('/v1/internal/slack/kiosk-by-type')
  Future<void> sendSlackAlert(@Body() Map<String, dynamic> body);

  @POST('/v1/internal/event/{kioskEventId}/machine/{machineId}/end')
  Future<void> endKioskApplication({
    @Path('kioskEventId') required int kioskEventId,
    @Path('machineId') required int machineId,
  });

  @DELETE('/v1/internal/event/{kioskEventId}/machine/{machineId}/end')
  Future<void> deleteEndMark(
      {@Path('kioskEventId') required int kioskEventId,
      @Path('machineId') required int machineId,
      @Path('remainingSingleSidedCount') required String remainingSingleSidedCount});

  @POST('/v1/internal/event/check/{kioskEventId}/{machineId}')
  Future<void> checkKioskAlive(
      {@Path('kioskEventId') required int kioskEventId,
      @Path('machineId') required int machineId,
      @Query('remainingSingleSidedCount') required String remainingSingleSidedCount});

  @POST('/v1/machine/unique-key/register')
  Future<void> createUniqueKeyHistory({
    @Body() required Map<String, dynamic> body,
  });

  @POST('/v1/qr/back-photo')
  Future<BackPhotoCardResponse> getBackPhotoCardByQr({
    @Body() required Map<String, dynamic> body,
  });

  // Vending APIs
  @POST('/v1/vending/order')
  Future<CreateVendingOrderResponse> createVendingOrder({
    @Body() required Map<String, dynamic> body,
  });

  @PATCH('/v1/vending/order/{orderId}/status')
  Future<VendingOrderStatusResponse> updateVendingOrderStatus({
    @Path('orderId') required int orderId,
    @Body() required Map<String, dynamic> body,
  });

  @PATCH('/v1/vending/print/{printedPhotoCardId}/status')
  Future<VendingPrintStatusResponse> updateVendingPrintStatus({
    @Path('printedPhotoCardId') required int printedPhotoCardId,
    @Body() required Map<String, dynamic> body,
  });

  @GET('/v1/vending/print/list')
  Future<VendingPrintListResponse> getVendingPrintList({
    @Query('kioskEventId') required int kioskEventId,
    @Query('kioskMachineId') required int kioskMachineId,
    @Query('pageSize') required int pageSize,
    @Query('currentPage') required int currentPage,
  });

  @GET('/v1/vending/print/reprint/{orderId}')
  Future<VendingReprintResponse> reprintVendingOrder({
    @Path('orderId') required int orderId,
  });
}
