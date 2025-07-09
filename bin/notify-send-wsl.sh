#!/bin/bash

# Default values
app_name="WSL Notify"
urgency="0"
# One hour by default.
expire_time=3600000
title=""
message=""

# Parse arguments
while  [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--urgency|--urgency=*) value="${1##--urgency=}"; if [[ "$value" != "$1" ]]; then shift; else value="$2"; shift 2; fi
      if [ "$value" = critical ]; then urgency=1; fi ;;
    -t|--expire-time|--expire-time=*) value="${1##--expire-time=}"; if [[ "$value" != "$1" ]]; then shift; else value="$2"; shift 2; fi
      expire_time="$value";;
    -a|--app-name|--app-name=*) value="${1##--app-name=}"; if [[ "$value" != "$1" ]]; then shift; else value="$2"; shift 2; fi
      app_name="$value";;
    -c|--category|--category=*) value="${1##--category=}"; if [[ "$value" != "$1" ]]; then shift; else value="$2"; shift 2; fi ;; # ignored
    -i|--icon|--icon=*) value="${1##--icon=}"; if [[ "$value" != "$1" ]]; then shift; else value="$2"; shift 2; fi ;;             # ignored
    -h|--hint|--hint=*) value="${1##--hint=}"; if [[ "$value" != "$1" ]]; then shift; else value="$2"; shift 2; fi ;;             # ignored
    --action|--action=*) value="${1##--action=}"; if [[ "$value" != "$1" ]]; then shift; else value="$2"; shift 2; fi ;;          # ignored
    --transient) shift ;; # ignored
    --help) shift ;;      # ignored
    --) shift; break ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      if [[ -z "$title" ]]; then
        title="$1"
      elif [[ -z "$message" ]]; then
        message="$1"
      else
        message="$message $1"
      fi
      shift
      ;;
  esac
done

# Read from stdin if no message
if [[ -z "$message" && ! -t 0 ]]; then
  message=$(cat)
fi

# Escape for PowerShell
pwsh_escape() {
  local str="$1"
  str="${str//'`'/'``'}"   # backticks
  str="${str//\"/\\\"}"    # quotes
  str="${str//$'\n'/'`n'}" # newlines
  str="${str//$'\r'/'`r'}" # carriage return
  str="${str//$'\t'/'`t'}" # tabs
  echo "$str"
}

# Compose the PowerShell script inline to show the notification.
powershell.exe -NoProfile -Command "
\$title = \"$(pwsh_escape "$title")\"
\$msg = \"$(pwsh_escape "$message")\"
\$appName = \"$(pwsh_escape "$app_name")\"
\$expirationTime = \"$(pwsh_escape "$expire_time")\"
\$priority = \"$(pwsh_escape "$urgency")\"

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null

\$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$textNodes = \$template.GetElementsByTagName('text')
\$textNodes.Item(0).AppendChild(\$template.CreateTextNode(\$title)) > \$null
\$textNodes.Item(1).AppendChild(\$template.CreateTextNode(\$msg)) > \$null

\$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$appName)
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template)
\$toast.Group = \$appName
\$toast.ExpirationTime = [DateTimeOffset]::Now.AddMilliseconds(\$expirationTime)
\$toast.NotificationMirroring = 1
\$toast.Priority = \$priority
\$notifier.Show(\$toast)
"
