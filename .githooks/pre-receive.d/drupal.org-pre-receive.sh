#!/bin/bash

# For debugging purposes.
function _debug() {
  if [ "${GIT_PREHOOK_DEBUG:-0}" = 1 ]; then
    echo >&2 "$@"
  fi
}

# Before pushing up (doesn't seem to work).
# https://stackoverflow.com/a/641979

_debug "pre-receive hook is running..."

git_remotes=$(git remote -v)
if ! [[ "$git_remotes" =~ git.drupal.org ]] && ! [[ "$git_remotes" =~ drupalcode.org ]]; then
  # Nothing to do here. Only applies to projects with drupal
  exit 0
fi

git_expected_author="${GIT_DRUPAL_USER:-${GIT_USER:-}}"
git_expected_email="${GIT_DRUPAL_EMAIL:-${GIT_COMMITTER_EMAIL:-}}"

if [ -z "$git_expected_author" ]; then
  # There are is Drupal user specified.
  exit 0
fi

norev=0000000000000000000000000000000000000000

# shellcheck disable=SC2034
while read -r oldsha newsha refname; do
  _debug "oldsha: $oldsha"
  _debug "newsha: $newsha"
  _debug "refname: $refname"

  # deleting is always safe
  if [[ "$newsha" == "$norev" ]]; then
    continue
  fi

  # make log argument be "..$newsha" when creating new branch
  if [[ $oldsha == "$norev" ]]; then
    revs="$newsha"
  else
    revs="$oldsha..$newsha"
  fi
  _debug $revs
  _debug "revs count: ${#revs}"
  git log --pretty=format:"%h %ae %an%n" $revs | while read -r git_author_sha git_author_email git_author_name; do
    if [[ -z "$git_author_sha" ]]; then
      continue
    fi

    if ! [[ "$git_author_name" =~ $git_expected_author ]] || ! [[ "$git_author_email" =~ $git_expected_author ]]; then
      {
        echo "Invalid git author: '$git_author_name <$git_author_email>' used, please update it."
        echo
        echo "If you really want to do this, use --no-verify to bypass this pre-receive hook."
        echo
      } >&2
      exit 3
    fi
  done
done
