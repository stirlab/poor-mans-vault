#!/usr/bin/env bash

function mount_vault() {

  local creds_dir="${1:-/var/db/vault}"
  local mount_dir="/tmp/vault.decrypted"

  mkdir -v ${mount_dir}

  echo "Mounting ${creds_dir} at ${mount_dir}..."
  gocryptfs ${creds_dir} ${mount_dir}

  for file in ${mount_dir}/*.sh; do
    echo "Reading ${file}..."
    . ${file}
  done

  echo "Unmounting ${mount_dir}..."
  fusermount -u  ${mount_dir}

  rmdir -v ${mount_dir}

  echo "Vault loaded to current environment"
}
