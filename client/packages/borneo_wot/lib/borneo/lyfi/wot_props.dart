import 'package:borneo_common/collections/collection_extensions.dart';
import 'package:lw_wot/wot.dart';

class ReadonlyLyfiColorProperty extends WotProperty<List<int>> {
  ReadonlyLyfiColorProperty({required super.thing, required super.name, WotPropertyMetadata? metadata})
    : super(
        value: WotValue<List<int>>(
          initialValue: [], // Default all off
          valueForwarder: (_) => throw UnsupportedError('`$name` is read-only'),
          equality: (a, b) => a.isEqualTo(b),
        ),
        metadata: WotPropertyMetadata(
          type: 'array',
          title: metadata?.title ?? name,
          description: metadata?.description ?? '',
          readOnly: true,
        ),
      );
}

class MutableLyfiColorProperty extends WotProperty<List<int>> {
  MutableLyfiColorProperty({
    required super.thing,
    required super.name,
    required WotForwarder<List<int>> valueForwarder,
    WotPropertyMetadata? metadata,
  }) : super(
         value: WotValue<List<int>>(
           initialValue: [], // Default all off
           valueForwarder: valueForwarder,
           equality: (a, b) => a.isEqualTo(b),
         ),
         metadata: WotPropertyMetadata(
           type: 'array',
           title: metadata?.title ?? name,
           description: metadata?.description ?? '',
           readOnly: false,
         ),
       );
}

final class LyfiOutputProperty extends WotProperty<List<int>> {
  LyfiOutputProperty({required super.thing, required super.name, WotPropertyMetadata? metadata})
    : super(
        value: WotValue<List<int>>(
          initialValue: [], // Default all off
          valueForwarder: (_) => throw UnsupportedError('`$name` is read-only'),
          equality: (a, b) => a.isEqualTo(b),
        ),
        metadata: WotPropertyMetadata(
          type: 'array',
          title: metadata?.title ?? name,
          description: metadata?.description ?? '',
          readOnly: true,
        ),
      );
}
