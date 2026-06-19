# Activity Feed Bot Implementation Steps

Use this checklist to put the updated bot into effect.

## 1. Rotate The Discord Bot Token

The old token was present in source code, so rotate it before restarting the bot.

1. Open the Discord Developer Portal.
2. Select the application for the activity feed bot.
3. Go to the bot/token section.
4. Reset or regenerate the bot token.
5. Copy the new token.

Do not paste the token into `bot.py`.

## 2. Update `.env`

Open:

```text
/home/bbotson/applications/ecoquant/repo/discord/activity_feed_bot/.env
```

Set the rotated token:

```dotenv
DISCORD_BOT_TOKEN=paste_new_token_here
```

Recommended full file:

```dotenv
DISCORD_BOT_TOKEN=paste_new_token_here
MASTER_CHANNEL_NAME=activityfeed
GUILD_NAME=EcoQuant Insight
EXCLUDED_CHANNELS=scalpchat,algo-af
ALLOWED_BOT_IDS=
```

Leave `ALLOWED_BOT_IDS` blank unless this bot needs to mirror messages created by another Discord bot/app.

## 3. Decide Whether Another Bot/App Should Be Mirrored

If the autoposting app posts directly into `#activityfeed`, you do not need `ALLOWED_BOT_IDS` for that app. You only need Discord channel permissions.

If the autoposting app posts into another channel and this bot should copy that message into `#activityfeed`, add the autoposting app's Discord user ID:

```dotenv
ALLOWED_BOT_IDS=123456789012345678
```

For multiple apps:

```dotenv
ALLOWED_BOT_IDS=123456789012345678,234567890123456789
```

To get the bot/app user ID in Discord:

1. Enable Developer Mode in Discord user settings.
2. Right-click the bot/app user.
3. Choose `Copy User ID`.

## 4. Fix Discord Channel Permissions

In Discord, open the server settings for the `#activityfeed` channel.

For normal members:

1. Open `#activityfeed` channel settings.
2. Go to permissions.
3. Select `@everyone` or the general member role.
4. Deny `Send Messages`.
5. Keep `View Channel` allowed if members should still read the feed.

For the activity feed bot:

1. Add a permission override for the bot user or bot role.
2. Allow `View Channel`.
3. Allow `Send Messages`.
4. Allow `Attach Files`.
5. Allow `Embed Links`.

For a separate autoposting app that posts directly to `#activityfeed`:

1. Add a permission override for that app's bot user or bot role.
2. Allow `View Channel`.
3. Allow `Send Messages`.
4. Allow `Attach Files`.
5. Allow `Embed Links`.

## 5. Restart The Bot

The updated code does not take effect until the running process is restarted.

Find the existing process:

```bash
ps aux | grep '[p]ython bot.py'
```

Stop it:

```bash
kill <old_pid>
```

Start the updated bot:

```bash
cd /home/bbotson/applications/ecoquant/repo/discord/activity_feed_bot
source venv/bin/activate
nohup python bot.py >> activity_feed_bot.log 2>&1 &
```

Check that it started:

```bash
tail -n 50 activity_feed_bot.log
```

You should see a login message similar to:

```text
Logged in as ...
Connected to: EcoQuant Insight ...
```

## 6. Test In Discord

Test normal user mirroring:

1. Post a message in a normal source channel.
2. Confirm the message appears in `#activityfeed`.

Test member restrictions:

1. Use a normal member account or ask a member to check.
2. Confirm they cannot manually post in `#activityfeed`.
3. Confirm they can still read `#activityfeed` if that is intended.

Test autoposting app behavior:

1. Trigger the autoposting app.
2. If it posts directly to `#activityfeed`, confirm the post appears there.
3. If it posts to another channel and should be mirrored, confirm its ID is in `ALLOWED_BOT_IDS`.

## 7. Publish To Git

The bot directory is currently untracked in the repo, and the repository has unrelated existing changes. Add only the activity feed bot files.

From:

```bash
cd /home/bbotson/applications/ecoquant/repo
```

Run:

```bash
git add discord/activity_feed_bot/bot.py \
  discord/activity_feed_bot/README.md \
  discord/activity_feed_bot/.env.example \
  discord/activity_feed_bot/.gitignore \
  discord/activity_feed_bot/requirements.txt \
  discord/activity_feed_bot/docs/change_record.md \
  discord/activity_feed_bot/docs/implementation_steps.md \
  README.md \
  .gitignore
```

Commit:

```bash
git commit -m "Fix activity feed bot permissions handling"
```

Push:

```bash
git push
```

Do not commit:

- `discord/activity_feed_bot/.env`
- `discord/activity_feed_bot/venv/`
- `discord/activity_feed_bot/activity_feed_bot.log`

## 8. If It Still Does Not Work

Check the log:

```bash
tail -n 100 /home/bbotson/applications/ecoquant/repo/discord/activity_feed_bot/activity_feed_bot.log
```

If the log says the bot is missing permission to post in `#activityfeed`, re-check the channel permission overrides.

If user messages mirror but app messages do not, check whether the app's Discord user ID needs to be added to `ALLOWED_BOT_IDS`.

If nothing mirrors, confirm the bot is online, the token is current, and Discord's Message Content Intent is enabled for the bot in the Developer Portal.
