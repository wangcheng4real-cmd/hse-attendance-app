import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/inspection_record.dart';
import 'photo_store.dart';

class ExportResult {
  const ExportResult(this.file, this.missingPhotos);
  final File file;
  final int missingPhotos;
}

class ExcelExporter {
  ExcelExporter(this._photoStore);
  final PhotoStore _photoStore;

  Uint8List buildWorkbookForTesting(List<InspectionRecord> records) =>
      _buildWorkbook(records, const []);

  Future<ExportResult> export(
    List<InspectionRecord> records,
    String inspector,
  ) async {
    final safeName = inspector.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filename =
        '${safeName}_${DateFormat('yyyyMMddHHmm').format(DateTime.now())}_安全员在岗履职情况表.xlsx';
    final images = <_Image>[];
    var missing = 0;
    for (var row = 0; row < records.length; row++) {
      for (var slot = 0; slot < records[row].photoPaths.length; slot++) {
        final file = await _photoStore.resolve(records[row].photoPaths[slot]);
        if (!await file.exists()) {
          missing++;
          continue;
        }
        images.add(_Image(row + 2, slot, await file.readAsBytes()));
      }
    }
    final bytes = _buildWorkbook(records, images);
    final tempFile = File(p.join(Directory.systemTemp.path, filename));
    await tempFile.writeAsBytes(bytes, flush: true);
    final exportDir = Directory(
      p.join(await getDatabasesPath(), 'hse_files', 'exports'),
    );
    await exportDir.create(recursive: true);
    final fallback = File(p.join(exportDir.path, filename));
    await fallback.writeAsBytes(bytes, flush: true);
    return ExportResult(fallback, missing);
  }

  Uint8List _buildWorkbook(
    List<InspectionRecord> records,
    List<_Image> images,
  ) {
    final archive = Archive();
    void addText(String name, String value) {
      final data = utf8.encode(value);
      archive.addFile(ArchiveFile(name, data.length, data));
    }

    addText('[Content_Types].xml', _contentTypes(images));
    addText(
      '_rels/.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
    );
    addText(
      'xl/workbook.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="在岗检查明细" sheetId="1" r:id="rId1"/></sheets></workbook>''',
    );
    addText(
      'xl/_rels/workbook.xml.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''',
    );
    addText('xl/styles.xml', _styles);
    addText('xl/worksheets/sheet1.xml', _sheet(records, images.isNotEmpty));
    if (images.isNotEmpty) {
      addText(
        'xl/worksheets/_rels/sheet1.xml.rels',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>''',
      );
      addText('xl/drawings/drawing1.xml', _drawing(images));
      addText('xl/drawings/_rels/drawing1.xml.rels', _drawingRels(images));
      for (var i = 0; i < images.length; i++) {
        archive.addFile(
          ArchiveFile(
            'xl/media/image${i + 1}.jpg',
            images[i].bytes.length,
            images[i].bytes,
          ),
        );
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  String _contentTypes(List<_Image> images) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${images.isEmpty ? '' : '<Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'}<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''';

  String _sheet(List<InspectionRecord> records, bool hasImages) {
    const headers = [
      '序号',
      '施工单位',
      '检查区域',
      '班次',
      '检查时间',
      '报送安全人员数量',
      '安全人员是否全部在岗',
      '打卡照片',
      '缺岗情况描述',
      '改进行动',
    ];
    final rows = StringBuffer();
    rows.write(
      '<row r="1" ht="30" customHeight="1"><c r="A1" s="1" t="inlineStr"><is><t>施工单位现场安全人员在岗验证检查表</t></is></c></row>',
    );
    rows.write('<row r="2" ht="32" customHeight="1">');
    for (var i = 0; i < headers.length; i++) {
      rows.write(_cell('${_column(i)}2', headers[i], 2));
    }
    rows.write('</row>');
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final row = i + 3;
      final height = r.photoPaths.isEmpty ? 34 : 86;
      final values = [
        '${i + 1}',
        r.contractor,
        r.area,
        r.shift,
        DateFormat('yyyy-MM-dd HH:mm').format(r.inspectedAt),
        '${r.reportedCount}',
        r.allPresent ? '是' : '否',
        r.photoPaths.isEmpty ? '' : '照片${r.photoPaths.length}张',
        r.absenceDescription,
        r.improvementAction,
      ];
      rows.write('<row r="$row" ht="$height" customHeight="1">');
      for (var c = 0; c < values.length; c++) {
        rows.write(
          _cell(
            '${_column(c)}$row',
            values[c],
            c == 0 || c == 3 || c == 5 || c == 6 ? 3 : 4,
          ),
        );
      }
      rows.write('</row>');
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="7" customWidth="1"/><col min="2" max="3" width="20" customWidth="1"/><col min="4" max="4" width="9" customWidth="1"/><col min="5" max="5" width="19" customWidth="1"/><col min="6" max="7" width="16" customWidth="1"/><col min="8" max="8" width="38" customWidth="1"/><col min="9" max="10" width="28" customWidth="1"/></cols><sheetData>$rows</sheetData><mergeCells count="1"><mergeCell ref="A1:J1"/></mergeCells><autoFilter ref="A2:J${records.length + 2}"/>${hasImages ? '<drawing r:id="rId1"/>' : ''}</worksheet>''';
  }

  String _cell(String ref, String value, int style) =>
      '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_xml(value)}</t></is></c>';
  String _column(int index) => String.fromCharCode(65 + index);
  String _xml(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);

  String _drawing(List<_Image> images) {
    final body = StringBuffer();
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      body.write(
        '''<xdr:oneCellAnchor><xdr:from><xdr:col>7</xdr:col><xdr:colOff>${image.slot * 1080000 + 50000}</xdr:colOff><xdr:row>${image.row}</xdr:row><xdr:rowOff>50000</xdr:rowOff></xdr:from><xdr:ext cx="1000000" cy="1000000"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="${i + 2}" name="打卡照片${i + 1}"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" r:embed="rId${i + 1}"/><a:stretch xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:off x="0" y="0"/><a:ext cx="1000000" cy="1000000"/></a:xfrm><a:prstGeom xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>''',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">$body</xdr:wsDr>';
  }

  String _drawingRels(List<_Image> images) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(images.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image${i + 1}.jpg"/>').join()}</Relationships>';
}

class _Image {
  const _Image(this.row, this.slot, this.bytes);
  final int row;
  final int slot;
  final Uint8List bytes;
}

const _styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="等线"/></font><font><b/><sz val="16"/><name val="等线"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="等线"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1F4E78"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border/><border><left style="thin"><color rgb="FFB7C9D6"/></left><right style="thin"><color rgb="FFB7C9D6"/></right><top style="thin"><color rgb="FFB7C9D6"/></top><bottom style="thin"><color rgb="FFB7C9D6"/></bottom></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''';
