# Desktop Goose 🪿

A goose walks around your Windows desktop. It steals your cursor, drags windows by their title bars, brings you sticky notes, tracks mud everywhere, and naps while you type.

It's a single PowerShell script, so there's nothing to install.

## Run it

1. Download `goose.ps1`, either with **Code → Download ZIP** or with:
   ```
   git clone https://github.com/NoraMeeker/DesktopGoose.git
   ```
2. In PowerShell, from the folder that contains the script, run:
   ```
   powershell -ExecutionPolicy Bypass -File goose.ps1
   ```
   You need `-ExecutionPolicy Bypass` because Windows blocks downloaded scripts by default.

Requires Windows. It runs on the built-in Windows PowerShell, so you don't need to install anything else.

## Controls

| Keys | What it does |
|------|--------------|
| Ctrl+Shift+G | Send the goose home (quit) |
| Ctrl+Shift+O | Open settings |
| Ctrl+Shift+F | Challenge the goose to a duel (only if Knife is on in settings) |
| Hold any mouse button | Make it let go of whatever it has |

You can also right-click the tray icon to open settings or send the goose home.

Settings are saved in `%APPDATA%\GooseOnTheLoose\settings.ini`. To change the messages on the sticky notes, edit `notes.txt` in the same folder.

## License

MIT. See [LICENSE](LICENSE).
