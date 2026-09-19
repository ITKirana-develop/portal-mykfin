// Basic smoke test untuk K-Portal.
//
// Test ini cuma memastikan app bisa di-build tanpa error (render
// HomeScreen pertama kali), bukan test fungsional detail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:portal_mykfin_flutter/main.dart';

void main() {
  testWidgets('K-Portal app builds without error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const KPortalApp());

    // Pastikan judul header utama muncul.
    expect(find.text('Portal MyKFIN'), findsOneWidget);
  });
}
