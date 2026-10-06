import 'dart:typed_data';
import '../domain/image_bytes.dart';
import '../database/workflow_service.dart';
import '../domain/format.dart';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'brand.dart';
import 'pdf_support.dart';

class ReceiptActions {
  static String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  /// Indian-numbering amount in words, suitable for receipts/vouchers.
  /// Example: 1250.50 -> "Rupees One Thousand Two Hundred Fifty and Paise Fifty Only".
  static String amountInWords(double value) {
    if (!value.isFinite || value < 0) return 'Rupees Zero Only';
    final roundedPaise = (value * 100).round();
    var rupees = roundedPaise ~/ 100;
    final paise = roundedPaise % 100;

    String underHundred(int n) {
      const ones = [
        '',
        'One',
        'Two',
        'Three',
        'Four',
        'Five',
        'Six',
        'Seven',
        'Eight',
        'Nine',
        'Ten',
        'Eleven',
        'Twelve',
        'Thirteen',
        'Fourteen',
        'Fifteen',
        'Sixteen',
        'Seventeen',
        'Eighteen',
        'Nineteen',
      ];
      const tens = [
        '',
        '',
        'Twenty',
        'Thirty',
        'Forty',
        'Fifty',
        'Sixty',
        'Seventy',
        'Eighty',
        'Ninety',
      ];
      if (n < 20) return ones[n];
      return '${tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${ones[n % 10]}'}';
    }

    String integerWords(int n) {
      if (n == 0) return 'Zero';
      final parts = <String>[];
      if (n >= 10000000) {
        parts.add('${integerWords(n ~/ 10000000)} Crore');
        n %= 10000000;
      }
      if (n >= 100000) {
        parts.add('${integerWords(n ~/ 100000)} Lakh');
        n %= 100000;
      }
      if (n >= 1000) {
        parts.add('${integerWords(n ~/ 1000)} Thousand');
        n %= 1000;
      }
      if (n >= 100) {
        parts.add('${underHundred(n ~/ 100)} Hundred');
        n %= 100;
      }
      if (n > 0) parts.add(underHundred(n));
      return parts.join(' ');
    }

    // Protect against an accidental negative zero after rounding.
    if (rupees == 0 && paise == 0) return 'Rupees Zero Only';
    final rupeePart = 'Rupees ${integerWords(rupees)}';
    final paisePart = paise == 0 ? '' : ' and Paise ${underHundred(paise)}';
    return '$rupeePart$paisePart Only';
  }

  static Future<void> printPdf({required Uint8List bytes, required String fileName}) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
  }

  static Future<void> sharePdf({
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: message,
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
  }

  static Future<void> showActionsDialog({
    required BuildContext context,
    required String documentNumber,
    required Future<Uint8List> Function() buildPdf,
    required String shareMessage,
    String title = 'Document Generated',
    String fileNamePrefix = 'Document',
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text('No: $documentNumber'),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Print / Save PDF'),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final bytes = await buildPdf();
                await printPdf(bytes: bytes, fileName: '$fileNamePrefix-$documentNumber.pdf');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not print PDF: $e')));
                }
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Send via WhatsApp'),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final bytes = await buildPdf();
                await sharePdf(
                  bytes: bytes,
                  fileName: '$fileNamePrefix-$documentNumber.pdf',
                  message: shareMessage,
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share PDF: $e')));
                }
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Compact two-column row used by thermal-roll receipts.
  static pw.TableRow thermalRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.8),
          child: pw.Text(label, style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.8),
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 7.6)),
        ),
      ],
    );
  }

  /// Page format for a thermal roll (58 mm or 80 mm, see [PdfSupport]).
  /// The height is unbounded, so the page is only as long as the content.
  static PdfPageFormat _thermalFormat() => PdfPageFormat(
        PdfSupport.thermalWidthMm * PdfPageFormat.mm,
        double.infinity,
        marginAll: 2.5 * PdfPageFormat.mm,
      );

  /// Compact receipt for a small portable thermal printer: monochrome, tiny
  /// logo, number and date on one row, and no wasted paper below the content.
  static pw.Document thermalReceiptDocument({
    required String title,
    required String documentNumber,
    required DateTime date,
    required List<pw.TableRow> rows,
    String? amountWords,
    String? remarks,
    String? outstanding,
    String? totalSettled,
    String? balanceRemaining,
  }) {
    final document = pw.Document(theme: PdfSupport.theme);
    document.addPage(
      pw.Page(
        pageFormat: _thermalFormat(),
        build: (_) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Image(brandPdfLogo, width: 18, height: 18, fit: pw.BoxFit.contain)),
            pw.SizedBox(height: 1.5),
            pw.Text('AL-AMIN BAITUL MAAL TRUST', textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8.6, fontWeight: pw.FontWeight.bold)),
            pw.Text('Regd. No. 5767 \u2022 Dangerpora, Malla Bagh, Srinagar', textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 6)),
            pw.Divider(thickness: .6, height: 5),
            pw.Text(title.toUpperCase(), textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('No: $documentNumber', style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold)),
                pw.Text(formatDate(date), style: const pw.TextStyle(fontSize: 7.2)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Table(
              border: const pw.TableBorder(
                top: pw.BorderSide(width: .5, color: PdfColors.black),
                horizontalInside: pw.BorderSide(width: .3, color: PdfColors.grey600),
                bottom: pw.BorderSide(width: .5, color: PdfColors.black),
              ),
              columnWidths: const {0: pw.FlexColumnWidth(1.0), 1: pw.FlexColumnWidth(1.5)},
              children: rows,
            ),
            if (totalSettled != null && totalSettled.trim().isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 1, color: PdfColors.black),
                    bottom: pw.BorderSide(width: 1, color: PdfColors.black),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text(totalSettled.trim(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ],
            if (amountWords != null && amountWords.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(amountWords.trim(), style: const pw.TextStyle(fontSize: 6.6)),
            ],
            if (outstanding != null && outstanding.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text('OUTSTANDING: ${outstanding.trim()}', style: pw.TextStyle(fontSize: 7.4, fontWeight: pw.FontWeight.bold)),
            ],
            if (balanceRemaining != null && balanceRemaining.trim().isNotEmpty) ...[
              pw.SizedBox(height: 1.5),
              pw.Text('BALANCE: ${balanceRemaining.trim()}', style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold)),
            ],
            if (remarks != null && remarks.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text('Remarks: ${remarks.trim()}', style: const pw.TextStyle(fontSize: 6.4)),
            ],
            pw.SizedBox(height: 3),
            pw.Text('Thank you', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6.6)),
          ],
        ),
      ),
    );
    return document;
  }

  /// Minimal thermal receipt specifically for Qarz-e-Hassanah repayments.
  /// Deliberately excludes address, phone, Aadhaar, mode, verification,
  /// signatures, receipt number and date as requested.
  static pw.Document qarzaRecoveryThermalDocument({
    required String name,
    required double amount,
    required double amountBorrowed,
    required double amountReturned,
    required double balanceAfter,
  }) {
    final document = pw.Document(theme: PdfSupport.theme);
    pw.Widget valueRow(String label, String value, {bool emphasize = false}) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.4, horizontal: 1),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: .35, color: PdfColors.grey700)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 5, child: pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(width: 3),
          pw.Expanded(flex: 5, child: pw.Text(value, textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: emphasize ? 9 : 7.6, fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal))),
        ],
      ),
    );
    document.addPage(pw.Page(
      pageFormat: _thermalFormat(),
      build: (_) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text('QARZ RETURN RECEIPT', textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8.4, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          valueRow('Name', name.trim().isEmpty ? '\u2014' : name.trim()),
          valueRow('Amount', '\u20B9${amount.asAmount}', emphasize: true),
          valueRow('Borrowed', '\u20B9${amountBorrowed.asAmount}'),
          valueRow('Returned (incl. this)', '\u20B9${amountReturned.asAmount}'),
          valueRow('Balance', '\u20B9${balanceAfter.asAmount}', emphasize: true),
        ],
      ),
    ));
    return document;
  }

  static pw.TableRow pdfRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(7),
          color: PdfColor.fromHex('#EEF4F1'),
          child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ),
        pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(value)),
      ],
    );
  }

  static pw.Widget _linedArea(String value, {int lines = 1, double lineHeight = 15, double lineGap = 0}) {
    final safeLines = lines < 1 ? 1 : lines;
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: .5, color: PdfColors.grey600)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(value.trim().isEmpty ? ' ' : value.trim(), style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 3),
          ...List.generate(
            safeLines,
            (index) => pw.Container(
              height: lineHeight,
              margin: pw.EdgeInsets.only(top: index == 0 ? 0 : lineGap),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: .35, color: PdfColors.grey500))),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signature(String label, Uint8List? bytes) {
    // A stored signature that is not a readable image is left blank instead of
    // stopping the whole receipt from printing.
    final image = recoverImageBytes(bytes);
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (image != null)
          pw.Container(height: 58, width: 160, child: pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain))
        else
          pw.SizedBox(height: 58),
        pw.SizedBox(height: 4),
        pw.Text(label, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 16),
      ],
    );
  }

  static pw.Document baseDocument({
    required String title,
    required String documentNumber,
    required String date,
    required List<pw.TableRow> rows,
    String? remarks,
    String footer = 'This document is generated from the saved accounting transaction.',
    String leftSignature = 'Authorized Signature: __________________',
    String rightSignature = 'Thank you',
    bool largeHeader = false,
  }) {
    final document = pw.Document(theme: PdfSupport.theme);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.2, color: PdfColors.black),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pdfBrandHeader(documentTitle: title, large: largeHeader),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('No: $documentNumber'), pw.Text('Date: $date')],
              ),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(width: .7),
                columnWidths: const {0: pw.FlexColumnWidth(1.45), 1: pw.FlexColumnWidth(2.55)},
                children: rows,
              ),
              if (remarks != null && remarks.trim().isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Text('Remarks', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(remarks),
              ],
              pw.Spacer(),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text(footer, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 26),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text(leftSignature), pw.Text(rightSignature)],
              ),
            ],
          ),
        ),
      ),
    );
    return document;
  }

  static pw.Document ledgerDocument({required String title, required List<List<String>> rows, bool includeRemarks = true}) {
    final document = pw.Document(theme: PdfSupport.theme);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(18),
        build: (_) {
          final hasUsername = rows.isNotEmpty && rows.first.length >= 8;
          final showRemarks = includeRemarks && rows.isNotEmpty && rows.first.length >= 8;
          final headers = hasUsername
              ? (showRemarks
                  ? ['Date', 'Amount', 'Debit/Credit', 'Receipt No.', 'Remarks', 'Type', 'Running Balance', 'Username']
                  : ['Date', 'Amount', 'Debit/Credit', 'Receipt No.', 'Remarks', 'Type', 'Running Balance', 'Username'])
              : (showRemarks
                  ? ['Date', 'Amount', 'Debit/Credit', 'Receipt No.', 'Remarks', 'Type', 'Running Balance']
                  : ['Date', 'Amount', 'Debit/Credit', 'Receipt No.', 'Type', 'Running Balance']);
          return [
            pdfBrandHeader(documentTitle: title, large: false),
            pw.Table(
              border: pw.TableBorder.all(width: .5),
              children: [
                pw.TableRow(
                  children: headers.map((v) => pw.Container(
                    padding: const pw.EdgeInsets.all(4),
                    color: PdfColor.fromHex('#145A4A'),
                    child: pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8)),
                  )).toList(),
                ),
                ...rows.map((row) => pw.TableRow(
                  children: row.map((v) => pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(v, style: const pw.TextStyle(fontSize: 7.5)),
                  )).toList(),
                )),
              ],
            ),
          ];
        },
      ),
    );
    return document;
  }

  static double _balanceFromRemarks(String remarks) {
    final match = RegExp(r'Outstanding After Recovery:\s*(?:INR|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false).firstMatch(remarks);
    if (match == null) return 0;
    return double.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
  }

  static pw.Document qarzaVoucherDocument({
    required String documentNumber,
    required DateTime date,
    required String party,
    required String address,
    required String aadhaar,
    required String phone,
    required double amount,
    required String chequeNumber,
    required String paymentMode,
    required String operation,
    required String verification,
    required String verifiedBy1,
    required String verifiedBy2,
    required String verifiedBy3,
    required String remarks,
    Uint8List? recipientSignature,
    Uint8List? accountantSignature,
    String? preparedBy,
    String? parentage,
    String? conditions,
    double? amountBorrowed,
    double? totalReturned,
    double? balanceAfter,
  }) {
    final isIssue = operation.toUpperCase() == 'ISSUE';
    if (!isIssue) {
      final resolvedBalance = balanceAfter ?? _balanceFromRemarks(remarks);
      final resolvedBorrowed = amountBorrowed ?? (amount + resolvedBalance);
      return qarzaRecoveryThermalDocument(
        name: party,
        amount: amount,
        amountBorrowed: resolvedBorrowed,
        amountReturned: totalReturned ?? amount,
        balanceAfter: resolvedBalance,
      );
    }
    final document = pw.Document(theme: PdfSupport.theme);

    pw.Container fieldCell(String label, String value, {bool boldValue = false}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        color: PdfColor.fromHex('#F3F7F5'),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 1.5),
            pw.Text(
              value.trim().isEmpty ? '—' : value.trim(),
              maxLines: label == 'Address' ? 2 : 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(fontSize: 8.4, fontWeight: boldValue ? pw.FontWeight.bold : pw.FontWeight.normal),
            ),
          ],
        ),
      );
    }

    pw.Widget writingBox(String label, String value, {required int lines, required double lineHeight, required double lineGap}) {
      return pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(5, 4, 5, 4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: .6, color: PdfColors.grey700),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8.2, fontWeight: pw.FontWeight.bold)),
            if (value.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(value.trim(), style: const pw.TextStyle(fontSize: 8.2), maxLines: 2, overflow: pw.TextOverflow.clip),
            ],
            pw.SizedBox(height: 2),
            ...List.generate(
              lines,
              (i) => pw.Container(
                height: lineHeight,
                margin: pw.EdgeInsets.only(top: i == 0 ? 0 : lineGap),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: .35, color: PdfColors.grey500)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget verifierCell(String label, String name) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Column(
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 7.1, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              height: 14,
              alignment: pw.Alignment.center,
              child: pw.Text(
                name.trim().isEmpty ? ' ' : name.trim(),
                textAlign: pw.TextAlign.center,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              height: 15,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: .4, color: PdfColors.grey700)),
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text('Signature', style: const pw.TextStyle(fontSize: 6.8)),
          ],
        ),
      );
    }

    pw.Widget signatureBox(String label, Uint8List? bytes) {
      final image = recoverImageBytes(bytes);
      return pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          if (image != null)
            pw.Container(height: 42, width: 145, child: pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain))
          else
            pw.SizedBox(height: 42),
          pw.Container(
            width: 145,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: .5, color: PdfColors.black)),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(label, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
        ],
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
        build: (_) => pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.1, color: PdfColors.black),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pdfBrandHeader(
                documentTitle: isIssue ? 'QARZ-E-HASSANAH ISSUE VOUCHER' : 'QARZ-E-HASSANAH RECOVERY VOUCHER',
                large: false,
              ),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(width: .6),
                columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
                children: [
                  pw.TableRow(children: [
                    fieldCell('Document / Form No.', documentNumber, boldValue: true),
                    fieldCell('Date', formatDate(date)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(width: .6),
                columnWidths: const {0: pw.FlexColumnWidth(1)},
                children: [
                  pw.TableRow(children: [fieldCell('Borrower / Party', party)]),
                  pw.TableRow(children: [fieldCell('Parentage', parentage ?? '')]),
                  pw.TableRow(children: [fieldCell('Address', address)]),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(width: .6),
                columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
                children: [
                  pw.TableRow(children: [
                    fieldCell('Aadhaar Card No.', aadhaar),
                    fieldCell('Phone Number', phone),
                  ]),
                  pw.TableRow(children: [
                    fieldCell(isIssue ? 'Amount Borrowed' : 'Amount Returned', '\u20B9${amount.asAmount}', boldValue: true),
                    fieldCell('Transaction Type', isIssue ? 'Qarz Issued' : 'Qarz Recovered'),
                  ]),
                  pw.TableRow(children: [
                    fieldCell('Payment Mode', paymentMode),
                    fieldCell('Cheque / Payment Reference', chequeNumber),
                  ]),
                ],
              ),
              pw.SizedBox(height: 4),
              fieldCell('Amount in Words', amountInWords(amount)),
              pw.SizedBox(height: 4),
              writingBox('Verification', verification, lines: 4, lineHeight: 9, lineGap: 3),
              pw.SizedBox(height: 4),
              writingBox('Conditions', conditions ?? '', lines: 2, lineHeight: 9, lineGap: 3),
              pw.SizedBox(height: 4),
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(width: .6, color: PdfColors.grey700)),
                child: pw.Table(
                  border: pw.TableBorder.symmetric(
                    inside: const pw.BorderSide(width: .5, color: PdfColors.grey600),
                  ),
                  columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth(), 2: pw.FlexColumnWidth()},
                  children: [
                    pw.TableRow(children: [
                      verifierCell('Verified by 1', verifiedBy1),
                      verifierCell('Verified by 2', verifiedBy2),
                      verifierCell('Verified by 3', verifiedBy3),
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              writingBox('Remarks', remarks, lines: 1, lineHeight: 9, lineGap: 0),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  signatureBox('Borrower / Recipient Signature', recipientSignature),
                  signatureBox('Accountant Signature', accountantSignature),
                ],
              ),
              pw.SizedBox(height: 3),
              if (isIssue) ...[
                pw.Divider(height: 1),
                pw.Text(
                  'Prepared by: ${preparedBy?.trim().isEmpty ?? true ? '—' : preparedBy!.trim()}',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 7.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return document;
  }

  static pw.Document zakaatVoucherDocument({
    required String voucherNumber,
    required DateTime date,
    required String recipientName,
    required String address,
    required String aadhaar,
    required String phone,
    required double amount,
    String reason = '',
    required String authority,
    required String cheque,
    required String paymentMode,
    String verification = '',
    String verifiedBy1 = '',
    String verifiedBy2 = '',
    String verifiedBy3 = '',
    required String remarks,
    Uint8List? recipientSignature,
    Uint8List? accountantSignature,
    String? preparedBy,
  }) {
    final document = pw.Document(theme: PdfSupport.theme);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
        build: (_) => pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.1, color: PdfColors.black)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pdfBrandHeader(documentTitle: 'ZAKAAT DISBURSEMENT VOUCHER', large: false),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(width: .6),
                columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
                children: [
                  pw.TableRow(children: [
                    _receiptField('Voucher / Form No.', voucherNumber, boldValue: true),
                    _receiptField('Date', formatDate(date)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 5),
              _receiptSection('RECIPIENT DETAILS', [
                pw.Table(
                  border: pw.TableBorder.all(width: .6),
                  columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
                  children: [
                    pw.TableRow(children: [
                      _receiptField('Recipient Name', recipientName),
                      _receiptField('Phone Number', phone),
                    ]),
                    pw.TableRow(children: [
                      _receiptField('Address', address),
                      _receiptField('Aadhaar Card No.', aadhaar),
                    ]),
                  ],
                ),
              ]),
              pw.SizedBox(height: 5),
              _receiptSection('AMOUNT & PAYMENT', [
                pw.Table(
                  border: pw.TableBorder.all(width: .6),
                  columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
                  children: [
                    pw.TableRow(children: [
                      _receiptField('Amount', '\u20B9${amount.asAmount}', boldValue: true),
                      _receiptField('Amount in Words', amountInWords(amount)),
                    ]),
                    pw.TableRow(children: [
                      _receiptField('Payment Mode', paymentMode),
                      _receiptField('Cheque / Payment Reference', cheque),
                    ]),
                  ],
                ),
                pw.Table(
                  border: pw.TableBorder.all(width: .6),
                  children: [
                    pw.TableRow(children: [
                      _receiptField('Issuing Authority / Report', authority),
                    ]),
                  ],
                ),
              ]),
              if (verifiedBy1.trim().isNotEmpty || verifiedBy2.trim().isNotEmpty || verifiedBy3.trim().isNotEmpty) ...[
                pw.SizedBox(height: 5),
                _receiptSection('VERIFIED BY', [
                  pw.Table(
                    border: pw.TableBorder.all(width: .6),
                    children: [
                      pw.TableRow(children: [
                        _receiptField('Verifier 1', verifiedBy1),
                        _receiptField('Verifier 2', verifiedBy2),
                        _receiptField('Verifier 3', verifiedBy3),
                      ]),
                    ],
                  ),
                ]),
              ],
              pw.SizedBox(height: 5),
              _receiptSection('REMARKS / PARTICULARS', [
                _linedArea(remarks, lines: 2, lineHeight: 8, lineGap: 2),
              ]),
              pw.SizedBox(height: 7),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _signature('Recipient / Beneficiary Signature', recipientSignature),
                  _signature('Accountant Signature', accountantSignature),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return document;
  }

  /// Full A4 voucher for fund adjustments such as Sadqa-e-Fitr and Other Expense.
  /// Every editable database field is represented; signature fields remain signature-only.
  static pw.Document fundAdjustmentVoucherDocument({
    required String title,
    required String documentNumber,
    required DateTime date,
    required String fundLabel,
    required String party,
    String? address,
    String? aadhaar,
    String? phone,
    required double amount,
    String? chequeNumber,
    required String paymentMode,
    String? verification,
    String? verifiedBy1,
    String? verifiedBy2,
    String? verifiedBy3,
    String? remarks,
    Uint8List? recipientSignature,
    Uint8List? accountantSignature,
    String? preparedBy,
  }) {
    final document = pw.Document(theme: PdfSupport.theme);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
        build: (_) => pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.1, color: PdfColors.black)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pdfBrandHeader(documentTitle: title, large: false),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(width: .6),
                columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
                children: [
                  pw.TableRow(children: [
                    _receiptField('Voucher / Form No.', documentNumber, boldValue: true),
                    _receiptField('Date', formatDate(date)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 5),
              _receiptSection('PARTY / EXPENSE DETAILS', [
                pw.Table(
                  border: pw.TableBorder.all(width: .6),
                  columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
                  children: [
                    pw.TableRow(children: [
                      _receiptField('Fund / Account', fundLabel),
                      _receiptField('Party / Description', party),
                    ]),
                    pw.TableRow(children: [
                      _receiptField('Address', address ?? ''),
                      _receiptField('Phone Number', phone ?? ''),
                    ]),
                    pw.TableRow(children: [
                      _receiptField('Aadhaar Card No.', aadhaar ?? ''),
                      _receiptField('Payment Mode', paymentMode),
                    ]),
                  ],
                ),
              ]),
              pw.SizedBox(height: 5),
              _receiptSection('AMOUNT & PAYMENT', [
                pw.Table(
                  border: pw.TableBorder.all(width: .6),
                  columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
                  children: [
                    pw.TableRow(children: [
                      _receiptField('Amount', '\u20B9${amount.asAmount}', boldValue: true),
                      _receiptField('Amount in Words', amountInWords(amount)),
                    ]),
                    pw.TableRow(children: [
                      _receiptField('Cheque / Payment Reference', chequeNumber ?? ''),
                      _receiptField('Transaction', title),
                    ]),
                  ],
                ),
              ]),
              pw.SizedBox(height: 5),
              _receiptSection('VERIFICATION', [
                _linedArea(verification ?? '', lines: 3, lineHeight: 8, lineGap: 2),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(width: .6),
                  columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth(), 2: pw.FlexColumnWidth()},
                  children: [
                    pw.TableRow(children: [
                      _verifierCell('Verified by 1', verifiedBy1 ?? ''),
                      _verifierCell('Verified by 2', verifiedBy2 ?? ''),
                      _verifierCell('Verified by 3', verifiedBy3 ?? ''),
                    ]),
                  ],
                ),
              ]),
              pw.SizedBox(height: 5),
              _receiptSection('REMARKS / PARTICULARS', [
                _linedArea(remarks ?? '', lines: 2, lineHeight: 8, lineGap: 2),
              ]),
              pw.SizedBox(height: 7),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _signature('Recipient / Party Signature', recipientSignature),
                  _signature('Accountant Signature', accountantSignature),
                ],
              ),
              if (preparedBy != null && preparedBy.trim().isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Divider(height: 1),
                pw.Text('Prepared by: ${preparedBy.trim()}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
              ],
            ],
          ),
        ),
      ),
    );
    return document;
  }

  static pw.Widget _receiptSection(String title, List<pw.Widget> children) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: PdfColors.grey200,
        child: pw.Text(title, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ),
      ...children,
    ],
  );

  static pw.Widget _receiptField(String label, String value, {bool boldValue = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    color: PdfColors.grey100,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7.1, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 1.5),
        pw.Text(value.trim().isEmpty ? '—' : value.trim(), maxLines: 3, overflow: pw.TextOverflow.clip, style: pw.TextStyle(fontSize: 8.1, fontWeight: boldValue ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    ),
  );

  static pw.Widget _verifierCell(String label, String name) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Text(name.trim().isEmpty ? ' ' : name.trim(), textAlign: pw.TextAlign.center, maxLines: 1, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 8),
        pw.Container(width: double.infinity, height: 12, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: .4, color: PdfColors.grey700)))),
        pw.SizedBox(height: 1),
        pw.Text('Signature', style: const pw.TextStyle(fontSize: 6.5)),
      ],
    ),
  );


  /// Voucher for a Qarz waiver / written-off transaction.
  static Future<pw.Document> qarzaWaiverVoucherDocument({
    required String waiverNumber,
    required DateTime date,
    required String borrowerName,
    required String originalQarzaNumber,
    required double amount,
    required String username,
    String? remarks,
    QarzaWaiverFigures? figures,
  }) async {
    final document = pw.Document(theme: PdfSupport.theme);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.1, color: PdfColors.black)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pdfBrandHeader(documentTitle: 'QARZ WAIVER / WRITTEN-OFF VOUCHER', large: true),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(width: .6),
                columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
                children: [
                  pw.TableRow(children: [
                    _receiptField('Waiver No.', waiverNumber, boldValue: true),
                    _receiptField('Date', formatDate(date)),
                  ]),
                  pw.TableRow(children: [
                    _receiptField('Borrower / Recipient', borrowerName),
                    _receiptField('Original Qarza No.', originalQarzaNumber),
                  ]),
                  if (figures != null) ...[
                    pw.TableRow(children: [
                      _receiptField('Initial Amount Borrowed', '\u20B9${figures.borrowed.asAmount}'),
                      _receiptField('Returned So Far', '\u20B9${figures.returned.asAmount}'),
                    ]),
                    pw.TableRow(children: [
                      _receiptField('Waived Earlier', '\u20B9${figures.previouslyWaived.asAmount}'),
                      _receiptField('Amount Waived (This Voucher)', '\u20B9${amount.asAmount}', boldValue: true),
                    ]),
                    pw.TableRow(children: [
                      _receiptField('Balance After Waiver', '\u20B9${figures.balanceAfter.asAmount}', boldValue: true),
                      _receiptField('Amount Waived in Words', amountInWords(amount)),
                    ]),
                  ] else
                    pw.TableRow(children: [
                      _receiptField('Amount Waived', '\u20B9${amount.asAmount}', boldValue: true),
                      _receiptField('Amount in Words', amountInWords(amount)),
                    ]),
                ],
              ),
              pw.SizedBox(height: 8),
              _receiptSection('REMARKS / JUSTIFICATION', [
                _linedArea(remarks ?? '', lines: 4, lineHeight: 9, lineGap: 2),
              ]),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _signature('Borrower / Recipient Signature', null),
                  _signature('Accountant Signature', null),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(height: 1),
              pw.Text('Prepared by: $username', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
            ],
          ),
        ),
      ),
    );
    return document;
  }

}
