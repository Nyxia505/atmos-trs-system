// This is a basic Flutter widget test for ATMOS TRS System.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atmos_trs_system/screens/login_screen.dart';

void main() {
  testWidgets('Login Screen UI Test', (WidgetTester tester) async {
    // Build our login screen
    await tester.pumpWidget(const MaterialApp(
      home: LoginScreen(),
    ));

    // Verify that ATMOS TRS title is present
    expect(find.text('ATMOS TRS'), findsOneWidget);
    
    // Verify that subtitle is present
    expect(find.text('Asenso Turismo Registration System'), findsOneWidget);
    
    // Verify that welcome message is present
    expect(find.text('Welcome Back!'), findsOneWidget);
    
    // Verify that sign in text is present
    expect(find.text('Sign in to continue to your account'), findsOneWidget);
    
    // Verify that email field is present
    expect(find.text('Email Address'), findsOneWidget);
    
    // Verify that password field is present
    expect(find.text('Password'), findsOneWidget);
    
    // Verify that sign in button is present
    expect(find.text('Sign In'), findsOneWidget);
    
    // Verify that sign up link is present
    expect(find.text('Sign Up'), findsOneWidget);
  });
}
