# LangSwapper

A macOS menu-bar app that fixes words typed on the wrong keyboard layout
(`้ำสสน` → `hello`, `l;ylfu` → `สวัสดี`) and switches the layout for you.
It supports English (ABC/US) and Thai.

## Build and run

Requires macOS 13 or later and Xcode command-line tools.

```bash
./scripts/build-app.sh           # downloads word lists, builds build/LangSwapper.app
open build/LangSwapper.app       # grant Accessibility access when asked
swift run LangSwapper --selftest # detector checks against this Mac's real layouts
swift run LangSwapper --eval 5000 # fix rate and false changes on the 5000 most common words
```

Enable both an English layout (ABC or US) and the Thai layout in System Settings → Keyboard → Input Sources.

The build is ad-hoc signed by default, so macOS drops Accessibility access
after each rebuild. To keep it, sign with a stable certificate:
`SIGN_IDENTITY="Your Cert Name" ./scripts/build-app.sh`. If corrections stop, remove LangSwapper from
System Settings → Privacy & Security → Accessibility and add it again.

## Using it

- **Fixing a word:** type it on the wrong layout and press Space, Return or Tab. The word is retyped on the right layout, and the keyboard switches to that layout.
- **Undo:** press Backspace or ⌘Z right after a fix. LangSwapper won't fix that word again.
- **Convert now:** press ⌃⌥Space to convert the current word whatever the detector thinks.
- **Menu options:**
  - **Disable in \<App\>:** turns LangSwapper off for the front app.
  - **Match layout to each app:** switching to an app selects the language you usually type there. This starts after 20 words and needs a 75% majority.
  - **Open at login.**
- **Never converted:** tech names (`git`, `api`, `json`…). In terminals and code editors, shell commands are not converted either.
- **Field check:** before rewriting, LangSwapper reads the focused field through the Accessibility API and checks that it ends with the typed word. If it doesn't (autocomplete, a moved cursor), the fix is skipped. Apps that don't expose their text fall back to the keystroke buffer.

## How it works

1. A `CGEventTap` records each key press as a physical key code plus Shift, not as a character.
2. When a word ends, the key presses are re-rendered on every enabled layout. The layouts are read with `TISCopyInputSourceForLanguage` and `UCKeyTranslate`.
3. Each rendering is scored against a word-frequency list. Thai has no spaces between words, so it is scored by how much of it splits into dictionary words, plus checks that reject impossible vowel and tone-mark orders.
4. If the typed text isn't a word and another rendering is a confident one, the word is erased with Backspace and retyped as Unicode. Then the layout is switched with `TISSelectInputSource`.

Code layout:

| Path | What's in it |
|---|---|
| `Sources/LangSwapperCore` | Platform-free logic: layout maps, dictionaries, scoring, app categories, per-app language counts |
| `Sources/LangSwapper` | The app: event tap, input sources, Accessibility checks, menu, settings |

Local data lives in `~/Library/Application Support/LangSwapper/`:
`ignoredWords.json` (words you undid) and `appLanguageCounts.json`.

## Privacy

Everything runs on your Mac. LangSwapper keeps only the current word in memory.
It does not log or send keystrokes, and it pauses in secure input fields such as
password boxes.

## Roadmap

- Use the surrounding words to settle ambiguous short words (`so`/`หน`, `ok`/`นา`).
- Detect Thai mid-phrase, before a space is typed.
- Learn the user's own vocabulary.
- Remember the language per website in browsers.
- Add more languages.

## Credits and license

The code is MIT-licensed; see [LICENSE](LICENSE).

The word lists are not part of this repository. `scripts/build-app.sh`
downloads them from [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords),
whose content is licensed CC BY-SA 4.0. If you redistribute a built app, include
that attribution.
