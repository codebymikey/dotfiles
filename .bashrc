if [[ "${BASH_PROFILE_DEBUG:-false}" = 'true' ]]; then
  {
    .bashrc
    =======
    echo "args: $*"
    echo "args (set): $-"
    env
    echo "----------"
  } >> /tmp/.bash-debug-${UID-}.log
fi
if [ -n "$PS1" ]; then
  source ~/.bash_profile;
  if [ -d $HOME/.bashrc.d ]; then
    for i in $(\ls $HOME/.bashrc.d/* 2>/dev/null); do
      source $i;
    done
  fi
fi
