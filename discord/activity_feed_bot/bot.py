import discord
import os
from dotenv import load_dotenv

load_dotenv()

TOKEN = os.getenv("DISCORD_BOT_TOKEN")
MASTER_CHANNEL_NAME = os.getenv("MASTER_CHANNEL_NAME", "activityfeed").lower()
GUILD_NAME = os.getenv("GUILD_NAME", "EcoQuant Insight")
EXCLUDED_CHANNELS = {
    name.strip().lower()
    for name in os.getenv("EXCLUDED_CHANNELS", "scalpchat,algo-af").split(",")
    if name.strip()
}
ALLOWED_BOT_IDS = {
    int(bot_id.strip())
    for bot_id in os.getenv("ALLOWED_BOT_IDS", "").split(",")
    if bot_id.strip().isdigit()
}

if not TOKEN:
    raise RuntimeError("DISCORD_BOT_TOKEN is not set. Add it to .env before starting the bot.")

intents = discord.Intents.default()
intents.message_content = True
intents.messages = True
intents.guilds = True

client = discord.Client(intents=intents)

@client.event
async def on_ready():
    print(f"Logged in as {client.user}")
    for guild in client.guilds:
        if guild.name == GUILD_NAME:
            print(f"Connected to: {guild.name} (id: {guild.id})")
            break

@client.event
async def on_message(message):
    if not message.guild:
        return

    if message.author.bot and message.author.id not in ALLOWED_BOT_IDS:
        return

    # Skip if message is from an excluded channel
    if message.channel.name.lower() in EXCLUDED_CHANNELS:
        return

    # Get master channel object
    master_channel = discord.utils.get(message.guild.text_channels, name=MASTER_CHANNEL_NAME)
    if not master_channel:
        print(f"Master feed channel not found: {MASTER_CHANNEL_NAME}")
        return

    # Skip if message is from the master channel itself
    if message.channel.id == master_channel.id:
        return

    # Format repost
    repost = f"📣 **[{message.channel.name}] {message.author.display_name}:** {message.content}"

    # Forward attachments too
    try:
        if message.attachments:
            files = [await a.to_file() for a in message.attachments]
            await master_channel.send(content=repost, files=files)
        else:
            await master_channel.send(content=repost)
    except discord.Forbidden:
        print(
            f"Missing permission to post in #{master_channel.name}. "
            "Check View Channel, Send Messages, Attach Files, and Embed Links."
        )
    except discord.HTTPException as exc:
        print(f"Failed to repost message {message.id} from #{message.channel.name}: {exc}")

client.run(TOKEN)
