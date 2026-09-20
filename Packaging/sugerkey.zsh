_sugerkey() {
    local -a commands
    commands=(
        'key:Choose the physical Hyper key'
        'add:Capture a Hyper shortcut and choose an application'
        'info:Show version, Hyper key, and bindings'
        'version:Show the installed version'
        'help:Show available commands'
    )

    if (( CURRENT == 2 )); then
        _describe 'command' commands
    else
        _message 'no more arguments'
    fi
}

autoload -Uz compinit
if (( ! $+functions[compdef] )); then
    compinit
fi
compdef _sugerkey sugerkey
