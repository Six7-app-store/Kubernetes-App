# shellcheck shell=sh
# Kubernetes-App: Komfort fuer alle Login-Shells.
# Wird auch von /bin/sh gelesen - deshalb eval statt "source <(...)".
alias k=kubectl
if [ -n "${BASH_VERSION:-}" ] && command -v kubectl >/dev/null 2>&1; then
  eval "$(kubectl completion bash)"
  # shellcheck disable=SC3044 # nur in bash erreicht
  complete -o default -F __start_kubectl k
fi
