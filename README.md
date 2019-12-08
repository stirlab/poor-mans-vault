# Poor man's Vault

Loads a gocryptfs encrypted 'vault' of sensitive environment variables into the
current shell.

**IMPORTANT NOTE:** I make no claims as to the security of this setup! It works
for me. For anything but the most simple scenarios, consider using a more
robust secrets manager such as
[Hashicorp Vault](https://www.vaultproject.io).

## Installation

1. Make sure [gocryptfs](https://nuetzlich.net/gocryptfs) is installed
2. Source ```vault.sh``` in the current Bash shell.

```
 . vault.sh
 ```

## Usage

Run ```vault_help``` for usage and parameter defaults.

### Initialization

Before the vault can be used, you must initialize the encrypted vault directory,
and provide the decryption password.

Run ```vault_init```, then enter the encyption password.

### Configuration

The vault configuration directory must contain a file called ```env```, which
contains a single word, the name of the environment-specific vault directory to
load, e.g. ```staging```, ```production```.

This is meant to support the ability to place ```env``` files on different
servers with different environment settings.

### Working with the vault

Run ```vault_edit```

This decrypts the vault, mounts it, and opens the  vault directory in vim.

Within the vault directory, place directories with the same names as any
```env``` configuration above, , e.g. ```staging```, ```production```. Within
these directories, place one or more files ending with a ```.sh``` extension.

In each file, add any environment variable exports that you wish to keep
be encrypted.

```
export DB_PASSWORD=sekret
export VPS_ACCESS_TOKEN=sometoken
```

In addition to the environment specific directories, you can also add a
```common``` directory -- any ```.sh``` files within it will be loaded for all
envionments.
