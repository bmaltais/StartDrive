# How Omarchy loads this plugin

Facts about the host that the code depends on and that no file here says. Each was read from Omarchy's own source (`/usr/share/omarchy/shell/shell.qml`, `shell/services/PluginRegistry.qml`, `bin/omarchy-plugin-*`), so check there first if Omarchy has changed.

## Enabled means listed

A plugin is enabled when its id appears in `~/.config/omarchy/shell.json`, either in a bar layout section (`bar.layout.left|center|right`) or in the `plugins` array (`PluginRegistry.isEnabled`, `findEntryLocation`). Nothing else enables it. A bar widget that was enabled is listed only in the layout, so removing it from the layout leaves no entry that enables its **service**. That is why `lib/prefs.sh` (`BAR_REMOVE_JQ`) adds the id to `plugins` whenever it takes the icon off the bar, and why `tests/cli.sh` checks it.

## What loads, and when

| Change | What picks it up |
|---|---|
| QML or JS edited in the plugin folder | Only a full shell restart (`omarchy restart shell`). The shell logs "Local plugin changed, reloading", and a `keepLoaded` service keeps running the old code. `omarchy plugin disable` and `enable` do not load new QML either |
| `manifest.json` edited (kinds, entry points) | `omarchy-shell shell rescanPlugins` first, then the restart |
| A service (`kinds` has `service`, with an `entryPoints.service`) | Loaded once the plugin is enabled; `keepLoaded: true` makes it survive a hot reload. It answers `omarchy-shell <id> <function>` after it loads, a moment after the shell itself answers `omarchy-shell shell ping`, so wait for it (`scripts/reload` polls `state`, `DEVKIT_RELOAD_READY` in `devkit.conf`) |

## The plugins folder is scanned

The shell scans **every folder** under `~/.config/omarchy/plugins/` (`PluginRegistry`, the `scanProcess` over `pluginsDir`). A backup or a second copy kept there is read as another plugin with the same id and logs "Module path ... is outside of the config folder". Keep backups elsewhere (`scripts/reload` uses `~/.local/share/startdrive-dev/`). A plugin folder may not contain symlinks, and the watcher does not follow them.

## Installed copy versus clone

`omarchy plugin add <git url>` installs a git clone, and `omarchy plugin update` only touches folders that have a `.git` (`omarchy-plugin-update` skips the rest). A developer's install is usually a plain copy of the checkout, which `omarchy plugin update` therefore ignores and `scripts/reload` refreshes. Run `ls -d ~/.config/omarchy/plugins/io.github.bmaltais.startdrive/.git` to tell which one is installed before assuming a clone: this has been assumed wrongly, and the user kept seeing the old UI.

## Changing the bar

`omarchy-shell-config` (sourced by `lib/prefs.sh`) edits `shell.json` with a jq program run after its `NORMALIZE`, writes it atomically, and asks the shell to reload its config. The reload can restart a plugin part-way through the process that asked, so the bar change is the last thing `startdrive setup` does.
