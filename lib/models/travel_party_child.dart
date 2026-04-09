import 'package:flutter/material.dart';

/// One minor in the travel party (signup): name, age, gender only.
class TravelPartyChildRowControllers {
  TravelPartyChildRowControllers();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  String? gender;

  void dispose() {
    nameController.dispose();
    ageController.dispose();
  }
}
