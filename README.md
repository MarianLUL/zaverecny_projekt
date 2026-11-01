# StepSense

Mobilní aplikace ve Flutteru pro sledování pohybové aktivity a pitného režimu. Počítá kroky, vzdálenost, **převýšení**, spálené kalorie a doporučuje denní příjem tekutin podle aktivity. Projekt vzniká jako **maturitní práce**.

## Hlavní funkce

- **Počítání kroků** z akcelerometru (peak detection + low-pass filtr)
- **Vzdálenost** z GPS, při jeho nedostupnosti odhad podle délky kroku
- **Převýšení** (nastoupané a sestoupané metry) z nadmořské výšky GPS, případně barometru
- **Kalorie** podle váhy, věku, výšky, typu pohybu, doby aktivity a MET, upravené o převýšení (chůze do kopce spaluje víc)
- **Pitný režim**: zapisování vypitých tekutin, denní cíl podle váhy a aktivity, přehled splnění cíle
- **Historie a statistiky** uložené v lokální databázi

## Použité technologie

| Kategorie | Technologie |
|-----------|-------------|
| Jazyky | Dart, SQL, Markdown |
| Framework | Flutter (Material Design) |
| Senzory | `sensors_plus` (akcelerometr, barometr), `geolocator` (GPS a nadmořská výška) |
| Data | `sqflite` (SQLite), `shared_preferences` (profil a nastavení) |
| Ostatní knihovny | `provider` (stav aplikace), `fl_chart` (grafy), `permission_handler` (oprávnění) |
| Nástroje | VS Code, Git & GitHub, Figma |

# Aktuální zpracování
Můj dosavadní projekt používá senzory v telefonu na vypočítání kroků, ale problém je v jeho zaznamení je moc citliví a zatím nepoužívá tracking GPS. 
V Budoucnu přidám vššechny ostatní funkce.

## Požadavky
- Flutter SDK, Android Studio (Android SDK + JDK 17), Git
- Windows: zapnutý Developer Mode
- Android telefon se zapnutým laděním USB (doporučeno)

## Spuštění
git clone https://github.com/<tvoje-jmeno>/stepsense.git
cd stepsense
flutter doctor --android-licenses
flutter pub get
flutter run

## Řešení problémů
- Chyba `different roots` (Windows): nastavte PUB_CACHE na stejný disk jako projekt.
- Zařízení nenalezeno: zkontrolujte datový kabel a ladění USB (`adb devices`).


