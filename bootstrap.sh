#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE}")"

if command -v git >/dev/null; then
  git pull origin main
fi

function doItRsync() {
  rsync \
    --exclude ".git/" \
    --exclude ".dotfiles/" \
    --exclude ".dotfiles-bak/" \
    --exclude ".idea" \
    --exclude ".DS_Store" \
    --exclude ".osx" \
    --exclude "bootstrap.sh" \
    --exclude "README.md" \
    --exclude "LICENSE-MIT.txt" \
    -avh --no-perms . ~
}

function doItFiles() {
  local symlink="$1"
  local backup="${2:-0}"
  local current_dir dotfiles_source
  local file relative_file_path target_file target_dir backup_dir

  current_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
  dotfiles_source="${current_dir}"
  backup_dir="$dotfiles_source/.dotfiles-bak/$(date +"%Y%m%d_%H.%M.%S")"
  while read -r file; do
    relative_file_path="${file#"${dotfiles_source}"/}"
    target_file="${HOME}/${relative_file_path}"
    target_dir="${target_file%/*}"

    if [ "$backup" = 1 ] && test -f "${file}"; then
      # Back up the regular script file before it's replaced.
      mkdir -p "${backup_dir}/${file%/*}"
      \cp -a "${file}" "${backup_dir}/${relative_file_path}"
    fi

    if test ! -d "${target_dir}"; then
      mkdir -p "${target_dir}"
    fi
    if [ "$symlink" = 1 ]; then
      printf 'Installing dotfiles symlink %s\n' "${target_file}"
      ln -sf "${file}" "${target_file}"
    else
      printf 'Copying dotfiles file %s\n' "${target_file}"
      \cp -af "${file}" "${target_file}"
    fi

  done < <(
    find "${dotfiles_source}" -type f \
      -not -path "${dotfiles_source}/.git/*" \
      -not -path "${dotfiles_source}/.dotfiles/*" \
      -not -path "${dotfiles_source}/.dotfiles-bak/*" \
      -not -path "${dotfiles_source}/.idea/*" \
      -not -path "${dotfiles_source}/.DS_Store" \
      -not -path "${dotfiles_source}/.osx" \
      -not -path "${dotfiles_source}/bootstrap.sh" \
      -not -path "${dotfiles_source}/README.md" \
      -not -path "${dotfiles_source}/LICENSE-MIT.txt"
  )
}

function doIt() {
  local symlink="$1"
  local backup="${2:-0}"
  doItFiles "$symlink" "$backup"
  # shellcheck source=.bash_profile
  source ~/.bash_profile
}

function testIt() {
  local args="${*@Q} --no-backup --force --testing"
  local username='app'
  local promptPrefix
  local HOST_UID HOST_GID
  HOST_UID=$(id -u)
  HOST_GID=$(id -g)

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
  docker_run_args+=(-w "/home/$username/")

  # Docker 17.05 and up supports HEREDOCS.
  # https://regex101.com/r/Yq3R2T/1
  if [[ "$(docker --version)" =~ (version ((1[8-9])|17\.[1-9]|17\.0\.[5-9]|[2-9])) ]]; then
    docker build \
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

RUN apk add rgb sudo --no-cache

# Use the other user by default.
USER "$HOST_USERNAME"
WORKDIR "/home/$HOST_USERNAME"
EOF
    docker run "${docker_run_args[@]}" dotfiles_bootstrap_temp:latest bash -il -c "/home/$username/.dotfiles/bootstrap.sh $args; exec bash -il;"
    exit
  else
    :
  fi

  local docker_init_commands
  docker_init_commands=$(
    cat <<BASH_COMMANDS
apk add rgb su-exec;
addgroup -g "\${HOST_GID}" "$username" && adduser -u "\${HOST_UID}" -G "$username" "$username" -D -s "\$(which bash)";
trap "echo -e \"=== Run \033[1;32mexit\033[0m command to leave debug workspace\"; exec su \"$username\"" EXIT ERR;
echo ${promptPrefix@Q} >> "/home/$username/.extra";
chown "$username:$username" "/home/$username/.extra";
dot_path="/home/$username/.dotfiles";
p="\${dot_path}/bootstrap.sh";
set +m; su "$username" -c "\$p $args"; set -m; exit;
BASH_COMMANDS
  )

  docker run --net=host --rm -it \
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
  local backup=${DOTFILE_BACKUP:-1}
  while (("$#")); do
    case "$1" in
    --help | -h)
      {
        echo ""
      } >&2
      exit
      ;;
    --test | -t)
      shift
      testIt "$@" "${positional_args[@]}"
      exit
      ;;
    --bootstrap)
      shift
      exit
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
    esac
    positional_args+=("$1")
    shift
  done

  set -- "${positional_args[@]}" # restore positional parameters

  if [ "$force" = 1 ]; then
    # Docker environment doesn't need to ask for confirmation.
    doIt "$symlink" "$backup"
  elif tty -s &>/dev/null; then
    # Interactive input.
    read -r -p "This may overwrite existing files in your home directory. Are you sure? (y/N) " -n 1
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      doIt "$symlink"
    fi
  else
    >&2 echo "Currently running in a non-interactive terminal, installing files..."
    doIt "$symlink" "$backup"
  fi
}

runMain "$@"

unset doIt doItRsync doItFiles runMain
