// Generates a QR code per knowledge base content, encoding its external
// reference code (ERC), plus a printable contact sheet.
//
//   dart run tool/qr_codes.dart [--out build/qr]
//
// Output: build/qr/<ERC>.png (QR + ERC + title) and build/qr/index.html.
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:northstar_kb/data/liferay_client.dart';
import 'package:qr/qr.dart';

// Same list as lib/data/content_types.dart (which depends on Flutter).
const _types = {
  'nmgproducts': 'Products',
  'nmgsupportarticles': 'Support Articles',
  'nmgknownissues': 'Known Issues',
  'nmgfaqs': 'FAQs',
  'nmgprocedures': 'Procedures',
  'nmgtechspecs': 'Technical Specs',
  'nmgreleasenotes': 'Release Notes',
  'nmgpolicies': 'Policies',
  'nmgcorporatearticles': 'Corporate News',
  'nmgcustomercases': 'Customer Cases',
  'nmgsalesplaybooks': 'Sales Playbooks',
};

Future<void> main(List<String> args) async {
  final i = args.indexOf('--out');
  final out = Directory(i >= 0 ? args[i + 1] : 'build/qr')..createSync(recursive: true);
  final config = jsonDecode(File('config/liferay.json').readAsStringSync()) as Map;
  final client = LiferayClient(
    resolve: (p) => Uri.parse('${config['LIFERAY_TARGET']}$p'),
    clientId: config['OAUTH_CLIENT_ID'] as String,
    clientSecret: config['OAUTH_CLIENT_SECRET'] as String,
  );

  final html = StringBuffer('''<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>Northstar KB QR codes</title><style>
body{font-family:system-ui,sans-serif;margin:24px;color:#0b3d5c}
h2{margin-top:32px;border-bottom:2px solid #0b6e99}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:16px}
figure{margin:0;text-align:center;break-inside:avoid}
img{width:100%;border:1px solid #ddd}
</style></head><body><h1>Northstar Enterprise Knowledge — content QR codes</h1>''');
  var count = 0;
  for (final MapEntry(key: path, value: label) in _types.entries) {
    final entries = await client.fetchAllEntries(path,
        spaceErc: config['SPACE_ERC'] as String,
        fields: 'externalReferenceCode,title');
    entries.sort((a, b) =>
        '${a['externalReferenceCode']}'.compareTo('${b['externalReferenceCode']}'));
    html.write('<h2>$label (${entries.length})</h2><div class="grid">');
    for (final e in entries) {
      final erc = e['externalReferenceCode'] as String;
      final title = e['title'] as String? ?? '';
      File('${out.path}/$erc.png').writeAsBytesSync(img.encodePng(qrCard(erc, title)));
      html.write('<figure><img src="${Uri.encodeComponent(erc)}.png" alt="$erc">'
          '</figure>');
      count++;
    }
    html.write('</div>');
  }
  html.write('</body></html>');
  File('${out.path}/index.html').writeAsStringSync(html.toString());
  client.close();
  stdout.writeln('$count QR codes written to ${out.path}');
}

/// A white card: the QR code of [erc], the ERC in clear and the title.
img.Image qrCard(String erc, String title) {
  final qr = QrImage(QrCode.fromData(
      data: erc, errorCorrectLevel: QrErrorCorrectLevel.M));
  const scale = 14, quiet = 4, width = 600;
  final qrPx = (qr.moduleCount + 2 * quiet) * scale;
  final card = img.Image(width: width, height: qrPx + 130, numChannels: 3)
    ..clear(img.ColorRgb8(255, 255, 255));
  final left = (width - qrPx) ~/ 2;
  for (var y = 0; y < qr.moduleCount; y++) {
    for (var x = 0; x < qr.moduleCount; x++) {
      if (qr.isDark(y, x)) {
        img.fillRect(card,
            x1: left + (x + quiet) * scale,
            y1: (y + quiet) * scale,
            x2: left + (x + quiet + 1) * scale - 1,
            y2: (y + quiet + 1) * scale - 1,
            color: img.ColorRgb8(0, 0, 0));
      }
    }
  }
  final ascii = title.replaceAll(RegExp(r'[^\x20-\x7E]'), '-');
  final shortTitle = ascii.length > 44 ? '${ascii.substring(0, 42)}...' : ascii;
  img.drawString(card, erc,
      font: img.arial48, x: 20, y: qrPx, color: img.ColorRgb8(11, 61, 92));
  img.drawString(card, shortTitle,
      font: img.arial24, x: 20, y: qrPx + 70, color: img.ColorRgb8(60, 60, 60));
  return card;
}
