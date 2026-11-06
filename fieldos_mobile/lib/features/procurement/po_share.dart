/// A purchase order as a message to send the supplier on WhatsApp.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';

String poShareText({
  required PurchaseOrder order,
  required String companyName,
  String? projectName,
  String? supplierName,
  PurchaseRequest? request,
}) {
  final number = (order.poNumber ?? '').trim();
  final lines = <String>[
    number.isEmpty ? 'Purchase order' : 'Purchase order $number',
    if (companyName.trim().isNotEmpty) 'From: ${companyName.trim()}',
    if ((supplierName ?? '').trim().isNotEmpty) 'To: ${supplierName!.trim()}',
    if ((projectName ?? '').trim().isNotEmpty) 'Site: ${projectName!.trim()}',
    if (request != null)
      'Material: ${[request.materialName.trim(), fmtQty(request.quantity), if (request.unit.trim().isNotEmpty) request.unit.trim()].join(' ')}',
    if (order.totalAmount != null) 'Amount: ${rupees(order.totalAmount!, paise: true)}',
    if (order.deliveryDate != null) 'Deliver by: ${fmtDate(order.deliveryDate!)}',
    if ((order.notes ?? '').trim().isNotEmpty) 'Notes: ${order.notes!.trim()}',
    'Dated ${fmtDate(order.createdAt)}',
    '',
    'Please confirm the delivery date by reply.',
  ];
  return lines.join('\n');
}
