import 'package:excel/excel.dart';

/// Converts an uploaded .xlsx file's bytes into a plain-text table
/// representation the agent can read like any other text attachment --
/// one section per sheet, rows as pipe-separated cell values.
String excelBytesToText(List<int> bytes) {
  final workbook = Excel.decodeBytes(bytes);

  final sections = <String>[];
  for (final entry in workbook.tables.entries) {
    final sheetName = entry.key;
    final sheet = entry.value;
    final lines = <String>[];
    for (final row in sheet.rows) {
      final cells = row.map((cell) => cell?.value?.toString() ?? '').toList();
      if (cells.every((c) => c.isEmpty)) continue;
      lines.add(cells.join(' | '));
    }
    if (lines.isEmpty) continue;
    sections.add('[Sheet: $sheetName]\n${lines.join('\n')}');
  }

  return sections.isEmpty ? '(empty spreadsheet)' : sections.join('\n\n');
}
