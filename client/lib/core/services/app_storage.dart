import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> getAppSupportDataDirectory() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return directory;
}
