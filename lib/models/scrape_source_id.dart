enum ScrapeSourceId {
  javbus('javbus'),
  avbase('avbase'),
  avwiki('avwiki');

  const ScrapeSourceId(this.storageValue);

  final String storageValue;
}
