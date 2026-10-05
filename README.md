# <img src="Packaging/AppIcon.png" alt="Kvinta icon" width="30" height="30"> Kvinta

Kvinta is a menu-bar macOS utility that uses one physical modifier as Hyper and toggles applications with Hyper shortcuts.

## Install locally

```sh
./scripts/install.sh
```

The installer places the app in `~/Applications/Kvinta.app`, links the CLI at `~/.local/bin/kvinta`, registers the daemon with launchd, and enables Zsh command completion in new terminal sessions.

A stable code-signing identity is required so macOS preserves Accessibility permission across updates. The installer uses the first available code-signing identity, or one provided through `KVINTA_SIGNING_IDENTITY`.

Then configure and use Kvinta with:

```sh
kvinta key
kvinta add
kvinta info
kvinta start
kvinta reload
kvinta --version
```

macOS will request Accessibility permission for keyboard interception. Configuration is stored in `~/.config/kvinta/config.toml`.

You can also edit `~/.config/kvinta/config.toml` manually. After saving your changes, run `kvinta reload` to load the new configuration.

Use `kvinta start` to start a stopped daemon. If it is already running, start leaves its configuration and pause state unchanged. Opening Kvinta from Spotlight or Finder uses the same start behavior. `kvinta reload` applies configuration changes and also starts the daemon if it is stopped.

Use `kvinta stop` or its alias `kvinta quit` to request graceful shutdown from Terminal, just like **Quit Kvinta** in the menu bar. If the stop request cannot be sent, the command reports an error. Run `kvinta start` to start it again; it also starts at the next login.

## Pause or quit with the mouse

Click the Kvinta icon in the menu bar to open Kvinta’s menu. Choose **Pause** to disable keyboard interception, **Resume** to enable it again, or **Quit Kvinta** to stop the daemon. The icon has a green checkmark badge when shortcuts are active and a gray pause badge when interception is disabled.

A user pause stays in effect until you choose Resume, including during configuration reloads and after shortcut capture finishes. Restarting the daemon starts a new active session. After quitting, run `kvinta start` in Terminal, open Kvinta from Spotlight, or open `~/Applications/Kvinta.app` in Finder to start it again. These entry points use the same launchd-managed daemon. It also starts at the next login.

If Kvinta blocks typing, use the menu with the mouse to pause or quit. If the entire process becomes unresponsive and the menu cannot open, use Activity Monitor to force quit `kvinta`.
