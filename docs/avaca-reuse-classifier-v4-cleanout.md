# AVACA reuse classifier V4 legacy cleanout

Operation: `avaca-reuse-classifier-avwiki-clean-v4-20260826`

Expected base: `dbac3dbb5b53c4b16d6b840bf804086a7e46647f`

This report records the implementation-side cleanout for the V4 work
provenance classifier. It is evidence for independent review; it is not a
Gate 2 approval.

## A. Active decision path

The new works path is now:

`enabled catalogs -> ordered catalog union -> typed identity/family resolution -> clean canonical code -> primary detail -> semantic reuse classifier -> conditional source escalation -> KEEP/REVIEW/EXCLUDE -> one canonical save`

All enabled works catalogs are collected before identity selection. Source
priority now selects the primary detail and evidence order; it does not hide
coverage from lower-priority catalogs or override a semantic conflict.

## B. Legacy active semantics removed

The following signals no longer cause an automatic exclusion, review, or
identity collapse on a new scrape:

- unknown or missing provenance;
- performer count, performer identity, cast count, runtime, or cast-plus-runtime;
- `independentSegments` by itself;
- bare or generic prefix/managed-family blacklist matches;
- editing, complete, unreleased, anniversary, special, no-cut, multi-angle,
  collection, or numeric tokens without a concrete reuse proposition;
- multi-actress presentation or several acts/numbers by itself;
- source priority as a substitute for semantic evidence;
- no-signal and missing-detail assumptions that treated uncertainty as reuse.

The invariant is now explicit in the evaluator: no reuse signal means
`KEEP`; uncertainty is not proof that the product reuses prior AV material.
Independent segments are weak neutral context unless the source separately
declares reused segments or a package of prior works.

## C. Compatibility retained deliberately

Legacy decoders and presentation/image consumers remain available for old
stored jobs, old database rows, image routing, and display compatibility.
The legacy `work_code_canonicalizer.dart` and `scrapeWorkStorageCode` helper
are not used to decide identity in the new catalog/detail pipeline. New
storage uses `scrapeWorkCanonicalStorageCode` after typed identity resolution.

AV-Wiki is metadata/provenance only and declares no image URI capability.
Existing image routes remain governed by the established image policy.

## D. Call-chain evidence

The implementation call sites can be rechecked with:

```text
rg -n "canonicalizeWorkCode|work_code_canonicalizer|scrapeWorkStorageCode" lib/services/works_scrape_service.dart
```

The expected result is no active legacy call in
`lib/services/works_scrape_service.dart`; compatibility definitions may still
appear in `lib/services/scrape/work_identity.dart` and legacy consumers.

The new identity calls are:

- `scrapeWorkIdentityKeyForSummary` during catalog union;
- `scrapeWorkIdentityKeyForDetails` and typed candidate evidence during detail
  validation;
- `scrapeWorkCanonicalStorageCode` immediately before persistence;
- `ScrapeExclusionPolicyEvaluator.evaluate` only after detail evidence has
  been collected.

## E. Identity and source boundaries

SOD-scoped `START`/`STARS` edition forms support the observed `V`, `T`, `VT`,
`VT2-EC`, and `STARSBD` relationships only with the required maker/label
context. Generic `FOO-123-EC`, numeric-prefix removal, global BD/V/VT/EC
stripping, zero trimming, or broad prefix grammar is not applied.

The `START-164` / `107START-164` / `1start00164` bridge is accepted only when
the same source declares the typed maker/platform identity. Distinct forms
such as `SIVR00303` and `SIVR-303` remain distinct without a trusted bridge.

## F. Offline regression evidence

`test/fixtures/scrape_classifier_v4_corpus.json` contains nine named actress
records, 162 decisive cases, one source-conflict ambiguity, and 19 identity
family labels. The corresponding test calculates decisive accuracy, false
exclude rate, false keep rate, and review rate from the fixture instead of
hard-coding a single aggregate result.

AV-Wiki fixtures cover actress search, aliases, pagination, duplicate URI
dedupe, zero results, malformed pages, wrong-code rejection, platform IDs,
partial page diagnostics, cancellation, and HTTPS/host safety.

## G. Verification limits

Focused Flutter tests and targeted analysis are run sequentially on Windows.
Flutter/Dart telemetry cleanup messages such as `PathAccessException` are
classified as environment diagnostics, not test or source evidence. Real
Windows and Android UI evidence must still be recorded separately; widget
tests and goldens do not substitute for platform interaction evidence.

## H. Review handoff

This cleanout report, source diff, focused tests, full-suite result, and
platform evidence are inputs to the independent GPT-5.6 Sol High review.
The implementation agent must not self-approve Gate 2. Release, tag, and push
remain out of scope for this operation.
