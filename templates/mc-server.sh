
#!/bin/bash


#Run these
#chmod +x mc-server.sh
#chmod +x docker-compose.yml

#This file just needs to be in the same directory as docker-compose.yml


SERVER_DIR="$(pwd)"
SERVER_NAME="$(basename "$SERVER_DIR")"

CONTAINER_NAME=$(grep -E '^\s*container_name:' docker-compose.yml | awk '{print $2}')
BACKUP_DIR="$HOME/minecraft-self-hosted/$SERVER_NAME"




# Ensure correct directory
if [[ "$(pwd)" != "$SERVER_DIR" ]]; then
    echo "⚠️  You must be in $SERVER_DIR to run this command!"
    exit 1
fi

# Available commands
COMMANDS=("start" "stop" "stop5" "cancel" "restart" "reseed" "status" "console" "logs" \
          "properties" "whitelist" "ops" "stats" "statsl" "backup" "backupn" "restore" "commands")

# Create missing symlinks
for CMD in "${COMMANDS[@]}"; do
    ln -sf mc-server.sh "$SERVER_DIR/$CMD"
done



RUN_CMD="$(basename "$0")"

case "$RUN_CMD" in

start)
    echo "🚀 Starting Minecraft server ($SERVER_NAME)..."
    docker compose up -d
    ;;

stop)
    echo "🛑 Stopping Minecraft server safely..."
    docker exec -it "$CONTAINER_NAME" rcon-cli stop 2>/dev/null
    sleep 5
    docker compose down
    ;;

stop5)
    echo "🕗 Countdown to shutdown (5 minutes)..."
    rm -f "$SERVER_DIR/stop5.cancel" 2>/dev/null

    for t in 5 4 3 2 1; do
        docker exec -it "$CONTAINER_NAME" rcon-cli say "§cSERVER SHUTDOWN in $t MINUTES!"
        sleep 60
        [[ -f "$SERVER_DIR/stop5.cancel" ]] && docker exec -it "$CONTAINER_NAME" rcon-cli say "§aSERVER SHUTDOWN CANCELLED!" && rm -f "$SERVER_DIR/stop5.cancel" && exit 0
    done

    for i in 30 15 10 9 8 7 6 5 4 3 2 1; do
        docker exec -it "$CONTAINER_NAME" rcon-cli say "§cSERVER SHUTDOWN in $i SECONDS!"
        sleep 1
    done

    docker exec -it "$CONTAINER_NAME" rcon-cli stop
    sleep 5
    docker compose down
    ;;

cancel)
    echo "❌ Cancelling shutdown"
    touch "$SERVER_DIR/stop5.cancel"
    docker exec -it "$CONTAINER_NAME" rcon-cli say "§aSERVER SHUTDOWN CANCELLED!"
    ;;

restart)
    echo "🔄 Restarting server..."
    "$SERVER_DIR/stop"
    sleep 3
    "$SERVER_DIR/start"
    ;;

reseed)
    echo "🌱 Reseeding world for $SERVER_NAME"
    read -rp "⚠️  THIS WILL DELETE THE CURRENT WORLD. Type YES to continue: " CONFIRM
    [[ "$CONFIRM" != "YES" ]] && echo "❌ Reseed cancelled" && exit 1

    echo "🛑 Stopping server..."
    docker exec -it "$CONTAINER_NAME" rcon-cli stop 2>/dev/null
    sleep 5
    docker compose down

    echo "🗑 Deleting world data..."
    rm -rf "$SERVER_DIR/data/world"
    rm -rf "$SERVER_DIR/data/world_nether"
    rm -rf "$SERVER_DIR/data/world_the_end"

    echo "🚀 Starting fresh world..."
    docker compose up -d
    echo "✅ World reseeded"
    ;;

status)
    docker ps --filter "name=$CONTAINER_NAME"
    ;;

console)
    echo "🎮 Opening interactive console (type 'exit' or press CTRL+D to quit)"
    docker exec -it "$CONTAINER_NAME" rcon-cli
    ;;

logs)
    docker compose logs -f
    ;;

properties)
    nano "$SERVER_DIR/data/server.properties"
    ;;

whitelist)
    nano "$SERVER_DIR/data/whitelist.json"
    ;;

ops)
    nano "$SERVER_DIR/data/ops.json"
    ;;

stats)
    echo "🔎 Player List:"
    docker exec -it "$CONTAINER_NAME" rcon-cli list 2>/dev/null
    echo "🔎 Server Version:"
    echo "  Minecraft: $(grep 'VERSION:' "$SERVER_DIR/docker-compose.yml" | grep -v 'FORGE' | cut -d'"' -f2)"
    FORGE_VER=$(grep 'FORGE_VERSION:' "$SERVER_DIR/docker-compose.yml" 2>/dev/null | cut -d'"' -f2)
    [[ -n "$FORGE_VER" ]] && echo "  Forge: $FORGE_VER"
    echo "🔎 Resource Usage:"
    docker stats --no-stream "$CONTAINER_NAME"
    ;;

statsl)
    for i in {1..6}; do
        docker exec -it "$CONTAINER_NAME" rcon-cli list 2>/dev/null
        docker stats --no-stream "$CONTAINER_NAME"
        [[ "$i" -lt 6 ]] && sleep 10
    done
    ;;

backup)
    docker exec -it "$CONTAINER_NAME" rcon-cli save-off
    docker exec -it "$CONTAINER_NAME" rcon-cli save-all
    sleep 2
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP="$(date +%F-%H%M)"
    tar -czf "$BACKUP_DIR/backup-$TIMESTAMP.tar.gz" -C "$SERVER_DIR" data
    docker exec -it "$CONTAINER_NAME" rcon-cli save-on
    echo "✅ Backup complete"
    ;;

backupn)
    read -rp "Enter backup name: " NAME
    docker exec -it "$CONTAINER_NAME" rcon-cli save-off
    docker exec -it "$CONTAINER_NAME" rcon-cli save-all
    sleep 2
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP="$(date +%F-%H%M)"
    tar -czf "$BACKUP_DIR/$NAME-$TIMESTAMP.tar.gz" -C "$SERVER_DIR" data
    docker exec -it "$CONTAINER_NAME" rcon-cli save-on
    echo "✅ Named backup complete"
    ;;

restore)
    echo "Available backups:"
    ls "$BACKUP_DIR"
    read -rp "Enter backup filename: " FILE
    docker stop "$CONTAINER_NAME"
    rm -rf "$SERVER_DIR/data"
    tar -xzf "$BACKUP_DIR/$FILE" -C "$SERVER_DIR"
    docker start "$CONTAINER_NAME"
    echo "✅ Restore complete"
    ;;

commands)
    echo "Available commands:"
    for CMD in "${COMMANDS[@]}"; do echo "  $CMD"; done
    ;;

*)
    echo "Usage: ${COMMANDS[*]}"
    exit 1
    ;;
esac
