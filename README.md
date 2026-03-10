Install `atq` and `cronic`, then add this line to crontab for hourly asynchronous backups running at idle system conditions:

```
0 * * * * echo 'cronic /opt/redis-backup.sh/redis-backup.sh' | batch 2>/dev/null
```
