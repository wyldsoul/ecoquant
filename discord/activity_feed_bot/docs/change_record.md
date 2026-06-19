# Activity Feed Bot Change Record

Date: 2026-06-15

## Summary

The activity feed bot was updated to make Discord permission failures easier to diagnose, remove a leaked hardcoded token from source code, and support optional mirroring of messages created by specific bot/app accounts.

## Files Changed

- `bot.py`
- `.env.example`
- `.gitignore`
- `README.md`

## What Changed

### Token Handling

The bot no longer contains a hardcoded Discord token in `bot.py`.

Before, `bot.py` loaded `DISCORD_BOT_TOKEN` from `.env`, then immediately replaced it with a hardcoded token. That meant changing `.env` would not actually affect the running bot.

Now, the bot only reads:

```dotenv
DISCORD_BOT_TOKEN=...
```

from `.env`.

If `DISCORD_BOT_TOKEN` is missing, the bot stops immediately with a clear error.

### Configurable Channel Settings

These values can now be set from `.env`:

```dotenv
MASTER_CHANNEL_NAME=activityfeed
GUILD_NAME=EcoQuant Insight
EXCLUDED_CHANNELS=scalpchat,algo-af
ALLOWED_BOT_IDS=
```

Defaults are still provided for the existing server/channel setup.

### Bot/App Message Handling

The bot still ignores messages from other bots/apps by default.

This matters because bot-to-bot loops can happen if every bot message is mirrored automatically.

If a specific autoposting app should be mirrored into `#activityfeed`, its Discord user ID can be added to:

```dotenv
ALLOWED_BOT_IDS=123456789012345678
```

Multiple bot/app IDs can be comma-separated.

### Permission Failure Logging

The bot now catches Discord permission errors when trying to post to `#activityfeed`.

If it cannot post, it logs a message telling you to check:

- `View Channel`
- `Send Messages`
- `Attach Files`
- `Embed Links`

### Git Safety

A `.gitignore` was added so these do not get committed:

- `.env`
- `venv/`
- `__pycache__/`
- `*.pyc`

This protects the bot token and avoids committing the local Python virtual environment.

### Documentation

`README.md` was added with configuration, Discord permission, run, and deploy notes.

## Validation

The bot passed Python syntax validation:

```bash
python3 -m py_compile bot.py
```

No live Discord restart was performed during the change. The currently running process must be restarted before the updated code takes effect.

