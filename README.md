Clone this repo:

```
cd /opt
git clone https://github.com/DragonWork/redis-backup.sh.git
```

The shell script runs on Linux and requires `bash` and standard tools including
`xargs`, `awk`, `cp`, `od` and `tr`. It uses `zstd` with its default compression
level when the RDB is not already zstd-compressed.

After BGSAVE, the script checks only the first 11 bytes of the RDB. It recognizes
both standalone zstd frames and Valkey's native zstd-compressed RDB format
(the VCS envelope followed by a zstd frame). Already compressed files are copied
unchanged, using a reflink when supported, without invoking or requiring `zstd`.
The header check does not scan or decompress the file.

Native Valkey backups retain their envelope and use the `.rdb` extension; restore
them directly with a Valkey version supporting that format. Standalone zstd
backups and backups compressed by this script use `.rdb.zst`; decompress these
before restoring. `--keep N` counts both formats together.

Install `atq` and `cronic`, then open crontab:

```
crontab -e
```

... and add this line for hourly asynchronous backups running at idle system conditions:

```
0 * * * * echo 'cronic /opt/redis-backup.sh/redis-backup.sh' | batch 2>/dev/null
```
