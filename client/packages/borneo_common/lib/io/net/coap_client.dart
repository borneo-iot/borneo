import 'dart:async';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:coap/coap.dart';
import 'package:cbor/simple.dart' as simple_cbor;

class CoapException extends IOException {
  final String message;
  final CoapResponse response;
  CoapException(this.message, this.response);

  @override
  String toString() => message;
}

extension CoapClientExtensions on CoapClient {
  /// Sends a GET request to the given [uri] and decodes the CBOR response payload as type [T].
  /// Throws [CoapException] if the response is not successful.
  Future<T> getCbor<T>(Uri uri, {bool confirmable = true, CancellationToken? cancelToken}) async {
    final response = await get(
      uri,
      accept: CoapMediaType.applicationCbor,
      confirmable: confirmable,
    ).asCancellable(cancelToken);
    if (!response.isSuccess) {
      throw CoapException("Failed to request uri (${response.code} - '${response.codeString}') `$uri`", response);
    }
    final cborPayload = simple_cbor.cbor.decode(response.payload) as T;
    return cborPayload;
  }

  /// Observes the given [uri] using a confirmable CoAP GET request and yields each CBOR-decoded payload as type [T].
  /// Errors during decoding are emitted as stream errors.
  Stream<T> observeCbor<T>(Uri uri, {CancellationToken? cancelToken}) async* {
    final request = CoapRequest.get(uri, accept: CoapMediaType.applicationCbor);
    final obs = await observe(request, maxRetransmit: 3).asCancellable(cancelToken);
    try {
      await for (final rep in obs) {
        try {
          yield simple_cbor.cbor.decode(rep.payload) as T;
        } catch (e, st) {
          yield* Stream<T>.error(e, st);
        }
      }
    } catch (e, st) {
      yield* Stream<T>.error(e, st);
    }
  }

  /// Observes the given [uri] using a non-confirmable CoAP GET request and yields each CBOR-decoded payload as type [T].
  /// Errors during decoding are emitted as stream errors.
  Stream<T> observeCborNon<T>(Uri uri, {CancellationToken? cancelToken}) async* {
    final request = CoapRequest(
      uri,
      RequestMethod.get,
      accept: CoapMediaType.applicationCbor,
      confirmable: false,
      contentFormat: CoapMediaType.applicationCbor,
    );
    final obs = await observe(request, maxRetransmit: 3).asCancellable(cancelToken);

    try {
      await for (final rep in obs) {
        try {
          yield simple_cbor.cbor.decode(rep.payload) as T;
        } catch (e, st) {
          yield* Stream<T>.error(e, st);
        }
      }
    } catch (e, st) {
      yield* Stream<T>.error(e, st);
    }
  }

  /// Sends a PUT request with CBOR-encoded [payload] to the given [uri].
  /// Throws [CoapException] if the response is not successful.
  Future<void> putCbor<T>(Uri uri, T payload, {bool confirmable = true, CancellationToken? cancelToken}) async {
    final bytes = simple_cbor.cbor.encode(payload);
    final response = await putBytes(
      uri,
      payload: bytes,
      accept: CoapMediaType.applicationCbor,
      format: CoapMediaType.applicationCbor,
      confirmable: confirmable,
    ).asCancellable(cancelToken);
    if (!response.isSuccess) {
      throw CoapException(
        "Failed to put uri `$uri`, payload: `$payload` (${response.code} - '${response.codeString}')",
        response,
      );
    }
  }

  /// Sends a POST request with CBOR-encoded [payload] to the given [uri].
  /// Throws [CoapException] if the response is not successful.
  Future<void> postCbor<T>(Uri uri, T payload, {bool confirmable = true, CancellationToken? cancelToken}) async {
    final bytes = simple_cbor.cbor.encode(payload);
    final response = await postBytes(
      uri,
      payload: bytes,
      accept: CoapMediaType.applicationCbor,
      format: CoapMediaType.applicationCbor,
      confirmable: confirmable,
    ).asCancellable(cancelToken);
    if (!response.isSuccess) {
      throw CoapException("Failed to post uri `$uri` (${response.code} - '${response.codeString}')", response);
    }
  }
}
