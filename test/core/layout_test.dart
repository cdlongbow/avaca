import 'package:avaca/core/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLayoutPolicy', () {
    test('uses compact below the measured boundary', () {
      expect(
        AppLayoutPolicy.resolve(
          const BoxConstraints.tightFor(width: 671),
        ).layoutClass,
        AppLayoutClass.compact,
      );
    });

    test('uses expanded at and above the measured boundary', () {
      expect(
        AppLayoutPolicy.resolve(
          const BoxConstraints.tightFor(width: 672),
        ).layoutClass,
        AppLayoutClass.expanded,
      );
      expect(
        AppLayoutPolicy.resolve(
          const BoxConstraints.tightFor(width: 673),
        ).layoutClass,
        AppLayoutClass.expanded,
      );
    });

    test('column calculation is constraint driven and bounded', () {
      final compact = AppLayoutPolicy.resolve(
        const BoxConstraints.tightFor(width: 390),
      );
      final expanded = AppLayoutPolicy.resolve(
        const BoxConstraints.tightFor(width: 1280),
      );

      expect(
        compact.columnsForWidth(
          390,
          minItemWidth: compact.homeCardMinWidth,
          minColumns: 3,
          maxColumns: 9,
        ),
        3,
      );
      expect(
        expanded.columnsForWidth(
          844,
          minItemWidth: expanded.homeCardMinWidth,
          minColumns: 3,
          maxColumns: 9,
        ),
        6,
      );
      expect(
        expanded.columnsForWidth(
          1280,
          minItemWidth: expanded.homeCardMinWidth,
          minColumns: 3,
          maxColumns: 9,
        ),
        9,
      );
    });

    test('detail modes use intrinsic rail requirements', () {
      final tokens = AppLayoutPolicy.resolve(
        const BoxConstraints.tightFor(width: 1280),
      );

      expect(tokens.detailIntermediateRequiredRail(1), 644);
      expect(tokens.detailWideRequiredRail(1), 1028);
      expect(tokens.detailWideRequiredRail(1.25), 1208);
      expect(tokens.canUseIntermediateDetail(882, 1.25), isTrue);
      expect(tokens.canUseWideDetail(882, 1.25), isFalse);
      expect(tokens.canUseWideDetail(1232, 1.25), isTrue);
    });

    test('grid geometry caps density and centres sparse collections', () {
      final compact = AppLayoutPolicy.resolve(
        const BoxConstraints.tightFor(width: 390),
      );
      final expanded = AppLayoutPolicy.resolve(
        const BoxConstraints.tightFor(width: 1280),
      );

      final home = expanded.gridGeometry(
        availableWidth: 1280,
        minItemWidth: expanded.homeCardMinWidth,
        maxItemWidth: expanded.homeCardMaxWidth,
        itemCount: 12,
        maxUsefulColumns: expanded.homeMaxUsefulColumns,
      );
      final works = expanded.gridGeometry(
        availableWidth: 1280,
        minItemWidth: expanded.workCardMinWidth,
        maxItemWidth: expanded.workCardMaxWidth,
        itemCount: 3,
        maxUsefulColumns: expanded.workMaxUsefulColumns,
      );
      final compactWorks = compact.gridGeometry(
        availableWidth: 390,
        minItemWidth: compact.workCardMinWidth,
        maxItemWidth: compact.workCardMaxWidth,
        itemCount: 3,
        maxUsefulColumns: compact.workMaxUsefulColumns,
      );

      expect(home.columns, 4);
      expect(home.itemWidth, 220);
      expect(home.railWidth, 910);
      expect(works.columns, 3);
      expect(works.itemWidth, 240);
      expect(works.railWidth, 740);
      expect(compactWorks.columns, 2);
    });
  });
}
