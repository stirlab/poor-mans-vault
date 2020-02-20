#!/usr/bin/env bash

VAULT_DEFAULT_ENV="dev"
VAULT_DEFAULT_VAULT_DIR="/var/db/vault"
VAULT_DEFAULT_MOUNT_DIR="/tmp/vault.decrypted"

SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

function _vault_get_environment() {
  echo "${VAULT_ENV:-${VAULT_DEFAULT_ENV}}"
}

function _vault_get_vault_dir() {
  echo "${VAULT_VAULT_DIR:-${VAULT_DEFAULT_VAULT_DIR}}"
}

function _vault_get_mount_dir() {
  echo "${VAULT_MOUNT_DIR:-${VAULT_DEFAULT_MOUNT_DIR}}"
}

function _vault_check_gocryptfs() {
  if [ -z "$(which gocryptfs)" ]; then
    echo "ERROR: missing gocryptfs"
    return 1
  fi
  return 0
}

function _vault_open() {
  local vault_dir="$(_vault_get_vault_dir)"
  local mount_dir="$(_vault_get_mount_dir)"
  if [ -d "${vault_dir}" ]; then
    if [ ! -d "${mount_dir}" ]; then
      mkdir -v "${mount_dir}"
      if [ $? -eq 0 ]; then
        echo "Mounting ${vault_dir} at ${mount_dir}..."
        gocryptfs ${vault_dir} ${mount_dir}
        return $?
      else
        echo "ERROR: could not create mount directory ${mount_dir}, aborting"
        return 1
      fi
    else
      echo "ERROR: mount directory ${mount_dir} already exists, aborting"
      return 1
    fi
  else
    echo "ERROR: vault directory ${vault_dir} missing, aborting"
    return 1
  fi
}

function _vault_load_env() {
  local environment="${1}"
  local mount_dir="$(_vault_get_mount_dir)"
  if [ -d "${mount_dir}/${environment}" ]; then
    # If the directory exists we expect at least one .sh file in it.
    echo "Loading .sh files from ${mount_dir}/${environment}..."
    for file in ${mount_dir}/${environment}/*.sh; do
      if [ -r "${file}" ]; then
        echo "Reading ${file}..."
        . "${file}"
      else
        echo "ERROR: could not read ${file}"
        return 1
      fi
    done
  else
    echo "${mount_dir}/${environment} does not exist, skipping"
  fi
  return 0
}

function _vault_load() {
  local environment="$(_vault_get_environment)"

  _vault_check_gocryptfs && \
    _vault_open && \
    _vault_load_env common && \
    _vault_load_env "${environment}"

  local ret=$?

  _vault_close

  if [ ${ret} -eq 0 ]; then
    echo "Vault loaded to current environment"
    export VAULT_LOADED=1
  fi
  return ${ret}
}

function _vault_close() {
  local mount_dir="$(_vault_get_mount_dir)"
  if [ -n "$(mount | grep ${mount_dir})" ]; then
    echo "Unmounting ${mount_dir}..."
    fusermount -u  "${mount_dir}"
  fi
  if [ -d "${mount_dir}" ]; then
    rmdir -v "${mount_dir}"
  fi
}

function _vault_check_missing_server() {
  local target="${1}"
  local server="${2}"
  if [ -z "${server}" ]; then
    echo "ERROR: ${target}_server required"
    exit 1
  fi
}

function _vault_get_remote_vault_dir() {
  local remote_server="${1}"
  local remote_vault_dir=$(${SSH_COMMAND} $remote_server 'echo ${VAULT_VAULT_DIR}')
  local ret=$?
  if [ ${ret} -ne 0 ]; then
    return ${ret}
  else
    if [ -z "${remote_vault_dir}" ]; then
      remote_vault_dir="${VAULT_DEFAULT_VAULT_DIR}"
    fi
    echo "${remote_vault_dir}"
  fi
}

function _vault_get_stat_command() {
  # stat doesn't work the same on Linux/Solaris vs. FreeBSD/Darwin, so
  # make adjustments here.
  local distro=$(uname -s)
  if [ "${distro}" = "Linux" ] || [ "${distro}" = "SunOS" ]; then
    echo "stat -c%Y"
  else
    echo "stat -s"
  fi
}

function _vault_get_remote_vault_last_modified_time() {
  local remote_server="${1}"
  local remote_vault_dir="${2}"
  local stat_command="$(_vault_get_stat_command)"
  local last_modified=$(${SSH_COMMAND} ${remote_server} "${stat_command} ${remote_vault_dir}")
  if [ -z "${last_modified}" ]; then
    # Simple way to allow modified test to pass.
    echo "0"
  else
    echo "${last_modified}"
  fi
}

function _vault_push() {
  local destination_server="${1}"
  local vault_dir="$(_vault_get_vault_dir)"

  _vault_check_missing_server destination "${destination_server}"
  local remote_vault_dir=$(_vault_get_remote_vault_dir "${destination_server}")

  local ret=$?
  if [ ${ret} -eq 0 ]; then
    local remote_last_modified=$(_vault_get_remote_vault_last_modified_time "${destination_server}" "${remote_vault_dir}")
    if [ "${remote_last_modified}" = "0" ]; then
      echo "${destination_server}:${remote_vault_dir} does not exist, creating..."
      ${SSH_COMMAND} ${destination_server} "mkdir -pv ${remote_vault_dir}"
      ret=$?
      if [ ${ret} -ne 0 ]; then
        echo "ERROR: could not create ${destination_server}:${remote_vault_dir}"
        return ${ret}
      fi
    fi
    echo "Pushing ${vault_dir} to ${destination_server}:${remote_vault_dir}..."
    rsync -e "${SSH_COMMAND}" -avz --delete ${vault_dir}/ ${destination_server}:${remote_vault_dir}
    ret=$?
    if [ ${ret} -eq 0 ]; then
      echo "Updating last modified time for ${destination_server}:${remote_vault_dir}..."
      ${SSH_COMMAND} ${destination_server} "touch ${remote_vault_dir}"
      ret=$?
      if [ ${ret} -eq 0 ]; then
        echo "Vault ${vault_dir} pushed successfully to ${destination_server}:${remote_vault_dir}"
      else
        echo "ERROR: could not update last modified time for ${destination_server}:${remote_vault_dir}"
      fi
    else
      echo "ERROR: could not push ${vault_dir} to ${destination_server}:${remote_vault_dir}"
    fi
  else
    echo "ERROR: could not prepare ${destination_server}:${remote_vault_dir}"
  fi
  return ${ret}
}


function _vault_pull() {
  local origin_server="${1}"
  local vault_dir="$(_vault_get_vault_dir)"

  _vault_check_missing_server origin "${origin_server}"
  local remote_vault_dir=$(_vault_get_remote_vault_dir "${origin_server}")

  local ret=$?
  if [ ${ret} -eq 0 ]; then
    ${SSH_COMMAND} ${origin_server} "ls ${remote_vault_dir}"
    ret=$?
    if [ ${ret} -ne 0 ]; then
      echo "ERROR: ${origin_server}:${remote_vault_dir} does not exist"
      return ${ret}
    fi
    echo "Pulling ${origin_server}:${remote_vault_dir} to ${vault_dir}..."
    rsync -e "${SSH_COMMAND}" -avz --delete ${origin_server}:${remote_vault_dir}/ ${vault_dir}
    ret=$?
    if [ ${ret} -eq 0 ]; then
      echo "Updating last modified time for ${vault_dir}..."
      touch ${vault_dir}
      ret=$?
      if [ ${ret} -eq 0 ]; then
        echo "Vault ${origin_server}:${remote_vault_dir} pulled successfully to ${vault_dir}"
      else
        echo "ERROR: could not update last modified time for ${vault_dir}"
      fi
    else
      echo "ERROR: could not pull ${destination_server}:${remote_vault_dir} to ${vault_dir}"
    fi
  else
    echo "ERROR: could not find ${origin_server}:${remote_vault_dir}"
  fi
  return ${ret}
}

function vault_help() {
  echo "

Usage:

  vault_help
  vault_init
  vault_edit
  vault_load
  vault_force_load
  vault_change_password
  vault_push <destination_server>
  vault_force_push <destination_server>
  vault_pull <origin_server>
  vault_force_pull <origin_server>

Settings:

  Environment: $(_vault_get_environment)
  Vault directory: $(_vault_get_vault_dir)
  Mount directory: $(_vault_get_mount_dir)

"
}

function vault_init() {
  local vault_dir="$(_vault_get_vault_dir)"

  _vault_check_gocryptfs && \
    mkdir -v "${vault_dir}" && \
    gocryptfs -init "${vault_dir}"

  local ret=$?

  if [ ${ret} -eq 0 ]; then
    echo "Vault ${vault_dir} initialized successfully"
  fi
  return ${ret}
}

function vault_edit() {
  local mount_dir="$(_vault_get_mount_dir)"
  local vault_dir="$(_vault_get_vault_dir)"

  _vault_check_gocryptfs && \
    _vault_open && \
    vim "${mount_dir}"

  local ret=$?

  _vault_close

  if [ ${ret} -eq 0 ]; then
    touch ${vault_dir}
    echo "Vault edited successfully.

Use vault_load to load new configuration to current environment"
    unset VAULT_LOADED
  fi
  return ${ret}
}

function vault_load() {
  if [ -n "${VAULT_LOADED}" ]; then
    echo "Vault already loaded -- to load again, use vault_force_load"
  else
    _vault_load
  fi
}

function vault_force_load() {
  _vault_load
}

function vault_change_password() {
  local vault_dir="$(_vault_get_vault_dir)"

  _vault_check_gocryptfs && \
    gocryptfs -passwd "${vault_dir}"

  local ret=$?

  if [ ${ret} -eq 0 ]; then
    echo "Vault ${vault_dir} passowrd updated successfully"
  fi
  return ${ret}
}

function vault_push() {
  local destination_server="${1}"
  _vault_check_missing_server destination "${destination_server}"
  local vault_dir="$(_vault_get_vault_dir)"
  local remote_vault_dir=$(_vault_get_remote_vault_dir "${destination_server}")
  local stat_command="$(_vault_get_stat_command)"
  local local_last_modified=$(${stat_command} "${vault_dir}")
  local remote_last_modified=$(_vault_get_remote_vault_last_modified_time "${destination_server}" "${remote_vault_dir}")
  if [ ${local_last_modified} -lt ${remote_last_modified} ]; then
    echo "ABORTING: ${destination_server}:${remote_vault_dir} was modified after ${vault_dir} -- use vault_force_push to force the push"
  else
    _vault_push "${destination_server}"
  fi
}

function vault_force_push() {
  local destination_server="${1}"
  _vault_push "${destination_server}"
}

function vault_pull() {
  local origin_server="${1}"
  _vault_check_missing_server origin "${origin_server}"
  local vault_dir="$(_vault_get_vault_dir)"
  local remote_vault_dir=$(_vault_get_remote_vault_dir "${origin_server}")
  local stat_command="$(_vault_get_stat_command)"
  local local_last_modified=$(${stat_command} "${vault_dir}")
  local remote_last_modified=$(_vault_get_remote_vault_last_modified_time "${origin_server}" "${remote_vault_dir}")
  if [ ${remote_last_modified} -lt ${local_last_modified} ]; then
    echo "ABORTING: ${vault_dir} was modified after ${origin_server}:${remote_vault_dir} -- use vault_force_pull to force the pull"
  else
    _vault_pull "${origin_server}"
  fi
}

function vault_force_pull() {
  local origin_server="${1}"
  _vault_pull "${origin_server}"
}
