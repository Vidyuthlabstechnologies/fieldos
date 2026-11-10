/// Free portals for a company's suppliers and clients. Online only: they
/// are not company members and nothing of the company is kept on their
/// phones. Each call goes to a server function that returns only what that
/// party may see (20261110440000_supplier_client_portals.sql).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Which portal a code opened.
enum PortalKind { supplier, client }

class PortalLink {
  const PortalLink({required this.kind, required this.id, required this.name, required this.companyId, required this.companyName});
  final PortalKind kind;

  /// The supplier (vendor) id, or the client's site id.
  final String id;
  final String name;
  final String companyId;
  final String companyName;
}

double? _d(Object? v) => (v as num?)?.toDouble();
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

class SupplierQuoteSent {
  const SupplierQuoteSent({required this.rate, required this.gstPct, required this.transport, this.deliveryDays, this.paymentTerms, required this.status});
  final double rate;
  final double gstPct;
  final double transport;
  final int? deliveryDays;
  final String? paymentTerms;

  /// received | accepted | rejected
  final String status;
}

class PriceRequest {
  const PriceRequest({
    required this.id,
    required this.vendorId,
    required this.site,
    required this.companyName,
    required this.item,
    required this.quantity,
    required this.unit,
    required this.open,
    this.notes,
    this.askedOn,
    this.quote,
  });
  final String id;
  final String vendorId;
  final String site;
  final String companyName;
  final String item;
  final double quantity;
  final String unit;
  final bool open;
  final String? notes;
  final DateTime? askedOn;
  final SupplierQuoteSent? quote;

  factory PriceRequest.fromJson(Map<String, dynamic> j) {
    final q = j['quote'] as Map?;
    return PriceRequest(
      id: j['id'] as String,
      vendorId: j['vendor_id'] as String,
      site: j['site'] as String? ?? '',
      companyName: j['company_name'] as String? ?? '',
      item: j['item'] as String? ?? '',
      quantity: _d(j['quantity']) ?? 0,
      unit: j['unit'] as String? ?? '',
      open: j['open'] as bool? ?? false,
      notes: j['notes'] as String?,
      askedOn: _t(j['asked_on']),
      quote: q == null
          ? null
          : SupplierQuoteSent(
              rate: _d(q['rate']) ?? 0,
              gstPct: _d(q['gst_pct']) ?? 18,
              transport: _d(q['transport']) ?? 0,
              deliveryDays: (q['delivery_days'] as num?)?.toInt(),
              paymentTerms: q['payment_terms'] as String?,
              status: q['status'] as String? ?? 'received',
            ),
    );
  }
}

class SupplierOrder {
  const SupplierOrder({
    required this.id,
    required this.site,
    required this.companyName,
    required this.status,
    this.poNumber,
    this.item,
    this.total,
    this.deliveryDate,
    this.createdAt,
    this.dispatchedOn,
    this.vehicle,
    this.note,
  });
  final String id;
  final String site;
  final String companyName;

  /// issued | acknowledged (on the way) | delivered
  final String status;
  final String? poNumber;
  final String? item;
  final double? total;
  final DateTime? deliveryDate;
  final DateTime? createdAt;
  final DateTime? dispatchedOn;
  final String? vehicle;
  final String? note;

  bool get open => status == 'issued' || status == 'acknowledged';

  factory SupplierOrder.fromJson(Map<String, dynamic> j) => SupplierOrder(
        id: j['id'] as String,
        site: j['site'] as String? ?? '',
        companyName: j['company_name'] as String? ?? '',
        status: j['status'] as String? ?? 'issued',
        poNumber: j['po_number'] as String?,
        item: j['item'] as String?,
        total: _d(j['total']),
        deliveryDate: _t(j['delivery_date']),
        createdAt: _t(j['created_at']),
        dispatchedOn: _t(j['dispatched_on']),
        vehicle: j['vehicle'] as String?,
        note: j['supplier_note'] as String?,
      );
}

class SupplierPortalData {
  const SupplierPortalData({required this.companies, required this.requests, required this.orders});
  final List<String> companies;
  final List<PriceRequest> requests;
  final List<SupplierOrder> orders;

  factory SupplierPortalData.fromJson(Map<String, dynamic> j) => SupplierPortalData(
        companies: [for (final s in (j['suppliers'] as List? ?? const []).cast<Map>()) s['company_name'] as String? ?? ''],
        requests: [for (final r in (j['requests'] as List? ?? const []).cast<Map>()) PriceRequest.fromJson(r.cast())],
        orders: [for (final o in (j['orders'] as List? ?? const []).cast<Map>()) SupplierOrder.fromJson(o.cast())],
      );
}

class SiteUpdate {
  const SiteUpdate({required this.id, required this.date, required this.summary, required this.manpower, this.weather, this.photos = const []});
  final String id;
  final DateTime date;
  final String summary;
  final int manpower;
  final String? weather;

  /// Storage paths of up to four photos.
  final List<String> photos;
}

class SiteBill {
  const SiteBill({required this.number, required this.date, required this.amount, required this.status, required this.kind});
  final String number;
  final DateTime date;
  final double amount;
  final String status;
  final String kind;
}

class ClientPayment {
  const ClientPayment({required this.date, required this.amount, required this.mode});
  final DateTime date;
  final double amount;
  final String mode;
}

class ClientSite {
  const ClientSite({
    required this.id,
    required this.name,
    required this.companyName,
    required this.tasksTotal,
    required this.tasksDone,
    required this.updates,
    required this.bills,
    required this.payments,
  });
  final String id;
  final String name;
  final String companyName;
  final int tasksTotal;
  final int tasksDone;
  final List<SiteUpdate> updates;
  final List<SiteBill> bills;
  final List<ClientPayment> payments;

  double get billed => bills.fold(0, (t, b) => t + b.amount);
  double get paid => payments.fold(0, (t, p) => t + p.amount);
  double get balance => billed - paid;

  /// Share of tasks done, 0 to 1; null without tasks.
  double? get progress => tasksTotal == 0 ? null : tasksDone / tasksTotal;

  factory ClientSite.fromJson(Map<String, dynamic> j) => ClientSite(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        companyName: j['company_name'] as String? ?? '',
        tasksTotal: (j['tasks_total'] as num?)?.toInt() ?? 0,
        tasksDone: (j['tasks_done'] as num?)?.toInt() ?? 0,
        updates: [
          for (final u in (j['updates'] as List? ?? const []).cast<Map>())
            SiteUpdate(
              id: u['id'] as String,
              date: _t(u['entry_date']) ?? DateTime(2000),
              summary: u['work_summary'] as String? ?? '',
              manpower: (u['manpower_count'] as num?)?.toInt() ?? 0,
              weather: u['weather'] as String?,
              photos: [for (final p in (u['photos'] as List? ?? const [])) p as String],
            ),
        ],
        bills: [
          for (final b in (j['bills'] as List? ?? const []).cast<Map>())
            SiteBill(
              number: b['number'] as String? ?? '',
              date: _t(b['date']) ?? DateTime(2000),
              amount: _d(b['amount']) ?? 0,
              status: b['status'] as String? ?? 'issued',
              kind: b['kind'] as String? ?? 'ra',
            ),
        ],
        payments: [
          for (final p in (j['payments'] as List? ?? const []).cast<Map>())
            ClientPayment(date: _t(p['date']) ?? DateTime(2000), amount: _d(p['amount']) ?? 0, mode: p['mode'] as String? ?? ''),
        ],
      );
}

/// A wrong code or too many tries, as [CloudSyncService.joinCompany] says it.
class PortalJoinError implements Exception {
  const PortalJoinError(this.code);
  final String code;
  @override
  String toString() => code == 'too_many_attempts'
      ? 'Too many wrong codes. Try again in an hour.'
      : 'That code is not right. Check it with the builder.';
}

class PortalService {
  PortalService(this.client);
  final SupabaseClient client;

  Future<PortalLink> join(String code) async {
    final m = Map<String, dynamic>.from(await client.rpc('join_portal', params: {'p_code': code}) as Map);
    final error = m['error'] as String?;
    if (error != null) throw PortalJoinError(error);
    return PortalLink(
      kind: m['kind'] == 'client' ? PortalKind.client : PortalKind.supplier,
      id: m['id'] as String,
      name: m['name'] as String? ?? '',
      companyId: m['company_id'] as String,
      companyName: m['company_name'] as String? ?? 'Company',
    );
  }

  Future<SupplierPortalData> supplierPortal() async =>
      SupplierPortalData.fromJson(Map<String, dynamic>.from(await client.rpc('supplier_portal') as Map));

  Future<void> sendQuote(PriceRequest r,
          {required double rate, required double gstPct, double transport = 0, int? deliveryDays, String? paymentTerms}) =>
      client.rpc('supplier_send_quote', params: {
        'p_request_id': r.id,
        'p_vendor_id': r.vendorId,
        'p_rate': rate,
        'p_gst_pct': gstPct,
        'p_transport': transport,
        'p_delivery_days': deliveryDays,
        'p_payment_terms': paymentTerms,
      });

  Future<void> dispatch(String orderId, {String? vehicle, String? note}) =>
      client.rpc('supplier_dispatch', params: {'p_po_id': orderId, 'p_vehicle': vehicle, 'p_note': note});

  Future<List<ClientSite>> clientPortal() async => [
        for (final s in (await client.rpc('client_portal') as List).cast<Map>()) ClientSite.fromJson(s.cast()),
      ];

  /// A link to one site photo, good for an hour.
  Future<String> photoUrl(String path) => client.storage.from('documents').createSignedUrl(path, 3600);

  // --- The builder's side ---------------------------------------------------

  Future<String> supplierCode(String vendorId) async =>
      await client.rpc('supplier_access_code', params: {'p_vendor_id': vendorId}) as String;

  Future<String> clientCode(String projectId) async =>
      await client.rpc('client_access_code', params: {'p_project_id': projectId}) as String;

  /// Returns how many of them can see it in the app now.
  Future<int> inviteSuppliers(String requestId, List<String> vendorIds) async =>
      (await client.rpc('invite_suppliers_to_quote', params: {'p_request_id': requestId, 'p_vendor_ids': vendorIds}) as num)
          .toInt();
}

final portalServiceProvider = Provider<PortalService>((ref) => PortalService(ref.watch(cloudSyncServiceProvider).client));
