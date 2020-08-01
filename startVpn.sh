#!/usr/bin/env bash

# Author: Tim Neumann
# License: Mozilla Public License
# Project Page: https://github.com/c-hack/openvpnClientScripts

dir="$(dirname "$(realpath "$0")")"

function printHelp {
  echo "Usage:"
  echo ""
  echo "$0 [options] <server name>"
  echo ""
  echo "Options:"
  echo "-h --help           print this help"
  echo "-n --not            invert next option. Only works for options below"
  echo "-d --default-route  add default route through vpn"
  echo "-t --tmux           use tmux"
  echo ""
  echo "Use the -n flag to override settings from the config"
  echo ""
  echo "Config:"
  echo "You can configure some of these options in the file startVpn.conf"
  echo "The following options are supported: default-route, tmux"
}

if ! which "xargs" > /dev/null 2>&1 ;then
  echo "Need xargs"
fi

args=($@)

if [ $# -lt 1 ] ;then
  printHelp
  exit
fi

serverName="${@: -1}"
if [ "$serverName" == "-h" ] ;then
  printHelp
  exit
elif [[ "$serverName" == "-"* ]] ;then
  echo "Missing server name"
  printHelp
  exit
fi

defaultRoute=false
tmux=false

while read line ; do
  option=$(echo "$line" | xargs)
  if [[ "$option" == "#"* ]] || [ "$option" == "" ] ;then
    : #Is a comment
  elif [ "$option" == "default-route" ] ;then
    defaultRoute=true
  elif [ "$option" == "tmux" ] ;then
    tmux=true
  else
    echo "Unknown config option: $line"; printHelp; exit
  fi
done < "$dir/startVpn.conf"

invert=false
optionCount=`expr $# - 1`
counter=0

while [ $counter -lt $optionCount ] ;do
  o="${args[$counter]}"
  if   [ "$o" == "-h" ] || [ "$o" == "--help" ] ;then printHelp; exit
  elif [ "$o" == "-n" ] || [ "$o" == "--not" ] ;then if $invert ;then "Cannot invert $o" ;else invert=true ;fi
  elif [ "$o" == "-d" ] || [ "$o" == "--default-route" ] ;then if $invert ;then defaultRoute=false ;else defaultRoute=true ;fi
  elif [ "$o" == "-t" ] || [ "$o" == "--tmux" ] ;then if $invert ;then tmux=false ;else tmux=true ;fi
  else echo "Unknown option: $o";printHelp; exit
  fi
  counter=`expr $counter + 1`
done

if $tmux && ! which "tmux" > /dev/null 2>&1 ;then
  echo "Need tmux"
fi

if $tmux && ! which "sudo" > /dev/null 2>&1 ;then
  echo "Need sudo"
fi

if $tmux ;then
  sessionName="VPN-$serverName"
  tmux="tmux -2"

  if $tmux has-session -t $sessionName ;then
    echo "Session $sessionName already exists. Attaching."
    sleep 1
    $tmux attach -t $sessionName
    exit 0;
  fi

  #create new session with the name and detach from it for now
  $tmux new-session -d -s $sessionName

  $tmux send-keys "sudo $0"

  if $defaultRoute ;then
    $tmux send-keys " -d"
  else
    $tmux send-keys " -n -d"
  fi

  $tmux send-keys " $serverName" Enter

  $tmux attach -t $sessionName:0
  exit
fi

### Start of internal logic

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

serverDir="$dir/servers/$serverName"

if ! [ -d "$serverDir" ] ;then
  echo "Cannot find the directory for the server $serverName"
  exit
fi

openVpnConfFile="$serverDir/client.ovpn"

if ! [ -e "$openVpnConfFile" ] ;then
  echo "Cannot find the client config file servers/$serverName/client.ovpn"
  exit
fi

startupHook="$serverDir/startup.sh"
shutdownHook="$serverDir/shutdown.sh"

if ! [ -e "$startupHook" ] ;then
  echo "Cannot find the startupHook servers/$serverName/startup.sh"
  exit
fi

if ! [ -e "$shutdownHook" ] ;then
  echo "Cannot find the shutdownHook servers/$serverName/shutdown.sh"
  exit
fi

cleanup() {
    err=$?
    echo "Cleaning stuff up..."
    trap '' EXIT INT TERM
    bash "$shutdownHook" "$defaultRoute"
    exit $err
}
sig_cleanup() {
    trap '' EXIT # some shells will call EXIT after the INT handler
    false # sets $?
    cleanup
}

PIPE="$dir/.pipe_$serverName"

function readAndWorkPipe {
  while read line ;do
    if [[ "$line" == *"Initialization Sequence Completed"* ]] ;then
      echo "Getting address..."
      bash "$1" "$2"
      echo "Done getting address."
      trap cleanup EXIT
      trap sig_cleanup INT QUIT TERM
    fi
  done < $3
}

rm -f "$PIPE"
mkfifo "$PIPE"

cd "$serverDir"

readAndWorkPipe "$startupHook" "$defaultRoute" "$PIPE" &
openvpn "$openVpnConfFile" | tee "$PIPE"
