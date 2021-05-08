#!/bin/bash

VERSION=2.11

# printing greetings
echo
echo "Modified MoneroOcean mining setup script v$VERSION."
echo "This script has been modified in the following ways:"
echo "  * Do not download pre-compiled binaries"
echo "  * Expect to specify moneroocean executable (must be compiled with min-donation level == 0)"
echo "  * Use local config.json template"
echo "  * Do not add miner.sh script to $HOME/.profile (rely on systemd service only)"
echo "  * Expect config file template in same dir as this script"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not advised to run this script under root"
fi

# command line arguments
WALLET=$1
XMRIG_EXE=$2
EMAIL=$3 # this one is optional

# checking prerequisites
if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_moneroocean_miner.sh <wallet address> <path to xmrig> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi


if [ -z $XMRIG_EXE ]; then
  echo "Script usage:"
  echo "> setup_moneroocean_miner.sh <wallet address> <path to xmrig> [<your email address>]"
  echo "ERROR: Please specify the path to your xmrig binary"
  echo "       Be sure the xmrig executable you provided is MoneroOcean's advanced version:"
  echo "       https://github.com/moneroocean/xmrig"
  exit 1
fi

if ! [ -f ./config.json ]; then
  echo "ERROR: Please make sure a template config.json file is in this directory, before running."
  echo "       You can get a template config file from the latest MoneroOcean/xmrig release."
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 500 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if   [ "$1" -gt "8192" ]; then
      echo "8192"
    elif [ "$1" -gt "4096" ]; then
      echo "4096"
    elif [ "$1" -gt "2048" ]; then
      echo "2048"
    elif [ "$1" -gt "1024" ]; then
      echo "1024"
    elif [ "$1" -gt "512" ]; then
      echo "512"
    elif [ "$1" -gt "256" ]; then
      echo "256"
    elif [ "$1" -gt "128" ]; then
      echo "128"
    elif [ "$1" -gt "64" ]; then
      echo "64"
    elif [ "$1" -gt "32" ]; then
      echo "32"
    elif [ "$1" -gt "16" ]; then
      echo "16"
    elif [ "$1" -gt "8" ]; then
      echo "8"
    elif [ "$1" -gt "4" ]; then
      echo "4"
    elif [ "$1" -gt "2" ]; then
      echo "2"
    else
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 30 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 20000 + $PORT ))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "20001" -o "$PORT" -gt "28192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi


# printing intentions
echo "I will setup and run in background Monero CPU miner."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo "JFYI: This host has $CPU_THREADS CPU threads, so projected Monero hashrate is around $EXP_MONERO_HASHRATE KH/s."
echo "Sleeping for 5 seconds before continuing (press Ctrl+C to cancel)"
sleep 5
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
fi
killall -9 xmrig

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean

echo "[*] Creating $HOME/moneroocean directory"
mkdir $HOME/moneroocean

echo "[*] Copying xmrig executable into $HOME/moneroocean directory"
cp $XMRIG_EXE $HOME/moneroocean
cp ./config-template.json $HOME/moneroocean/config.json

echo "[*] Checking if $HOME/moneroocean/xmrig works fine"
$HOME/moneroocean/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/moneroocean/xmrig ]; then
    echo "WARNING: $HOME/moneroocean/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/moneroocean/xmrig was removed by antivirus (or some other problem)"
  fi
  exit 1
fi

echo "[*] Miner $HOME/moneroocean/xmrig is OK"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/moneroocean/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/moneroocean/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/moneroocean/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/moneroocean/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/moneroocean/xmrig.log'",#' $HOME/moneroocean/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/moneroocean/config.json

if ! sudo -n true 2>/dev/null; then
  echo "ERROR: This script requires passwordless sudo to set hugepages"
  exit 1
else
  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "       Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."
  else
    echo "[*] Creating moneroocean_miner systemd service"
    cat >/tmp/moneroocean_miner.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$HOME/moneroocean/xmrig --config=$HOME/moneroocean/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/moneroocean_miner.service /etc/systemd/system/moneroocean_miner.service
    echo "[*] Starting moneroocean_miner systemd service"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable moneroocean_miner.service
    sudo systemctl start moneroocean_miner.service
    echo "To see miner service logs run \"sudo journalctl -u moneroocean_miner -f\" command"
  fi
fi

echo "[*] Setup complete"





