#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
build_app="$project_dir/.build/Kvinta.app"
install_app="$HOME/Applications/Kvinta.app"
cli_dir="$HOME/.local/bin"
config_dir="$HOME/.config/kvinta"
completion_file="$config_dir/completion.zsh"
zshrc="${ZDOTDIR:-$HOME}/.zshrc"
launch_agents_dir="$HOME/Library/LaunchAgents"
launch_agent="$launch_agents_dir/com.sargisabovyan.kvinta.daemon.plist"
launch_domain="gui/$(id -u)"
launch_label="com.sargisabovyan.kvinta.daemon"
signing_identity="${KVINTA_SIGNING_IDENTITY:-}"

if [[ -z "$signing_identity" ]]; then
    signing_identities="$(security find-identity -v -p codesigning)"
    if [[ "$signing_identities" =~ '"([^"]+)"' ]]; then
        signing_identity="$match[1]"
    else
        print -u2 "A stable code-signing identity is required for persistent Accessibility permission."
        print -u2 "Create an Apple Development certificate in Xcode or set KVINTA_SIGNING_IDENTITY."
        exit 1
    fi
fi

swift build --package-path "$project_dir" -c release

launchctl bootout "$launch_domain/$launch_label" 2>/dev/null || true

mkdir -p "$config_dir"
chmod 700 "$config_dir"

rm -rf "$build_app"
mkdir -p "$build_app/Contents/MacOS"
cp "$project_dir/.build/release/kvinta" "$build_app/Contents/MacOS/kvinta"
cp "$project_dir/Packaging/Info.plist" "$build_app/Contents/Info.plist"
codesign --force --sign "$signing_identity" "$build_app"

mkdir -p "$HOME/Applications" "$cli_dir" "$launch_agents_dir" "$HOME/Library/Logs" "$config_dir"
rm -rf "$install_app"
cp -R "$build_app" "$install_app"
ln -sfn "$install_app/Contents/MacOS/kvinta" "$cli_dir/kvinta"
cp "$project_dir/Packaging/kvinta.zsh" "$completion_file"

completion_line='[ -s "$HOME/.config/kvinta/completion.zsh" ] && source "$HOME/.config/kvinta/completion.zsh"'
if [[ ! -f "$zshrc" || "$(<"$zshrc")" != *"$completion_line"* ]]; then
    print >> "$zshrc"
    print '# Kvinta shell completion' >> "$zshrc"
    print -r -- "$completion_line" >> "$zshrc"
fi

cat > "$launch_agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$launch_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$install_app/Contents/MacOS/kvinta</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Kvinta.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Kvinta.log</string>
</dict>
</plist>
PLIST

plutil -lint "$install_app/Contents/Info.plist" >/dev/null
plutil -lint "$launch_agent" >/dev/null
launchctl bootstrap "$launch_domain" "$launch_agent"

print "Installed Kvinta.app in $HOME/Applications."
print "Signed with: $signing_identity"
print "The 'kvinta' command is available at $cli_dir/kvinta."
print "Zsh completion is installed. Open a new terminal or run 'source ~/.zshrc' to enable it."
if [[ ":$PATH:" != *":$cli_dir:"* ]]; then
    print "Add $cli_dir to PATH before using the command."
fi
print "Run 'kvinta key' to grant permission and configure Hyper."
