# Activity Feed Bot

This Discord bot mirrors messages from normal channels into `#activityfeed`.

## Configuration

Create or update `.env` next to `bot.py`:

```dotenv
DISCORD_BOT_TOKEN=replace_with_rotated_token
MASTER_CHANNEL_NAME=activityfeed
GUILD_NAME=EcoQuant Insight
EXCLUDED_CHANNELS=scalpchat,algo-af
ALLOWED_BOT_IDS=
```

`ALLOWED_BOT_IDS` is optional. Leave it blank to ignore all bot/app-authored
messages. Set it to a comma-separated list of Discord user IDs if another app
posts messages that this bot should mirror, for example:

```dotenv
ALLOWED_BOT_IDS=123456789012345678,234567890123456789
```

## Discord Permissions

In the Discord server, configure the `#activityfeed` channel:

1. Deny `Send Messages` for `@everyone` or the general member role.
2. Add the activity feed bot's role or bot user as an override.
3. Allow the bot override:
   - `View Channel`
   - `Send Messages`
   - `Attach Files`
   - `Embed Links`

If another autoposting app should post directly in `#activityfeed`, give that
app's bot user or role the same channel override.

## Run

```bash
cd /home/bbotson/applications/ecoquant/repo/discord/activity_feed_bot
source venv/bin/activate
python bot.py
```

## Publish/Deploy

If this is running manually, stop the old process and restart it with the
commands above.

If this is deployed as a service, copy this directory to the server, update the
server-side `.env`, then restart the service or process manager that launches
`python bot.py`.

Before deploying, rotate the Discord bot token because the old token was present
in source code.
