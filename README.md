# Sugerkey

Sugerkey is a headless macOS utility that uses one physical modifier as Hyper and toggles applications with Hyper shortcuts.

## Install locally

```sh
./scripts/install.sh
```

The installer places the headless app in `~/Applications/Sugerkey.app`, links the CLI at `~/.local/bin/sugerkey`, and registers the daemon with launchd.

A stable code-signing identity is required so macOS preserves Accessibility permission across updates. The installer uses the first available code-signing identity, or one provided through `SUGERKEY_SIGNING_IDENTITY`.

Then configure and use Sugerkey with:

```sh
sugerkey key
sugerkey add
sugerkey info
sugerkey --version
```

macOS will request Accessibility permission for keyboard interception. Configuration is stored in `~/.config/sugerkey/config.toml`.
