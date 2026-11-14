/// The paper size PDFs are laid out on. Americans print on US Letter
/// (8.5 x 11 in); an A4 page there gets its foot cut off or shrunk to fit,
/// so a bill or payslip looks wrong in the client's hands. Every other
/// market FieldOS sells in uses A4.
library;

import 'package:pdf/pdf.dart';

import 'package:fieldos_mobile/core/market.dart';

/// Letter for [Market.us], A4 for every other market. Read when the PDF is
/// built, so it follows [currentMarket] (and debugSetMarket in tests).
PdfPageFormat marketPageFormat([Market? m]) =>
    (m ?? currentMarket) == Market.us ? PdfPageFormat.letter : PdfPageFormat.a4;
