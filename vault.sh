#!/usr/bin/env bash

VAULT_DEFAULT_CONFIG_DIR="/etc/vault"
VAULT_DEFAULT_VAULT_DIR="/var/db/vault"
VAULT_DEFAULT_MOUNT_DIR="/tmp/vault.decrypted"

function vault_help() {
  echo "

Usage:

  vault_init [vault_dir]
  vault_edit [vault_dir] [mount_dir]
  vault_load [vault_dir] [config_dir] [mount_dir]

Parameters:

  vault_dir: The gocryptfs encrypted directory (default ${VAULT_DEFAULT_VAULT_DIR})
  config_dir: The vault config directory (default ${VAULT_DEFAULT_CONFIG_DIR})
  mount_dir: The directory to mount the encrypted directory on (default ${VAULT_DEFAULT_MOUNT_DIR})

"
}

function vault_check_gocryptfs() {
  if [ -z "$(which gocryptfs)" ]; then
    echo "ERROR: missing gocryptfs"
    return 1
  fi
  return 0
}

function vault_check_env() {
  local config_dir="${1}"
  if [ -r "${config_dir}/env" ]; then
    return 0
  else
    echo "ERROR: ${config_dir}/env not readable"
    return 1
  fi
}

function vault_get_env() {
  local config_dir="${1}"
  echo "$(cat "${config_dir}/env")"
  return 0
}

function vault_open() {
  local vault_dir="${1}"
  local mount_dir="${2}"
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

function vault_load_env() {
  local mount_dir="${1}"
  local environment="${2}"
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

function vault_load_common_env() {
  local mount_dir="${1}"
  vault_load_env "${mount_dir}" common
  return $?
}

function vault_close() {
  local mount_dir="${1}"
  if [ -n "$(mount | grep ${mount_dir})" ]; then
    echo "Unmounting ${mount_dir}..."
    fusermount -u  "${mount_dir}"
  fi
  if [ -d "${mount_dir}" ]; then
    rmdir -v "${mount_dir}"
  fi
}

function vault_validate() {
  local config_dir="${1}"
  vault_check_gocryptfs && vault_check_env "${config_dir}"
  return $?
}

function vault_init() {
  local vault_dir="${1:-${VAULT_DEFAULT_VAULT_DIR}}"

  vault_check_gocryptfs && \
    mkdir -v "${vault_dir}" && \
    gocryptfs -init "${vault_dir}"

  local ret=$?

  if [ ${ret} -eq 0 ]; then
    echo "Vault ${vault_dir} initialized successfully"
  fi
  return ${ret}
}

function vault_load() {
  local vault_dir="${1:-${VAULT_DEFAULT_VAULT_DIR}}"
  local config_dir="${2:-${VAULT_DEFAULT_CONFIG_DIR}}"
  local mount_dir="${3:-${VAULT_DEFAULT_MOUNT_DIR}}"

  vault_validate "${config_dir}"

  if [ $? -eq 0 ]; then
    local environment="$(vault_get_env "${config_dir}")" && \
    vault_open "${vault_dir}" "${mount_dir}" && \
      vault_load_common_env "${mount_dir}" && \
      vault_load_env "${mount_dir}" "${environment}"

    local ret=$?

    vault_close "${mount_dir}"

    if [ ${ret} -eq 0 ]; then
      echo "Vault loaded to current environment"
    fi
    return ${ret}
  fi
  return 1
}

function vault_edit() {
  local vault_dir="${1:-${VAULT_DEFAULT_VAULT_DIR}}"
  local mount_dir="${2:-${VAULT_DEFAULT_MOUNT_DIR}}"

  vault_check_gocryptfs && \
    vault_open "${vault_dir}" "${mount_dir}" && \
    vim "${mount_dir}"

  local ret=$?

  vault_close "${mount_dir}"

  if [ ${ret} -eq 0 ]; then
    echo "Vault edited successfully"
  fi
  return ${ret}
}
