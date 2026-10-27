mkdir -p /phinaow

export HOME="/phinaow"

export PATH="$HOME/.venv/bin:$PATH"

if [ ! -d "$HOME/.venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$HOME/.venv"
    "$HOME/.venv/bin/pip" install -r /phinaow/requirements.txt
fi

export PATH="$HOME/.venv/bin:$PATH"

export HISTCONTROL=ignoredups
export HISTFILE="$HOME/.bash_history"
export HISTFILESIZE=100000
export HISTSIZE=1000

# PS1="(phinaow) \$(pwd) \\$ "

PS1='|*|\[\e[1;0m\](\[\e[1;94m\]phinaow\[\e[1;0m\])---[\[\e[1;94m\]\w\[\e[1;0m\]]\n └─> \[\e[1;0m\]'

