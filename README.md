Clone this repo:

```
cd /opt
git clone https://github.com/DragonWork/redis-backup.sh.git
```

The shell script requires at least `bash`, `xargs`, `awk` and `zstd` for compression.

Install `atq` and `cronic`, then open crontab:

```
crontab -e
```

... and add this line for hourly asynchronous backups running at idle system conditions:

```
0 * * * * echo 'cronic /opt/redis-backup.sh/redis-backup.sh' | batch 2>/dev/null
```
