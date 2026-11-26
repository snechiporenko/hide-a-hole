# hide-a-hole

A native macOS utility that draws a black backdrop behind the menu bar. It lets clicks pass through and adds a configurable gradient around the cursor. The backdrop uses the menu bar's original height without an offset. It collapses toward the center when the menu bar uses a light appearance (typically dark icons), and expands from the center when it uses a dark appearance (typically light icons). Appearance is inferred from a one-point-wide status item and may not match custom-colored icons or every display. If macOS changes the status-item layout, the item may occupy its normal width.

## Usage

From the project directory:

```sh
swift run hide-a-hole help                      # show command-line help
swift run hide-a-hole install                   # install and start at login
swift run hide-a-hole status                    # check registration in the current session
swift run hide-a-hole uninstall                 # stop and remove from login items
swift run hide-a-hole cursor-color '#00000000'  # transparent center
swift run hide-a-hole cursor-color '#FF000080'  # semi-transparent red center
swift run hide-a-hole cursor-color '#000000FF'  # solid black backdrop
swift run hide-a-hole cursor-radius 150         # radius in macOS points
```

Run `swift run hide-a-hole` without arguments to start manually; press Ctrl+C to stop. Avoid running it manually while the service is active. The utility has no window or Dock icon. Its backdrop height may be incorrect when the menu bar is set to hide automatically.

Installation copies the executable to `~/Library/Application Support/hide-a-hole/` and creates a per-user LaunchAgent in `~/Library/LaunchAgents/`. Run `install` again to update and restart the service. It starts after the current user logs in and does not require administrator privileges.

## Configuration

Settings are stored in `~/Library/Application Support/hide-a-hole/config.json`:

```json
{
  "cursorColor": "#00000000",
  "cursorRadius": 100
}
```

`cursorColor` uses `#RRGGBBAA`: the final two digits set opacity from `00` (fully transparent) to `FF` (fully opaque). The center blends into opaque black at the edge. If the file or setting is missing, the center defaults to transparent.

`cursorRadius` is a number from 1 to 10000 macOS points and can be fractional. The default is 100. The legacy `holeEnabled` setting retains its previous behavior until a color is set.

The commands create the file if needed. Changes, including manual edits, are applied within one second. If the JSON is invalid, the running process retains its last valid settings and commands do not overwrite the file. Uninstalling the service preserves the configuration.
