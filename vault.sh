#!/usr/bin/env bash

VAULT_DEFAULT_ENV="dev"
VAULT_DEFAULT_VAULT_DIR="/var/db/vault"
VAULT_DEFAULT_MOUNT_DIR="/tmp/vault.decrypted"

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

function vault_help() {
  echo "

Usage:

  vault_help
  vault_init
  vault_edit
  vault_load
  vault_force_load
  vault_change_password

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

  _vault_check_gocryptfs && \
    _vault_open && \
    vim "${mount_dir}"

  local ret=$?

  _vault_close

  if [ ${ret} -eq 0 ]; then
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
