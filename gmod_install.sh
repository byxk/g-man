#!/bin/bash -e

# Var defaults
SESS_NAME=gmod
WINDOW_NAME=0
PANE_NAME=0
USER=srcds
SV_PASSWORD=''
RCON_PASSWORD='PaSsWoRd!'
MAX_PLAYERS=12
MAP=gm_flatgrass
GAMEMODE=sandbox
API_KEY=
COLLECTION=
EXTRA_OPTIONS=''

# Grab vars from command line
while getopts ":M:S:u:s:r:m:o:hg:c:a:dl" opt; do
  case $opt in
    S)
      SESS_NAME="$OPTARG"
      ;;
    u)
      USER="$OPTARG"
      ;;
    s)
      SV_PASSWORD="$OPTARG"
      ;;
    r)
      RCON_PASSWORD="$OPTARG"
      ;;
    m)
      MAX_PLAYERS="$OPTARG"
      ;;
    M)
      MAP="$OPTARG"
      ;;
    o)
      EXTRA_OPTIONS="$OPTARG"
      ;;
    g)
      GAMEMODE="$OPTARG"
      ;;
    c)
      COLLECTION="$OPTARG"
      ;;
    a)
      API_KEY="$OPTARG"
      ;;
    d)
      NODOWNLOAD=y
      ;;
    l)
      NOFASTDL=y
      ;;
    h)
      cat <<DELIM

    Usage: ./gmod_install.sh

    Option    Description                                  Default
    -----------------------------------------------------------------------
        -u    User to install the server under             srcds
        -s    Set the sv_password option
        -r    Sets the RCON password                       PaSsWoRd!
        -m    Maximum number of players on the server      12
        -g    Game mode                                    sandbox
        -M    Starting map                                 gm_flatgrass
        -S    Session name for tmux                        gmod
        -c    Steam Workshop Collection ID (requires -a)
        -a    API Key
        -d    Skip steamcmd download/validation
        -l    Skip fastdl setup
        -o    Set extra options

DELIM
      exit -1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument" >&2
      exit 1
      ;;
  esac
done

HOMEDIR="/home/$USER"
ARCH=`uname -p`

# Validation: we need to have either both collection and API key, or neither.
if ([ -z "$COLLECTION" ] && [ -n "$API_KEY" ] ) || ( [ -n "$COLLECTION" ] && [ -z "$API_KEY" ] ); then
#if (  ) != (  ); then
  echo "Collection and API key must be provided together."
  exit -1;
fi;

clear

# Opening Banner
cat <<DELIM
     _____        __  __
    / ____|      |  \/  |
   | |  __ ______| \  / | __ _ _ __
   | | |_ |______| |\/| |/ _\` | '_ \\
   | |__| |      | |  | | (_| | | | |
    \_____|      |_|  |_|\__,_|_| |_|

      Garry's Mod Auto-Installer


================================================================================
  Options
================================================================================

   System Architecture: $ARCH
   Username: $USER
   SV Password: $SV_PASSWORD
   RCON Password: $RCON_PASSWORD
   Game Mode: $GAMEMODE
   Starting Map: $MAP
   Player Max: $MAX_PLAYERS
   Tmux Session Name: $SESS_NAME
   Steam Workshop Collection: $COLLECTION
   API Key: $API_KEY
   Extra Options: $EXTRA_OPTIONS
================================================================================


  You have 5 seconds to hit Ctrl-C if the above options don't look right!
DELIM


# Here we go! Update, and add the i386 architecture libraries in.
apt-get update

if [ "$ARCH" = "x86_64" ];
then
  dpkg --add-architecture i386
  apt-get update
  apt-get -y install lib32stdc++6 lib32ncurses5 lib32z1 unzip lighttpd
  if [ -z "$NOFASTDL" ]; then
      apt-get -y install mono-complete
  fi
fi

# Start with the Steam commands
mkdir -p "$HOMEDIR"
useradd $USER || true
wget http://media.steampowered.com/client/steamcmd_linux.tar.gz -O $HOMEDIR/steamcmd_linux.tar.gz
tar xfz $HOMEDIR/steamcmd_linux.tar.gz -C $HOMEDIR
chown -R $USER:$USER $HOMEDIR
chmod 700 $HOMEDIR
chmod +x "$HOMEDIR"/steamcmd.sh

# Execute Steam commands to build the server
if [ -z "$NODOWNLOAD" ]; then
su - -c "$HOMEDIR/steamcmd.sh +login anonymous +force_install_dir $HOMEDIR/gmod +app_update 4020 validate +quit" $USER
su - -c "$HOMEDIR/steamcmd.sh +login anonymous +force_install_dir $HOMEDIR/content/tf2 +app_update 232250 validate +quit" $USER
su - -c "$HOMEDIR/steamcmd.sh +login anonymous +force_install_dir $HOMEDIR/content/css +app_update 232330 validate +quit" $USER
fi

# Build the mount.cfg file
su - -c "(cat <<DELIM
// Auto-generated by G-Man
// https://github.com/b-turchyn/g-man
"mountcfg"
{
        "cstrike"       "$HOMEDIR/content/css/cstrike"
        "tf"            "$HOMEDIR/content/tf2/tf"
}
DELIM
) > $HOMEDIR/gmod/garrysmod/cfg/mount.cfg" $USER

# Build the options string
OPTSTRING=" -game garrysmod +maxplayers $MAX_PLAYERS +map $MAP +gamemode $GAMEMODE +exec server.cfg" 

if [ -n "$SV_PASSWORD" ];
then
  OPTSTRING="$OPTSTRING +sv_password $SV_PASSWORD"
fi

if [ -n "$RCON_PASSWORD" ];
then
  OPTSTRING="$OPTSTRING +rcon_password $RCON_PASSWORD"
fi

if [ -n "$COLLECTION" ] && [ -n "$API_KEY" ];
then
  OPTSTRING="$OPTSTRING +host_workshop_collection $COLLECTION -authkey $API_KEY"
fi

if [ -n "$EXTRA_OPTIONS" ];
then
  OPTSTRING="$OPTSTRING $EXTRA_OPTIONS"
fi

# fastdl
# $HOMEDIR/gmod/garrysmod/cfg/mount.cfg
mkdir -p $HOMEDIR/gmod/SourceRSC
mkdir -p /var/www/html/fastdl
unzip SourceRSC.zip -d $HOMEDIR/gmod/SourceRSC
if [ -z "$NOFASTDL" ]; then
cat <<EOF > $HOMEDIR/gmod/SourceRSC/sourcersc.ini
[GameMod]
GMOD

[GSQryMode]
local

[RedirQryMode]
local

[ServerPath]
/home/srcds/gmod/garrysmod/

[RedirectPath]
/var/www/html/fastdl

[CompressPath]
/tmp/bzd

[RmCPath]
False

[SkipAddons]
False

[SkipMisc]
True

[Debug]
False

[AutoUpdate]
True

[RedirectCleaner]
Off

EOF
fi
if ! grep -i dir-listing /etc/lighttpd/lighttpd.conf; then
    echo "dir-listing.activate = \"enable\"" >> /etc/lighttpd/lighttpd.conf
fi
systemctl restart lighttpd
IP=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1 | head -n1)

su - -c "(cat <<DELIM
sv_allowupload 1
sv_allowdownload 0
sv_downloadurl \"http://$IP/fastdl/\"
DELIM
) > $HOMEDIR/gmod/garrysmod/cfg/server.cfg" $USER

su - -c "(cat <<DELIM
-- Collection: Zombie Survival Gamemode + Maps (157384458)
resource.AddWorkshop('105462463') -- Zombie Survival
resource.AddWorkshop('110984714') -- Zs Nacht Der Untoten
resource.AddWorkshop('110985664') -- Zs Obj Vertigo
resource.AddWorkshop('110983920') -- Zs Vault 106
resource.AddWorkshop('104848844') -- zs_yc2transit
resource.AddWorkshop('112595416') -- zs_obj_dump_v14
resource.AddWorkshop('107254185') -- zs_hazard_v3
resource.AddWorkshop('117020215') -- zs_factory_v3
resource.AddWorkshop('118656242') -- zs_cleanoffice
DELIM
) > $HOMEDIR/gmod/garrysmod/lua/autorun/server/resource.lua" $USER

if [ -z "$NOFASTDL" ]; then
# Spin up the tmux session for fastdl
tmux new-session -A -d -s fastdl
tmux send-keys -t "fastdl:$WINDOW_NAME.$PANE_NAME" C-z \
  "cd $HOMEDIR/gmod/SourceRSC/ && sudo mono SourceRSC.exe" Enter
fi

# Spin up the tmux session for gmod
tmux new-session -A -d -s $SESS_NAME

tmux send-keys -t "$SESS_NAME:$WINDOW_NAME.$PANE_NAME" C-z \
  "su - -c '$HOMEDIR/gmod/srcds_run $OPTSTRING' $USER" Enter

cat <<DELIM
     _____        __  __
    / ____|      |  \/  |
   | |  __ ______| \  / | __ _ _ __
   | | |_ |______| |\/| |/ _\` | '_ \\
   | |__| |      | |  | | (_| | | | |
    \_____|      |_|  |_|\__,_|_| |_|

Complete!
https://github.com/b-turchyn/g-man
DELIM
