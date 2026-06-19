import discord
import os

TOKEN = "your-bot-token-here"
MASTER_CHANNEL_NAME = "activityfeed"  # channel name in lowercase, no #
GUILD_NAME = "EcoQuant Insight"  # optional: used for diagnostics

intents = discord.Intents.default()
intents.message_content = True
intents.messages = True
intents.guilds = True

client = discord.Client(intents=intents)

@client.event
async def on_ready():
    print(f"✅ Logged in as {client.user}")
    for guild in client.guilds:
        if guild.name == GUILD_NAME:
            print(f"🛰 Connected to: {guild.name} (id: {guild.id})")
            break

@client.event
async def on_message(message):
    if message.author.bot:
        return

    # Get master channel object
    master_channel = discord.utils.get(message.guild.text_channels, name=MASTER_CHANNEL_NAME)
    if not master_channel:
        print("❌ Master feed channel not found.")
        return

    # Skip if message is from the master channel itself
    if message.channel.id == master_channel.id:
        return

    # Format repost
    repost = f"📣 **[{message.channel.name}] {message.author.display_name}:** {message.content}"

    # Forward attachments too
    if message.attachments:
        files = [await a.to_file() for a in message.attachments]
        await master_channel.send(content=repost, files=files)
    else:
        await master_channel.send(content=repost)

client.run(TOKEN)