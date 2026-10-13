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
| Nástroje | Android Studio, VS Code, Git & GitHub, Figma |

## Jak se počítá převýšení a kalorie

- Z GPS (případně barometru) se zaznamenává nadmořská výška, data se vyhlazují, aby šum nezkresloval výsledek.
- Sčítají se zvlášť metry nahoru a dolů.
- Kalorie vycházejí z hodnoty MET podle typu pohybu a přičítá se k nim energie za překonané převýšení, takže stejná trasa do kopce vyjde náročnější než po rovině.

## Pitný režim

- Základní denní cíl se odvozuje z váhy uživatele.
- K cíli se přičítá doporučený příjem podle délky a náročnosti aktivity (včetně převýšení).
- Uživatel jedním klepnutím přidá vypitou sklenici, láhev nebo vlastní množství.
- Přehled zobrazuje splnění denního cíle a historii.
