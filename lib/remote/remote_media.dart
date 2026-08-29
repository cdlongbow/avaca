import 'dart:typed_data';

import 'remote_errors.dart';
import 'remote_limits.dart';

class RemoteResourceId {
  RemoteResourceId(List<int> bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.isEmpty || bytes.length > RemoteLimits.maxResourceIdBytes) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'opaque resource id is outside the configured bound',
      );
    }
  }

  final Uint8List bytes;
}

class RemoteByteRange {
  const RemoteByteRange({required this.offset, required this.length});

  final int offset;
  final int length;

  void validate({required int resourceLength}) {
    if (offset < 0 ||
        length < 0 ||
        length > RemoteLimits.maxReadBytes ||
        resourceLength < 0 ||
        offset > resourceLength ||
        length > resourceLength - offset) {
      throw const RemoteException(
        RemoteFailureCode.rangeInvalid,
        'byte range is outside the resource or configured limit',
      );
    }
  }
}

class RemoteResourceHandle {
  const RemoteResourceHandle({required this.token, required this.length});

  final Object token;
  final int length;
}

class RemoteReadResult {
  RemoteReadResult({
    required this.offset,
    required List<int> bytes,
    required this.eof,
  }) : bytes = Uint8List.fromList(bytes);

  final int offset;
  final Uint8List bytes;
  final bool eof;
}

/// Resources are addressed only by opaque identifiers. This interface has no
/// path, drive, UNC, directory, SQL, or shell operation by design.
abstract interface class RemoteMediaSource {
  Future<RemoteResourceHandle> open(RemoteResourceId resourceId);
  Future<RemoteReadResult> read(
    RemoteResourceHandle handle,
    RemoteByteRange range,
  );
  Future<void> close(RemoteResourceHandle handle);
}

class UnavailableRemoteMediaSource implements RemoteMediaSource {
  const UnavailableRemoteMediaSource();

  @override
  Future<RemoteResourceHandle> open(RemoteResourceId resourceId) async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'no production media source is enabled in this phase',
    );
  }

  @override
  Future<RemoteReadResult> read(
    RemoteResourceHandle handle,
    RemoteByteRange range,
  ) async {
    throw const RemoteException(
      RemoteFailureCode.unsupported,
      'no production media source is enabled in this phase',
    );
  }

  @override
  Future<void> close(RemoteResourceHandle handle) async {}
}

class RemoteResourceService {
  const RemoteResourceService(this.source);

  final RemoteMediaSource source;

  Future<RemoteResourceHandle> open(RemoteResourceId resourceId) =>
      source.open(resourceId);

  Future<RemoteReadResult> read(
    RemoteResourceHandle handle,
    RemoteByteRange range,
  ) {
    range.validate(resourceLength: handle.length);
    return source.read(handle, range).then((result) {
      if (result.offset != range.offset ||
          result.bytes.length > range.length ||
          result.bytes.length > RemoteLimits.maxReadBytes ||
          (range.length == 0 && result.bytes.isNotEmpty)) {
        throw const RemoteException(
          RemoteFailureCode.internal,
          'media source returned a result outside the requested range',
        );
      }
      final expectedEof = range.offset + result.bytes.length >= handle.length;
      if (result.eof != expectedEof) {
        throw const RemoteException(
          RemoteFailureCode.internal,
          'media source returned an inconsistent EOF marker',
        );
      }
      return result;
    });
  }

  Future<void> close(RemoteResourceHandle handle) => source.close(handle);
}
