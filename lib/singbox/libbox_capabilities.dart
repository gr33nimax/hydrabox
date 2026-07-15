enum UrlTestCompletionModel { rpcCompletion, groupEvents }

/// Describes what the bundled libbox build actually supports.
///
/// Keep this client-side until the future core exposes a versioned capability
/// handshake. It lets the Flutter layer avoid pretending that parameters are
/// supported merely because they are already present in the Pigeon request.
class LibboxCapabilities {
  const LibboxCapabilities({
    required this.supportsTargetedUrlTest,
    required this.supportsUrlTestTimeout,
    required this.supportsUrlTestConcurrency,
    required this.supportsUrlTestDeadline,
    required this.supportsUrlTestForce,
    required this.urlTestCompletionModel,
  });

  static const bundledLegacy = LibboxCapabilities(
    supportsTargetedUrlTest: false,
    supportsUrlTestTimeout: false,
    supportsUrlTestConcurrency: false,
    supportsUrlTestDeadline: false,
    supportsUrlTestForce: false,
    urlTestCompletionModel: UrlTestCompletionModel.groupEvents,
  );

  final bool supportsTargetedUrlTest;
  final bool supportsUrlTestTimeout;
  final bool supportsUrlTestConcurrency;
  final bool supportsUrlTestDeadline;
  final bool supportsUrlTestForce;
  final UrlTestCompletionModel urlTestCompletionModel;
}
