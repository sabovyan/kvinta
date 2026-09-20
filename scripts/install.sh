#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
build_app="$project_dir/.build/Sugerkey.app"
install_app="$HOME/Applications/Sugerkey.app"
cli_dir="$HOME/.local/bin"
completion_file="$HOME/.config/sugerkey/completion.zsh"
zshrc="${ZDOTDIR:-$HOME}/.zshrc"
launch_agents_dir="$HOME/Library/LaunchAgents"
launch_agent="$launch_agents_dir/com.sargisabovyan.sugerkey.daemon.plist"
launch_domain="gui/$(id -u)"
launch_label="com.sargisabovyan.sugerkey.daemon"
legacy_launch_label="com.sugerkey.daemon"
legacy_launch_agent="$launch_agents_dir/$legacy_launch_label.plist"
signing_identity="${SUGERKEY_SIGNING_IDENTITY:-}"

if [[ -z "$signing_identity" ]]; then
    signing_identities="$(security find-identity -v -p codesigning)"
    if [[ "$signing_identities" =~ '"([^"]+)"' ]]; then
        signing_identity="$match[1]"
    else
        print -u2 "A stable code-signing identity is required for persistent Accessibility permission."
        print -u2 "Create an Apple Development certificate in Xcode or set SUGERKEY_SIGNING_IDENTITY."
        exit 1
    fi
fi

swift build --package-path "$project_dir" -c release

launchctl bootout "$launch_domain/$launch_label" 2>/dev/null || true
launchctl bootout "$launch_domain/$legacy_launch_label" 2>/dev/null || true
rm -f "$legacy_launch_agent"
rm -f "$HOME/.config/sugerkey/daemon.pid"

rm -rf "$build_app"
mkdir -p "$build_app/Contents/MacOS"
cp "$project_dir/.build/release/sugerkey" "$build_app/Contents/MacOS/sugerkey"
cp "$project_dir/Packaging/Info.plist" "$build_app/Contents/Info.plist"
codesign --force --sign "$signing_identity" "$build_app"

mkdir -p "$HOME/Applications" "$cli_dir" "$launch_agents_dir" "$HOME/Library/Logs" "${completion_file:h}"
rm -rf "$install_app"
cp -R "$build_app" "$install_app"
ln -sfn "$install_app/Contents/MacOS/sugerkey" "$cli_dir/sugerkey"
cp "$project_dir/Packaging/sugerkey.zsh" "$completion_file"

completion_line='[ -s "$HOME/.config/sugerkey/completion.zsh" ] && source "$HOME/.config/sugerkey/completion.zsh"'
if [[ ! -f "$zshrc" || "$(<"$zshrc")" != *"$completion_line"* ]]; then
    print >> "$zshrc"
    print '# Sugerkey shell completion' >> "$zshrc"
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
        <string>$install_app/Contents/MacOS/sugerkey</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Sugerkey.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Sugerkey.log</string>
</dict>
</plist>
PLIST

plutil -lint "$install_app/Contents/Info.plist" >/dev/null
plutil -lint "$launch_agent" >/dev/null
launchctl bootstrap "$launch_domain" "$launch_agent"

print "Installed Sugerkey.app in $HOME/Applications."
print "Signed with: $signing_identity"
print "The 'sugerkey' command is available at $cli_dir/sugerkey."
print "Zsh completion is installed. Open a new terminal to enable it."
if [[ ":$PATH:" != *":$cli_dir:"* ]]; then
    print "Add $cli_dir to PATH before using the command."
fi
print "Run 'sugerkey key' to grant permission and configure Hyper."
