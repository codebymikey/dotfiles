#!/bin/bash

# Pre-commit hook to enforce using just the specific username.

[[ "${TRACE:-0}" == "1" ]] && set -o xtrace

# Expected author to use.
git_expected_author="${GIT_DRUPAL_USER:-${GIT_USER:-}}"
git_expected_email="${GIT_DRUPAL_EMAIL:-${GIT_COMMITTER_EMAIL:-}}"
git_real_name="${GIT_REAL_NAME:-}"

if [ -z "$git_expected_author" ] && [ -z "$git_real_name" ]; then
  # There are no Drupal users specified.
  exit 0
fi

git_remotes=$(git remote -v)
if ! [[ "$git_remotes" =~ git.drupal.org ]] && ! [[ "$git_remotes" =~ drupalcode.org ]]; then
  # Nothing to do here. Only applies to projects with drupal
  exit 0
fi

git_author_info=$(git var GIT_AUTHOR_IDENT) || exit 1
git_author_name=$(printf '%s\n' "${git_author_info}" | sed -n 's/^\(.*\) <.*$/\1/p')
git_author_email=$(printf '%s\n' "${git_author_info}" | sed -n 's/^.* <\(.*\)> .*$/\1/p')

if [[ -n "$git_real_name" && "$git_author_name <$git_author_email>" =~ $git_real_name ]] || \
   [[ ! "$git_author_name" =~ $git_expected_author ]] || \
   [[ ! "$git_author_email" =~ $git_expected_author ]]; then
  {
    echo "Invalid git author: '$git_author_name <$git_author_email>' used, please update it."
    echo
    echo "If you really want to do this, use --no-verify to bypass this pre-commit hook."
    echo
  } >&2
  echo >&2
  exit 2
fi
