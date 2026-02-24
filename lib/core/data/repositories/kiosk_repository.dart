import 'package:vending_kiosk/core/data/datasources/remote/kiosk_api_client.dart';
import 'package:vending_kiosk/core/data/models/request/card_stock_consume_request.dart';
import 'package:vending_kiosk/core/data/models/request/card_stock_recharge_request.dart';
import 'package:vending_kiosk/core/data/models/request/unique_key_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_back_photo_request.dart';
import 'package:vending_kiosk/core/data/models/request/create_order_request.dart';
import 'package:vending_kiosk/core/data/models/request/create_print_request.dart';
import 'package:vending_kiosk/core/data/models/request/get_back_photo_by_qr_request.dart';
import 'package:vending_kiosk/core/data/models/request/get_orders_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_order_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_print_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_print_status_request.dart';
import 'package:vending_kiosk/core/data/models/response/alert_definition_response.dart';
import 'package:vending_kiosk/core/data/models/response/back_photo_card_response.dart';
import 'package:vending_kiosk/core/data/models/response/back_photo_status_response.dart';
import 'package:vending_kiosk/core/data/models/response/card_stock_consume_response.dart';
import 'package:vending_kiosk/core/data/models/response/card_stock_recharge_response.dart';
import 'package:vending_kiosk/core/data/models/response/create_order_response.dart';
import 'package:vending_kiosk/core/data/models/response/create_print_response.dart';
import 'package:vending_kiosk/core/data/models/response/kiosk_machine_info.dart';
import 'package:vending_kiosk/core/data/models/response/nominated_photo_list.dart';
import 'package:vending_kiosk/core/data/models/response/order_list_response.dart';
import 'package:vending_kiosk/core/data/models/response/update_order_response.dart';
import 'package:vending_kiosk/core/data/models/response/update_print_response.dart';
import 'package:vending_kiosk/core/data/models/response/machine_card_stock_response.dart';
import 'package:vending_kiosk/core/data/models/request/create_vending_order_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_order_status_request.dart';
import 'package:vending_kiosk/core/data/models/response/create_vending_order_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_order_status_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_status_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_list_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_reprint_response.dart';
import 'package:vending_kiosk/core/network/dio_client.dart';
import 'package:vending_kiosk/flavors.dart';
import 'package:vending_kiosk/lib.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vending_kiosk/presentation/core/card_count_provider.dart';
import 'package:vending_kiosk/presentation/print/dispense_progress_provider.dart';

part 'kiosk_repository.g.dart';

@riverpod
class KioskRepository extends _$KioskRepository {
  @override
  _KioskRepository build() {
    final dio = ref.watch(dioProvider(F.kioskBaseUrl));

    return _KioskRepository(KioskApiClient(dio), ref);
  }
}

class _KioskRepository {
  final KioskApiClient _apiClient;
  final Ref _ref;

  _KioskRepository(this._apiClient, this._ref);
  Future<String> healthCheck() async {
    try {
      return await _apiClient.healthCheck();
    } catch (e) {
      rethrow;
    }
  }

  // Slack Alert definitions
  Future<List<AlertDefinitionResponse>> getAlertDefinition() async {
    try {
      return await _apiClient.getAlertDefinitions();
    } catch (e) {
      rethrow;
    }
  }

  /// POST /v1/internal/slack-alert — 서버가 타입·메시지에 따라 Slack 전송
  Future<void> sendSlackAlert(String type, String message) async {
    try {
      await _apiClient.sendSlackAlert({'type': type, 'text': message});
    } catch (e) {
      rethrow;
    }
  }

  // Machine Info Operations
  Future<KioskMachineInfo> getKioskMachineInfo(int machineId) async {
    try {
      return await _apiClient.getKioskMachineInfo(kioskMachineId: machineId);
    } catch (e) {
      rethrow;
    }
  }

  Future<KioskMachineInfo> getKioskMachineInfoByKey(String uniqueKey) async {
    try {
      return await _apiClient.getKioskMachineInfoByKey(uniqueKey: uniqueKey);
    } catch (e) {
      rethrow;
    }
  }

  Future<MachineCardStockResponse> getMachineCardStock(int machineId, {String? uniqueKey}) async {
    try {
      final response = await _apiClient.getMachineCardStock(
        machineId: machineId,
        uniqueKey: uniqueKey,
      );

      _ref
          .read(dispenseProgressNotifierProvider.notifier)
          .updateCurrent(response.cardCurrentCount, response.cardCapacity);

      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<CardStockConsumeResponse> consumeCardStock(CardStockConsumeRequest request) async {
    try {
      final response = await _apiClient.consumeCardStock(
        body: request.toJson(),
      );

      _ref
          .read(dispenseProgressNotifierProvider.notifier)
          .updateCurrent(response.cardCurrentCount, response.cardCapacity);

      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<CardStockRechargeResponse> rechargeCardStock(CardStockRechargeRequest request) async {
    try {
      final response = await _apiClient.rechargeCardStock(
        body: request.toJson(),
      );

      _ref.read(dispenseProgressNotifierProvider.notifier).initialize(response.cardCurrentCount);

      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Photo Operations
  Future<NominatedPhotoList> getFrontPhotoList(int eventId) async {
    try {
      return await _apiClient.getFrontPhotoList(kioskEventId: eventId);
    } catch (e) {
      rethrow;
    }
  }

  Future<BackPhotoCardResponse> getBackPhotoCard(int eventId, String authNumber) async {
    try {
      return await _apiClient.getBackPhotoCard(
        kioskEventId: eventId,
        photoAuthNumber: authNumber,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<BackPhotoStatusResponse> updateBackPhotoStatus(UpdateBackPhotoRequest request) async {
    try {
      return await _apiClient.updateBackPhotoStatus(
        body: request.toJson(),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<OrderListResponse> getOrders(GetOrdersRequest request) async {
    try {
      return await _apiClient.getOrders(
        pageSize: request.pageSize,
        currentPage: request.currentPage,
        kioskMachineId: request.kioskMachineId,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<CreateOrderResponse> createOrderStatus(CreateOrderRequest request) async {
    try {
      return await _apiClient.createOrder(
        body: request.toJson(),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<UpdateOrderResponse> updateOrderStatus(int orderId, UpdateOrderRequest request) async {
    try {
      return await _apiClient.updateOrder(
        orderId: orderId,
        body: request.toJson(),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<CreatePrintResponse> createPrintStatus({
    required CreatePrintRequest request,
  }) async {
    try {
      return await _apiClient.createPrint(body: request.toJson());
    } catch (e) {
      rethrow;
    }
  }

  Future<UpdatePrintResponse> updatePrintStatus({
    required int printedPhotoCardId,
    required UpdatePrintRequest request,
  }) async {
    try {
      return await _apiClient.updatePrint(
        printedPhotoCardId: printedPhotoCardId,
        body: request.toJson(),
      );
    } catch (e) {
      rethrow;
    }
  }

  // Future<void> updatePrintLog({
  //   required PrinterLog request,
  // }) async {
  //   try {
  //     final cardCount = _ref.read(cardCountProvider);

  //     await _apiClient.updatePrintLog(
  //       body: {
  //         ...request.toJson(),
  //         'remainingSingleSidedCount': cardCount.remainingSingleSidedCount,
  //       },
  //     );
  //   } catch (e) {
  //     rethrow;
  //   }
  // }

  Future<void> endKioskApplication({
    required int kioskEventId,
    required int machineId,
  }) async {
    try {
      await _apiClient.endKioskApplication(kioskEventId: kioskEventId, machineId: machineId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteEndMark({
    required int kioskEventId,
    required int machineId,
    required String remainingSingleSidedCount,
  }) async {
    try {
      await _apiClient.deleteEndMark(
          kioskEventId: kioskEventId, machineId: machineId, remainingSingleSidedCount: remainingSingleSidedCount);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> checkKioskAlive({
    required int kioskEventId,
    required int machineId,
    required String remainingSingleSidedCount,
  }) async {
    try {
      await _apiClient.checkKioskAlive(
          kioskEventId: kioskEventId, machineId: machineId, remainingSingleSidedCount: remainingSingleSidedCount);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> createUniqueKeyHistory({required UniqueKeyRequest request}) async {
    try {
      await _apiClient.createUniqueKeyHistory(body: request.toJson());
    } catch (e) {
      rethrow;
    }
  }

  Future<BackPhotoCardResponse> getBackPhotoCardByQr(GetBackPhotoByQrRequest request) async {
    try {
      return await _apiClient.getBackPhotoCardByQr(
        body: request.toJson(),
      );
    } catch (e) {
      rethrow;
    }
  }

  // Vending APIs
  Future<CreateVendingOrderResponse> createVendingOrder(CreateVendingOrderRequest request) async {
    try {
      return await _apiClient.createVendingOrder(body: request.toJson());
    } catch (e) {
      rethrow;
    }
  }

  Future<VendingOrderStatusResponse> updateVendingOrderStatus(
    int orderId,
    UpdateVendingOrderStatusRequest request,
  ) async {
    try {
      return await _apiClient.updateVendingOrderStatus(
        orderId: orderId,
        body: request.toJson(),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<VendingPrintStatusResponse> updateVendingPrintStatus(
    int printedPhotoCardId,
    UpdateVendingPrintStatusRequest request,
  ) async {
    try {
      return await _apiClient.updateVendingPrintStatus(
        printedPhotoCardId: printedPhotoCardId,
        body: request.toJson(),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<VendingPrintListResponse> getVendingPrintList({
    required int kioskEventId,
    required int kioskMachineId,
    required int pageSize,
    required int currentPage,
  }) async {
    try {
      return await _apiClient.getVendingPrintList(
        kioskEventId: kioskEventId,
        kioskMachineId: kioskMachineId,
        pageSize: pageSize,
        currentPage: currentPage,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<VendingReprintResponse> reprintVendingOrder(int orderId) async {
    try {
      return await _apiClient.reprintVendingOrder(orderId: orderId);
    } catch (e) {
      rethrow;
    }
  }
}
