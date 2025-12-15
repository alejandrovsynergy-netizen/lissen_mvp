import 'dart:io';

void main() async {
  final libDir = Directory('lib');

  if (!libDir.existsSync()) {
    print('❌ No se encontró la carpeta lib/');
    return;
  }

  final output = StringBuffer();
  output.writeln('// ===============================');
  output.writeln('// EXPORTACIÓN COMPLETA DE LISSEN');
  output.writeln('// Generado automáticamente');
  output.writeln('// ===============================\n\n');

  void scanDir(Directory dir) {
    final entities = dir.listSync(recursive: false);

    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final relativePath = entity.path.replaceAll('\\', '/');
        output.writeln('/// ===== ARCHIVO: $relativePath =====\n');
        output.writeln(entity.readAsStringSync());
        output.writeln('\n\n');
      } else if (entity is Directory) {
        scanDir(entity);
      }
    }
  }

  scanDir(libDir);

  final outFile = File('lissen_export.txt');
  outFile.writeAsStringSync(output.toString(), flush: true);

  print('✅ Exportación completa.');
  print('📄 Archivo generado: lissen_export.txt');
}
