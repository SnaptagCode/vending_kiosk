import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/core/common/constants/image_paths.dart';
import 'package:vending_kiosk/core/common/sound/sound_manager.dart';
import 'package:vending_kiosk/core/data/models/entities/vending_print_item_entity.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/setup/payment_history_provider.dart';
import 'package:vending_kiosk/presentation/setup/setup_refund_process_provider.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/core/ui/widget/general_error_widget.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:flutter_svg/svg.dart';
import 'package:loader_overlay/loader_overlay.dart';

class PaymentHistoryScreen extends ConsumerStatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen(setupRefundProcessProvider, (prev, next) {
      next.whenOrNull(
        error: (error, stack) async {
          context.loaderOverlay.hide();
          await DialogHelper.showSetupDialog(context, title: '환불이 실패했습니다.');
        },
        data: (response) async {
          context.loaderOverlay.hide();
          if (response != null && response.respCode == '0000') {
            await DialogHelper.showSetupDialog(context, title: '환불이 완료되었습니다.');
          } else if (response != null) {
            await DialogHelper.showSetupDialog(context, title: '환불이 실패했습니다.');
          }
        },
      );
    });
    final ordersPage = ref.watch(ordersPageProvider());

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
              fontFamily: 'Pretendard',
            ),
      ),
      child: LoaderOverlay(
        overlayWidgetBuilder: (dynamic progress) {
          return Center(
            child: SizedBox(
              width: 350.h,
              height: 350.h,
              child: CircularProgressIndicator(
                strokeWidth: 15.h,
              ),
            ),
          );
        },
        child: Scaffold(
          backgroundColor: Color(0xFFF2F2F2),
          appBar: AppBar(
            leading: IconButton(
              padding: EdgeInsets.only(left: 30.w),
              icon: SvgPicture.asset(SnaptagSvg.arrowBack),
              onPressed: () async {
                final result = await DialogHelper.showSetupDialog(
                  context,
                  title: '메인페이지로 이동합니다.',
                );
                if (result) {
                  Navigator.pop(context);
                }
              },
            ),
            title: const Text('출력 내역'),
            actions: [
              IconButton(
                padding: EdgeInsets.only(left: 30.w),
                icon: SvgPicture.asset(SnaptagSvg.home),
                onPressed: () async {
                  HomeRouteData().go(context);
                },
              ),
            ],
          ),
          body: ordersPage.when(
            data: (response) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 130.w,
                  ),
                  SizedBox(
                    width: 438.w,
                    child: DateWidget(),
                  ),
                  SizedBox(
                    height: 60.w,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 30.w),
                    child: SizedBox(
                      width: double.infinity,
                      child: DataTable(
                        columnSpacing: 15.0,
                        horizontalMargin: 0,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(
                            color: Color(0xFFE6E8EB),
                            width: 1,
                          ),
                        ),
                        headingTextStyle: TextStyle(
                          color: Color(0xFF757575),
                          fontSize: 18.sp,
                        ),
                        headingRowColor: WidgetStateColor.resolveWith(
                          (states) => Color(0xFFF6F7F8),
                        ),
                        dataTextStyle: TextStyle(
                          color: Color(0xFF414448),
                          fontSize: 16.sp,
                        ),
                        columns: columns,
                        rows: response.list.map((order) {
                          return DataRow(
                            color: WidgetStateColor.resolveWith((states) => Colors.white),
                            cells: [
                              DataCell(
                                Center(
                                  child: Text(
                                    order.completedAt != null
                                        ? DateFormat('yyyy.MM.dd HH:mm').format(
                                            DateTime.parse(order.completedAt!),
                                          )
                                        : '',
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: Text(
                                    order.eventName.length > 20
                                        ? '${order.eventName.substring(0, 20)}...'
                                        : order.eventName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(child: Text(NumberFormat('#,###').format(order.amount))),
                              ),
                              DataCell(
                                Center(child: Text(_getOrderState(order.orderStatus))),
                              ),
                              DataCell(
                                Center(child: _getRefundWidget(context, order)),
                              ),
                              DataCell(
                                Center(child: _buildPrintStatusCell(context, order)),
                              ),
                              DataCell(
                                Center(child: Text(order.purchaseAuthNumber)),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  PaginationControls(
                    currentPage: response.paging.currentPage,
                    totalPages: (response.paging.totalCount / response.paging.pageSize).ceil(),
                    onPageChanged: (newPage) {
                      ref.read(ordersPageProvider().notifier).goToPage(newPage);
                    },
                  ),
                ],
              );
            },
            loading: () => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading orders...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            error: (error, stack) => GeneralErrorWidget(
              exception: error as Exception,
              onRetry: () => ref.refresh(ordersPageProvider()),
            ),
          ),
        ),
      ),
    );
  }

  List<DataColumn> get columns {
    return const [
      DataColumn(
        label: Text('일자'),
        headingRowAlignment: MainAxisAlignment.center,
      ),
      DataColumn(
        label: Text('이벤트명'),
        headingRowAlignment: MainAxisAlignment.center,
      ),
      DataColumn(
        label: Text('결제 금액'),
        headingRowAlignment: MainAxisAlignment.center,
      ),
      DataColumn(
        label: Text('결제 상태'),
        headingRowAlignment: MainAxisAlignment.center,
      ),
      DataColumn(
        label: Text('환불 상태'),
        headingRowAlignment: MainAxisAlignment.center,
      ),
      DataColumn(
        label: Text('출력 상태'),
        headingRowAlignment: MainAxisAlignment.center,
      ),
      DataColumn(
        label: Align(
            alignment: Alignment.center,
            child: Text(
              '결제 \n승인번호',
              textAlign: TextAlign.center,
            )),
        headingRowAlignment: MainAxisAlignment.center,
      ),
    ];
  }

  Widget _buildPrintStatusCell(BuildContext context, VendingPrintItemEntity order) {
    final isIncomplete = order.completedCount != order.totalCount;
    final text = '${order.completedCount}/${order.totalCount}';

    if (!isIncomplete) {
      return Text(text, style: TextStyle(fontSize: 16.sp));
    }

    return GestureDetector(
      onTap: () => _handleReprint(context, order),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.red,
          fontSize: 16.sp,
          decoration: TextDecoration.underline,
          decorationColor: Colors.red,
        ),
      ),
    );
  }

  Future<void> _handleReprint(BuildContext context, VendingPrintItemEntity order) async {
    context.loaderOverlay.show();
    try {
      final response = await ref.read(kioskRepositoryProvider).reprintVendingOrder(order.kioskOrderId);

      if (response.reprintableIds.isEmpty) {
        context.loaderOverlay.hide();
        return;
      }

      ref.read(reprintIdsProvider.notifier).state = response.reprintableIds;
      ref.read(printQuantityNotifierProvider.notifier).setQuantity(response.reprintableIds.length);

      context.loaderOverlay.hide();
      PrintProcessRouteData().go(context);
    } catch (e) {
      context.loaderOverlay.hide();
    }
  }

  String _getOrderState(String status) {
    switch (status) {
      case 'pending':
        return '결제 대기';
      case 'failed':
        return '결제 실패';
      default:
        return '결제 완료';
    }
  }

  Widget _getRefundWidget(BuildContext context, VendingPrintItemEntity order) {
    if (order.isRefunded) {
      return TextButton(
        onPressed: null,
        child: Text(
          '환불 완료',
          style: TextStyle(
            color: Color(0xFF414448),
            fontSize: 16.sp,
          ),
        ),
      );
    }

    if (order.orderStatus == 'pending' || order.orderStatus == 'failed') {
      return TextButton(
        onPressed: null,
        child: Text(
          '-',
          style: TextStyle(
            color: Color(0xFF414448),
            fontSize: 16.sp,
          ),
        ),
      );
    }

    return TextButton(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color(0xFF9D9D9D),
            ),
          ),
        ),
        child: Text(
          '환불',
          style: TextStyle(
            color: Color(0xFF9D9D9D),
            fontSize: 16.sp,
          ),
        ),
      ),
      onPressed: () async {
        context.loaderOverlay.show();
        await SoundManager().playSound();
        final result1 = await DialogHelper.showSetupDialog(
          context,
          title: '환불을 진행합니다.',
          showCancelButton: true,
        );
        if (!result1) {
          context.loaderOverlay.hide();
          return;
        }
        final result2 = await DialogHelper.showSetupDialog(
          context,
          title: '결제한 카드를 삽입해 주세요.',
          cancelButtonText: '환불 취소',
          confirmButtonText: '환불 진행',
          showCancelButton: true,
        );
        if (result2) {
          await ref.read(setupRefundProcessProvider.notifier).startRefund(order);
          context.loaderOverlay.hide();
        } else {
          context.loaderOverlay.hide();
        }
      },
    );
  }
}

class DateWidget extends StatelessWidget {
  const DateWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          DateFormat('yyyy.MM.dd').format(DateTime.now().subtract(const Duration(days: 14))),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF1C1C1C),
            fontSize: 32.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '-',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF1C1C1C),
            fontSize: 32.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          DateFormat('yyyy.MM.dd').format(DateTime.now()),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF1C1C1C),
            fontSize: 32.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// PaginationControls 위젯은 이전과 동일
class PaginationControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    List<Widget> pageButtons() {
      List<Widget> buttons = [];
      int startPage = (currentPage - 5).clamp(1, totalPages > 10 ? totalPages - 9 : 1);
      int endPage = (startPage + 9).clamp(startPage, totalPages);

      for (int i = startPage; i <= endPage; i++) {
        buttons.add(
          ActionChip(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            labelPadding: EdgeInsets.zero,
            label: Text(
              i.toString(),
              style: TextStyle(
                color: i == currentPage ? Colors.white : Colors.black,
                fontSize: 14,
              ),
            ),
            backgroundColor: i == currentPage ? Color(0xFFA671EA) : Color(0xFFF2F2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: Colors.transparent),
            ),
            onPressed: () => onPageChanged(i),
          ),
        );
      }
      return buttons;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: currentPage > 1 ? () => onPageChanged(1) : null,
              child: const Icon(Icons.keyboard_double_arrow_left_sharp),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
              child: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 8),
            ...pageButtons(),
            const SizedBox(width: 8),
            InkWell(
              onTap: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
              child: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: currentPage < totalPages ? () => onPageChanged(totalPages) : null,
              child: const Icon(Icons.keyboard_double_arrow_right_sharp),
            ),
          ],
        ),
      ),
    );
  }
}
