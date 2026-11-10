/// Supplier quotes for one purchase request, compared on what the material
/// will really cost at site: rate times quantity, GST on the material, and
/// transport. The cheapest valid quote is marked, with what it saves
/// against the next one and against the estimate.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';

const gstChoices = [0.0, 5.0, 12.0, 18.0, 28.0];

class QuoteLine {
  QuoteLine(this.quote, this.qty);
  final SupplierQuote quote;
  final double qty;

  double get material => quote.rate * qty;
  double get gst => material * quote.gstPct / 100;
  double get landed => material + gst + quote.transport;
  double get perUnit => qty > 0 ? landed / qty : 0;

  bool expired(DateTime now) {
    final v = quote.validUntil;
    return v != null && DateTime(v.year, v.month, v.day).isBefore(DateTime(now.year, now.month, now.day));
  }
}

class QuoteComparison {
  QuoteComparison(this.lines, this.estimate);

  /// Valid quotes cheapest first, then expired and turned-down ones.
  final List<QuoteLine> lines;
  final double? estimate;

  QuoteLine? get best => lines.isEmpty || lines.first.quote.status == 'rejected' ? null : lines.first;

  /// The cheapest valid quote less the next one.
  double? savingVsNext(DateTime now) {
    final open = [for (final l in lines) if (l.quote.status != 'rejected' && !l.expired(now)) l];
    return open.length < 2 ? null : open[1].landed - open[0].landed;
  }

  double? savingVsEstimate() => best == null || estimate == null ? null : estimate! - best!.landed;

  /// The fastest delivery among valid quotes, to flag when the cheapest is slow.
  int? fastestDays(DateTime now) {
    int? d;
    for (final l in lines) {
      if (l.quote.status == 'rejected' || l.expired(now) || l.quote.deliveryDays == null) continue;
      if (d == null || l.quote.deliveryDays! < d) d = l.quote.deliveryDays;
    }
    return d;
  }
}

QuoteComparison compareQuotes(PurchaseRequest r, Iterable<SupplierQuote> quotes, DateTime now) {
  final lines = [for (final q in quotes) QuoteLine(q, r.quantity)];
  int rank(QuoteLine l) => l.quote.status == 'accepted' ? 0 : (l.quote.status == 'rejected' ? 3 : (l.expired(now) ? 2 : 1));
  lines.sort((a, b) {
    final x = rank(a).compareTo(rank(b));
    return x != 0 ? x : a.landed.compareTo(b.landed);
  });
  return QuoteComparison(lines, r.estimatedAmount);
}

/// The message asking a supplier for their price, for WhatsApp.
String rfqMessage({
  required PurchaseRequest request,
  required String siteName,
  required String companyName,
  String? siteLocation,
  DateTime? needBy,
}) {
  final b = StringBuffer()
    ..writeln('Namaste, $companyName here.')
    ..writeln('Please send your best rate for:')
    ..writeln('${request.materialName}: ${fmtQty(request.quantity)} ${request.unit}'.trim())
    ..writeln('Delivery to: $siteName${siteLocation == null || siteLocation.trim().isEmpty ? '' : ', ${siteLocation.trim()}'}');
  if (needBy != null) b.writeln('Needed by: ${fmtDate(needBy)}');
  b
    ..writeln('Please mention the rate a unit, GST, transport, delivery days and payment terms.')
    ..write('Thank you.');
  return b.toString();
}

/// What goes on the PO's notes when a quote is awarded.
String awardNote(SupplierQuote q) => [
      'Quote: ${rupees(q.rate, paise: true)} a unit',
      'GST ${fmtQty(q.gstPct)}%',
      if (q.transport > 0) 'transport ${rupees(q.transport)}',
      if (q.deliveryDays != null) 'delivery ${q.deliveryDays} days',
      if (q.paymentTerms != null) q.paymentTerms!,
    ].join(', ');
