if [[ "${BASH_PROFILE_DEBUG:-false}" = 'true' ]]; then
  {
    echo ".bash_profile"
    =============
    echo "args: $*"
    echo "args (set): $-"
    env
    echo "----------"
  } >> /tmp/.bash-debug-${UID-}.log
fi
if [[ "${BASH_PROFILE_IGNORE_NON_INTERACTIVE:-true}" = 'true' ]] && ! [[ $- == *i* ]]; then
  # Don't include the rest of the code if it's a non-interactive profile.
  return
fi
# Load the shell dotfiles, and then some:
# * ~/.path can be used to extend `$PATH`.
# * ~/.extra can be used for other settings you don’t want to commit.
for file in ~/.{init,var,functions,functions_install,functions_wsl,path,brew,bash_prompt,historyrc,bash_ssh,bash-powerline-ng,exports,aliases,extra}; do
  # Usage of "." over "source" here ensures that variables from a previous import are accessible by a later one.
  [ -r "$file" ] && [ -f "$file" ] && . "$file"
  # Attempt to pick up local overrides.
  [ -r "$file.local" ] && [ -f "$file.local" ] && . "$file.local"
done
unset file

if [ -z "${ZSH:-}" ] && [ -f "${BASH_SOURCE[0]%/*}/.bash_preexec.sh" ]; then
  # shellcheck source=.bash_preexec.sh
  source "${BASH_SOURCE[0]%/*}/.bash_preexec.sh"
  # Load the preexec.local script.
  # shellcheck disable=SC1090
  [ -r ~/.preexec.local ] && [ -f ~/.preexec.local ] && . ~/.preexec.local
  # echo "preexec_functions = ${preexec_functions[*]}"
  # echo "precmd_functions = ${precmd_functions[*]}"
fi

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Case-insensitive globbing (used in pathname expansion)
shopt -s nocaseglob

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# Append to the Bash history file, rather than overwriting it
shopt -s histappend

# Autocorrect typos in path names when using `cd`
shopt -s cdspell

# Enable some Bash 4 features when possible:
# * `autocd`, e.g. `**/qux` will enter `./foo/bar/baz/qux`
# * Recursive globbing, e.g. `echo **/*.txt`
for option in autocd globstar; do
  shopt -s "$option" 2>/dev/null
done

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
  if test -r ~/.dircolors; then
    eval "$(dircolors -b ~/.dircolors)"
  else
    eval "$(dircolors -b)"
  fi
  alias ls='ls --color=auto'
  #alias dir='dir --color=auto'
  #alias vdir='vdir --color=auto'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

# Add tab completion for many Bash commands
if which brew &>/dev/null && [ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]; then
  # Ensure existing Homebrew v1 completions continue to work
  export BASH_COMPLETION_COMPAT_DIR="$(brew --prefix)/etc/bash_completion.d"
  source "$(brew --prefix)/etc/profile.d/bash_completion.sh"
elif [ -f /etc/bash_completion ]; then
  source /etc/bash_completion
fi

# Enable tab completion for `g` by marking it as an alias for `git`
if type _git &>/dev/null; then
  complete -o default -o nospace -F _git g
fi

# Add tab completion for SSH hostnames based on ~/.ssh/config, ignoring wildcards
[ -e "$HOME/.ssh/config" ] && complete -o "default" -o "nospace" -W "$(grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2- | tr ' ' '\n')" scp sftp ssh

# Add tab completion for `defaults read|write NSGlobalDomain`
# You could just use `-g` instead, but I like being explicit
complete -W "NSGlobalDomain" defaults

# Add `killall` tab completion for common apps
complete -o "nospace" -W "Contacts Calendar Dock Finder Mail Safari iTunes SystemUIServer Terminal Twitter" killall
