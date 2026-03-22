// dart format width=120

import 'package:borneo_kernel_abstractions/driver.dart';

abstract class BaseLyfiDriver extends Driver {
  const BaseLyfiDriver({super.logger});

  // Removed createWotAdapter method - WotThing is now managed by application layer
}
