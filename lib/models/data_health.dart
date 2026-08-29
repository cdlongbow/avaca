class DataHealthSnapshot {
  const DataHealthSnapshot({
    required this.generatedAt,
    required this.actressCount,
    required this.workCount,
    required this.storedWorkCount,
    required this.notStoredWorkCount,
    required this.missingReleaseDateCount,
    required this.missingStudioCount,
    required this.missingPublisherCount,
    required this.missingSeriesCount,
    required this.missingCardImageCount,
    required this.missingDetailImageCount,
    required this.missingProvenanceCount,
    required this.pendingDeletionCount,
    this.libraryWorkCount = 0,
    this.libraryMediaIssueCount = 0,
    this.importRepairCount = 0,
    this.libraryLinkIssueCount = 0,
    this.warnings = const [],
  });

  final DateTime generatedAt;
  final int actressCount;
  final int workCount;
  final int storedWorkCount;
  final int notStoredWorkCount;
  final int missingReleaseDateCount;
  final int missingStudioCount;
  final int missingPublisherCount;
  final int missingSeriesCount;
  final int missingCardImageCount;
  final int missingDetailImageCount;
  final int missingProvenanceCount;
  final int pendingDeletionCount;
  final int libraryWorkCount;
  final int libraryMediaIssueCount;
  final int importRepairCount;
  final int libraryLinkIssueCount;
  final List<String> warnings;

  double get storedRatio => workCount == 0 ? 0 : storedWorkCount / workCount;

  int get metadataIssueCount =>
      missingReleaseDateCount +
      missingStudioCount +
      missingPublisherCount +
      missingSeriesCount;
}
