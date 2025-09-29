#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE}")"

(return 0 2>/dev/null) && IS_SCRIPT_SOURCED=1 || IS_SCRIPT_SOURCED=0

if [ "$IS_SCRIPT_SOURCED" = 0 ]; then
  # saner programming env when not sourced: these switches turn some bugs into errors
  # Switching it on during source can break certain
  set -o errexit -o pipefail -o noclobber -o nounset
fi

function _exitCleanly() {
  unset doIt doItRsync doItFiles runMain
  if [ "$IS_SCRIPT_SOURCED" = 1 ]; then
    # The script is sourced, don't exit.
    return "$@"
  fi
  echo "exit cleanly!!! $@">> /tmp/debug.txt
  unset _exitCleanly
  # The script is not sourced, exit.
  exit "$@"
}

function doItRsync() {
  local symlink="$1"
  local backup="${2:-0}"
  local dryrun="${3:-0}"

  rsync \
    "$@" \
    --dry-run \
    --exclude ".git/" \
    --exclude ".dotfiles/" \
    --exclude ".dotfiles-bak/" \
    --exclude ".idea" \
    --exclude ".vscode" \
    --exclude ".DS_Store" \
    --exclude ".osx" \
    # todo test this
    --exclude '.*.local' \
    --exclude '.gitkeep' \
    --exclude "bootstrap.sh" \
    --exclude "README.md" \
    --exclude "LICENSE-MIT.txt" \
    -avh --no-perms . ~
}

function doItFiles() {
  local symlink="$1"
  local backup="${2:-0}"
  local dryrun="${3:-0}"
  local current_dir dotfiles_source
  local file relative_file_path relative_dir_path target_file target_dir backup_dir

  current_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

  dotfiles_source="${current_dir}"
  backup_dir="$dotfiles_source/.dotfiles-bak/$(date +"%Y%m%d_%H.%M.%S")"
  while read -r file; do
    relative_file_path="${file#"${dotfiles_source}"/}"
    relative_dir_path="${relative_file_path%/*}"
    if [ "$relative_dir_path" = "$relative_file_path" ]; then
      relative_dir_path=""
    fi
    target_file="${HOME}/${relative_file_path}"
    target_dir="${target_file%/*}"

    if [ "$backup" = 1 ] && test -f "${target_file}" && [ "$(realpath "$target_file")" != "$file" ]; then
      # Back up the regular script file before it's replaced.
      if [ "$dryrun" = 1 ]; then
        echo "[dry-run] Backing up: ${target_file} -> ${backup_dir}/${relative_file_path}"
      else
        mkdir -p "${backup_dir}/${relative_dir_path}"
        \cp -a "${target_file}" "${backup_dir}/${relative_file_path}"
      fi
    fi

    if [ "$dryrun" = 0 ] && test ! -d "${target_dir}"; then
      mkdir -p "${target_dir}"
    fi
    if [ "$symlink" = 1 ]; then
      if [ "$dryrun" = 1 ]; then
        printf '[dry-run] Installing symlink: %s -> %s\n' "${file}" "${target_file}"
      else
        printf 'Installing symlink %s\n' "${target_file}"
        ln -sf "${file}" "${target_file}"
      fi
    else
      if [ "$dryrun" = 1 ]; then
        printf '[dry-run] Copying file: %s -> %s\n' "${file}" "${target_file}"
      else
        printf 'Copying file %s\n' "${target_file}"
        \cp -af "${file}" "${target_file}"
      fi
    fi

  done < <(
    find "${dotfiles_source}" -type f,l \
      -not -path "${dotfiles_source}/.git/*" \
      -not -path "${dotfiles_source}/.dotfiles/*" \
      -not -path "${dotfiles_source}/.dotfiles-bak/*" \
      -not -path "${dotfiles_source}/.idea/*" \
      -not -path "${dotfiles_source}/.vscode/*" \
      -not -path "${dotfiles_source}/.DS_Store" \
      -not -path "${dotfiles_source}/*/.gitkeep" \
      -not -path "${dotfiles_source}/.*.local" \
      -not -path "${dotfiles_source}/.osx" \
      -not -path "${dotfiles_source}/bootstrap.sh" \
      -not -path "${dotfiles_source}/README.md" \
      -not -path "${dotfiles_source}/LICENSE-MIT.txt" \
      -print | sort
  )
}

function doIt() {
  local symlink="$1"
  local backup="${2:-0}"
  local dryrun="${3:-0}"
  doItFiles "$symlink" "$backup" "$dryrun"
  if [ -f ~/.bash_profile ]; then
    # shellcheck source=.bash_profile
    source ~/.bash_profile
  fi
}

function testIt() {
  local args="${*@Q} --no-backup --force --testing"
  local username='app'
  local promptPrefix
  local HOST_UID HOST_GID
  HOST_UID=$(id -u)
  HOST_GID=$(id -g)
  local containerBinary='';
  if command -v "docker" &> /dev/null; then
    containerBinary="docker"
  elif command -v "podman" &> /dev/null; then
    containerBinary="podman"
  else
    echo -e \"=== Please install docker or podman in order to test the environment. \033[1;32mexit\033[0m command to leave debug workspace\";
    return _exitCleanly 1
  fi

  promptPrefix=$(
    cat <<'PREFIX'
PROMPT_COMMAND_ORIGINAL="$PROMPT_COMMAND"
function dotfile_debug_workspace_prompt() {
  printf "[debug-workspace] "
  if command -v "$PROMPT_COMMAND_ORIGINAL" &> /dev/null; then
    "$PROMPT_COMMAND_ORIGINAL";
  else
    printf "$PROMPT_COMMAND_ORIGINAL";
  fi
}
PROMPT_COMMAND="dotfile_debug_workspace_prompt"
PREFIX
  )

  local current_dir
  current_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

  local docker_run_args=(--net=host --rm -it)
  docker_run_args+=(-v "$current_dir:/home/$username/.dotfiles")
  docker_run_args+=(-w "/home/$username/.dotfiles")

  # Docker 17.05 and up supports HEREDOCS.
  # https://regex101.com/r/Yq3R2T/1
  if [[ "$containerBinary" = docker ]] && [[ "$(docker --version)" =~ (version ((1[8-9])|17\.[1-9]|17\.0\.[5-9]|[2-9])) ]]; then
    $containerBinary build \
      --build-arg HOST_UID="$HOST_UID" --build-arg HOST_GID="$HOST_GID" --build-arg HOST_USERNAME="$username" \
      -t dotfiles_bootstrap_temp:latest - <<'EOF'
FROM bash:latest
ARG HOST_UID
ARG HOST_GID
ARG HOST_USERNAME

RUN addgroup -g "$HOST_GID" "$HOST_USERNAME" && \
  adduser -u "$HOST_UID" -G "$HOST_USERNAME" "$HOST_USERNAME" -D -s "$(which bash)"

# Allow passwordless sudo for user.
RUN mkdir -p /etc/sudoers.d/ && echo "$HOST_USERNAME ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$HOST_USERNAME"

RUN apk add rgb sudo git --no-cache

# Use the other user by default.
USER "$HOST_USERNAME"
WORKDIR "/home/$HOST_USERNAME/.dotfiles"

# Update default prompt using preexec.
RUN <<'PREEXEC' cat >> /home/$HOST_USERNAME/.preexec.local
function dotfile_debug_workspace_prompt() {
  local return_code=$?
  if [ "$return_code" != 0 ]; then
    echo -e "=== Run \033[1;32mexit\033[0m command to leave debug workspace"
  fi
  printf "[debug-workspace] "
  return "$return_code"
}
precmd_functions+=(dotfile_debug_workspace_prompt)
PREEXEC

EOF
    $containerBinary run "${docker_run_args[@]}" dotfiles_bootstrap_temp:latest bash -il -c "/home/$username/.dotfiles/bootstrap.sh $args; exec bash -il;"
    _exitCleanly
    return $?
  else
    :
  fi

  local docker_init_commands
  docker_init_commands=$(
    cat <<BASH_COMMANDS
apk add rgb git su-exec;
addgroup -g "\${HOST_GID}" "$username" && adduser -u "\${HOST_UID}" -G "$username" "$username" -D -s "\$(which bash)";
trap "echo -e \"=== Run \033[1;32mexit\033[0m command to leave debug workspace\"; exec su \"$username\"" EXIT ERR;
echo ${promptPrefix@Q} >> "/home/$username/.extra";
chown "$username:$username" "/home/$username/.extra";
dot_path="/home/$username/.dotfiles";
p="\${dot_path}/bootstrap.sh";
set +m; su "$username" -c "\$p $args"; set -m; exit;
BASH_COMMANDS
  )

  $containerBinary run --net=host --rm -it \
    -v "$current_dir:/home/$username/.dotfiles" \
    -w "/home/$username" \
    --env "HOST_UID=$(id -u)" --env "HOST_GID=$(id -g)" \
    bash \
    bash -c "$docker_init_commands"
}

function runMain() {
  local positional_args=()
  local force=${DOTFILE_FORCE:-0}
  local symlink=${DOTFILE_SYMLINK:-0}
  local backup=${DOTFILE_BACKUP:-}
  local dryrun=${DOTFILE_DRYRUN:-0}
  while (("$#")); do
    case "$1" in
    --help | -h)
      {
        echo "Should typically be installed with $0 --symlink"
        echo ""
        echo "options:"
        echo "    --update        Fetch the latest version from upstream."
        echo "    --test          Test the dotfile inside a docker environment."
        echo "    --backup        Backup the existing files if any."
        echo "    --no-backup     Disable backup of the existing file if any."
        echo "    --force         Force overwrite the existing files."
        echo "    --symlink       Symlink the dotfiles so that changes made to this local repo are automatically picked up."
        echo "    --dryrun        Do a dry run."
      } >&2
      _exitCleanly; return $?;
      ;;
    --update)
      shift
      if command -v git >/dev/null; then
        # Attempt to update the dotfile.
        git pull origin main
      fi
      ;;
    --test | -t)
      shift
      testIt "$@" "${positional_args[@]}"
      _exitCleanly; return $?;
      ;;
    --backup)
      backup=1
      ;;
    --no-backup)
      backup=0
      ;;
    --force | -f)
      force=1
      ;;
    --symlink | -s)
      symlink=1
      ;;
    --dryrun)
      dryrun=1
      ;;
    esac
    positional_args+=("$1")
    shift
  done

  set -- "${positional_args[@]}" # restore positional parameters

  if [ "$force" = 1 ]; then
    # Docker environment doesn't need to ask for confirmation.
    doIt "$symlink" "${backup:-1}" "$dryrun"
  elif tty -s &>/dev/null; then
    # Interactive input.
    printf 'This may overwrite existing files in your home directory. '
    if [ "$backup" != 1 ]; then
      printf 'You can enable backups with --backup. '
    fi
    read -r -p "Are you sure? (y/N) " -n 1
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      doIt "$symlink" "${backup:-0}" "$dryrun"
    fi
  else
    >&2 echo "Currently running in a non-interactive terminal, installing files..."
    doIt "$symlink" "${backup:-1}" "$dryrun"
  fi
}

runMain "$@"

_exitCleanly
unset _exitCleanly
