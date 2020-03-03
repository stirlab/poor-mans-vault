# Poor man's Vault

Loads a gocryptfs encrypted 'vault' of sensitive environment variables into the
current Bash shell.

**IMPORTANT NOTE:** I make no claims as to the security of this setup! It works
for me. For anything but the most simple scenarios, consider using a more
robust secrets manager such as
[Hashicorp Vault](https://www.vaultproject.io).


## Installation

 * Make sure [gocryptfs](https://nuetzlich.net/gocryptfs) is installed.
 * Source ```pmv.sh``` in the Bash shell where you wish to have access to the
   vault functions.

```
 . pmv.sh
```


## Usage

Run ```pmv_help``` for usage and current vault settings.


### Configuration

Vault is configured via the following environment variables:

 *  ```PMV_ENV```: The vault environment files to load
    (default ```dev```). Only this environment and the ```common```
    environment will be loaded in the current shell.
 *  ```PMV_VAULT_DIR```: The gocryptfs encrypted directory
    (default ```/var/db/vault```).
 *  ```PMV_MOUNT_DIR```: The directory to mount the encrypted
    directory on (default ```/tmp/vault.decrypted```).


### Initialization

Before vault can be used, you must initialize the encrypted vault directory,
and provide the decryption password.

 * Ensure ```${PMV_VAULT_DIR}``` doesn't already exist.
 * Run ```pmv_init```, then enter the encyption password.


### Adding/editing items in the vault

Run ```pmv_edit```

This decrypts the vault, mounts it at ```${PMV_MOUNT_DIR}```, and opens
```${PMV_MOUNT_DIR}``` in vim.

Create a directory in ```${PMV_MOUNT_DIR}``` that matches the name of the
```${PMV_ENV}``` setting.

Within the ```${PMV_ENV}``` subdirectory, place one or more files ending
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

Upon exit of vim, the vault is 'closed' by unmounting ```${PMV_MOUNT_DIR}```.


### Loading the vault into the current environment

 * Run ```pmv_load```
 * Enter the password used when the vault was initialized.

This decrypts the vault, mounts it at ```${PMV_MOUNT_DIR}```, and sources all
files ending in ```.sh``` in the following directories, in the following order:

 * ```${PMV_MOUNT_DIR}/common```
 * ```${PMV_MOUNT_DIR}/${PMV_ENV}```


Immediately after loading all files into the current shell, the vault is
'closed' by unmounting ```${PMV_MOUNT_DIR}```.

### Changing the vault password

 * Run ```pmv_change_password```
 * Enter the old password
 * Enter the new password

### Pushing to / pulling from remote servers

A simple push/pull mechanism allows synchronizing a local vault with a vault on
a remote server:

 * ```pmv_push root@foo.example.com```
 * ```pmv_pull root@foo.example.com```

Under the hood, ```rsync -avz --delete``` is used to synchronize the
directories. Directory modification times are checked both local and remote, and
the operation is aborted if the target directory has a modification time after
the source directory.

To defeat the modification time validation check, use the ```force``` variant
of the commands:

 * ```pmv_force_push root@foo.example.com```
 * ```pmv_force_pull root@foo.example.com```

**IMPORTANT NOTE:** The validation and synchronization feature is very basic,
and is provided as a convenience. It should work fine when used properly, and,
use at your own risk! In particular, make sure you have a valid setting for
```Vault directory``` on all servers by running ```pmv_help```

### Misc

  * See ```man gocryptfs``` to understand the backing library, and run any
    advanced operations on the vault, such as checking consistency.
