# Kvinta

Kvinta is a headless macOS utility that uses one physical modifier as Hyper and toggles applications with Hyper shortcuts.

## Install locally

```sh
./scripts/install.sh
```

The installer places the headless app in `~/Applications/Kvinta.app`, links the CLI at `~/.local/bin/kvinta`, registers the daemon with launchd, and enables Zsh command completion in new terminal sessions.

A stable code-signing identity is required so macOS preserves Accessibility permission across updates. The installer uses the first available code-signing identity, or one provided through `KVINTA_SIGNING_IDENTITY`.

Then configure and use Kvinta with:

```sh
kvinta key
kvinta add
kvinta info
kvinta --version
```

macOS will request Accessibility permission for keyboard interception. Configuration is stored in `~/.config/kvinta/config.toml`.
