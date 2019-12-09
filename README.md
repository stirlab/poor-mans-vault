# Poor man's Vault

Loads a gocryptfs encrypted 'vault' of sensitive environment variables into the
current Bash shell.

**IMPORTANT NOTE:** I make no claims as to the security of this setup! It works
for me. For anything but the most simple scenarios, consider using a more
robust secrets manager such as
[Hashicorp Vault](https://www.vaultproject.io).


## Installation

 * Make sure [gocryptfs](https://nuetzlich.net/gocryptfs) is installed.
 * Source ```vault.sh``` in the Bash shell where you wish to have access to the
   vault functions.

```
 . vault.sh
```


## Usage

Run ```vault_help``` for usage and current vault settings.


### Configuration

Vault is configured via the following environment variables:

 *  ```VAULT_ENVIRONMENT```: The vault environment files to load
    (default ```dev```). Only this environment and the ```common```
    environment will be loaded in the current shell.
 *  ```VAULT_VAULT_DIR```: The gocryptfs encrypted directory
    (default ```/var/db/vault```).
 *  ```VAULT_MOUNT_DIR```: The directory to mount the encrypted
    directory on (default ```/tmp/vault.decrypted```).


### Initialization

Before vault can be used, you must initialize the encrypted vault directory,
and provide the decryption password.

 * Ensure ```${VAULT_VAULT_DIR}``` doesn't already exist.
 * Run ```vault_init```, then enter the encyption password.


### Adding/editing items in the vault

Run ```vault_edit```

This decrypts the vault, mounts it at ```${VAULT_MOUNT_DIR}```, and opens
```${VAULT_MOUNT_DIR}``` in vim.

Create a directory in ```${VAULT_MOUNT_DIR}``` that matches the name of the
```${VAULT_ENVIRONMENT}``` setting.

Within the ```${VAULT_ENVIRONMENT}``` subdirectory, place one or more files ending
with a ```.sh``` extension.

In each file, add any environment variable exports that you wish to keep
encrypted.

```
export DB_PASSWORD=sekret
export VPS_ACCESS_TOKEN=sometoken
```

In addition to the environment specific directories, you can also add a
```common``` directory -- any ```.sh``` files within it will be loaded for all
environments, prior to the environment-specific files being loaded.

Upon exit of vim, the vault is 'closed' by unmounting ```${VAULT_MOUNT_DIR}```.


### Loading the vault into the current environment

 * Run ```vault_load```
 * Enter the password used when the vault was initialized.

This decrypts the vault, mounts it at ```${VAULT_MOUNT_DIR}```, and sources all
files ending in ```.sh``` in the following directories, in the following order:

 * ```${VAULT_MOUNT_DIR}/common```
 * ```${VAULT_MOUNT_DIR}/${VAULT_ENVIRONMENT}```


Immediately after loading all files into the current shell, the vault is
'closed' by unmounting ```${VAULT_MOUNT_DIR}```.

### Changing the vault password

 * Run ```vault_change_password```
 * Enter the old password
 * Enter the new password

### Misc

  * See ```man gocryptfs``` to understand the backing library, and run any
    advanced operations on the vault, such as checking consistency.
