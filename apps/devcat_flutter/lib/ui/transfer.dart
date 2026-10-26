import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportText(
  BuildContext context,
  Directory dataDirectory,
  String name,
  String text,
) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final folder = Directory('${dataDirectory.path}/exports');
    await folder.create(recursive: true);
    final file = File('${folder.path}/$name');
    await file.writeAsString(text, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: name),
    );
  } else {
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return;
    await File(location.path).writeAsString(text, flush: true);
  }
}
