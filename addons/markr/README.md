<!-- markdownlint-disable MD033 MD041 -->
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="wordmark.png">
  <img src="wordmark-on-light.png" alt="Markr" width="360">
</picture>
<!-- markdownlint-enable MD033 MD041 -->

Build a world marker sequence, drop it from one hotkey, and switch presets when the plan
changes.

## Default hotkeys

| Key | Action |
| --- | --- |
| `Shift+G` | Place the next marker in the sequence |
| `Ctrl+G` | Clear all world markers |
| _unbound_ | Restart the sequence from the first marker |

These are claimed on first run only, and only if the key is free; anything you have already
bound is left alone. Set your own in `/markr` or in Blizzard's Key Bindings panel under the
**Markr** header.

## Commands

```
/markr                 open the settings window
/markr list            list your presets
/markr use <name>      switch the active preset
/markr reset           restart the sequence at the first marker
/markr help            command list
```

## Settings

Open the window with `/markr`, the minimap button, the addon compartment, or
**Options → AddOns → Markr**. From there you can:

- **Presets**: create, duplicate, rename and delete presets, and pick which one the hotkey
  uses. Presets are saved account-wide.
- **Sequence**: click a marker to switch it on or off, drag to reorder. The hotkey walks the
  strip left to right, skipping the disabled ones, and wraps around at the end.
- **Placement**: drop instantly at the mouse cursor, or arm Blizzard's placement reticle and
  click where you want it. Chat announcements toggle here too.
- **Hotkeys**: click a binding button and press the key you want.

## License

[MIT](../../LICENSE.md)
