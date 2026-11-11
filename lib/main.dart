// =============================================================
// main.dart
// Vstupní bod aplikace StepSense.
// Jeho jediným úkolem je spustit aplikaci a zobrazit hlavní obrazovku.
// Veškerá logika je v lib/services a veškeré UI v lib/screens.
// =============================================================
 
import 'package:flutter/material.dart';
import 'screens/track_screen.dart';
 
// main() je první funkce, kterou Dart spustí.
// runApp() vezme widget a udělá z něj kořen celé aplikace.
void main() => runApp(const MaterialApp(
      // Skryje červený štítek "DEBUG" v rohu obrazovky.
      debugShowCheckedModeBanner: false,
      // Úvodní obrazovka: mapa, trasa a statistiky aktivity.
      home: TrackScreen(),
    ));
 
