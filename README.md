# KakuTra

Assistant macOS de traduction au curseur. KakuTra reconnaît localement le japonais, le chinois et le coréen, puis traduit le texte pris en charge vers l’anglais avec Apple Translation.

## Parcours

Appuyez une ou deux fois sur le raccourci configuré :

- **Une fois** : suivre et traduire le mot sous le curseur.
- **Deux fois** : traduire visuellement les lignes OCR japonaises, chinoises et coréennes de l’écran sous le curseur. Les autres langues sont ignorées. Appuyez sur Échap pour arrêter ce mode.

Survolez le titre du résultat pour afficher sa transcription latine : romaji depuis la lecture du dictionnaire japonais, pinyin pour le chinois et romanisation coréenne.

Un seul mode est actif à la fois. Sur un appui simple, la version Direct peut lire une sélection existante près du curseur et la traduire comme une phrase; sinon, comme la version App Store, elle suit le parcours OCR du mot. Le double appui utilise l’OCR dans les deux versions.

Le mode actif et le geste de changement sont rappelés dans le menu de la barre des menus. En mode écran, l’image de l’écran sous le curseur est relue périodiquement; les traductions sont placées sur les blocs reconnus. Une traduction absente ou en échec laisse le texte source visible.

## Fonctions

- OCR local avec Vision et traduction avec le framework Translation d’Apple.
- Définitions depuis les bases SQLite japonaises, chinoises et coréennes présentes dans `~/Library/Application Support/KakuTra/Dictionaries`.
- Prononciation avec les voix Apple.
- Ajout volontaire d’une carte à Anki via AnkiConnect depuis un résultat affiché. Les recherches ne sont pas enregistrées dans l’application.
- Langue d’interface configurable indépendamment des langues de traduction.

## Configuration requise

- macOS 14 ou ultérieur ; la traduction système nécessite macOS 15 ou ultérieur.
- Autorisation Enregistrement de l’écran pour l’OCR du mot et la traduction visuelle de l’écran.
- Dans la version Direct, l’autorisation Accessibilité est facultative : elle permet de lire une sélection existante pour un appui simple ; sans elle, l’OCR reste utilisé.
- Anki et AnkiConnect uniquement pour ajouter des cartes.

## Compiler

Ouvrez `KakuTra Translator.xcodeproj` dans Xcode ou utilisez :

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
```

Licence MIT.
