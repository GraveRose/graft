#!/bin/bash

#
# ToDo
#------
#
# 1. Create documentation on how to configure the
#    remote server to tunnel to.
# 4. Add in DNS tunneling 
#

# User-defined variables
#
# ----------------
# Global Variables
# ----------------
# PREF is the order in which you prefer the protocols be attempted
# Example: PREF=(http ssh icmp dns) # Default
PREF=(http ssh icmp dns)

# SRV is the IP address or FQDN of the server you want to connect to
SRV=x.x.x.x

# USER is the username to authenticate to SRV with
# Example: USER=jdoe
USER=jode

# RPORT is the TCP port to bind the revers shell to on SRV
# Example: RPORT=2232
RPORT=2222

# ---------------
# HTTPS Variables
# ---------------
# HPORT is the port that SRV has HTTPS bound to
# Example: HPORT=443
HPORT=443

# SHA is the SHA-1 hash of the certificate installed on $SRV
# You can get this with: nmap $SRV -p 443 --script -ssl-cert | grep SHA
# Example: SHA="abcd 1234 abcd 1234 abcd 1234 abcd 1234 abcd 1234"
SHA="abcd 1234 abcd 1234 abcd 1234 abcd 1234 abcd 1234"

# -------------
# SSH Variables
# -------------
# CFG is the config file for the SSH client (You probably don't need to change this)
CFG="$HOME/.ssh/config"

# SSHPORT is the port that SRV has SSH bound to
# Example: SSHPORT=22
SSHPORT=22

# SIG is the signature of $SSH running on $SRV
# Example: SIG="awe54lkws8o7sd4a23w45lhkjasd8dfg4234lkas8as"
SIG="awe54lkws8o7sd4a23w45lhkjasd8dfg4234lkas8as"

# --------------
# ICMP Variables
# --------------
# LPORT is the local port to use for the ICMP reverse tunnel
# Example: LPORT=1234
LPORT=1234

# LSSHPORT is the port the /client/ is running SSH on
# Example: LSSHPORT=22
LSSHPORT=22

# -------------
# Log Variables
# -------------
# This is for logging which will be implemented properly once this is a systemd process
LF="/tmp/graft.log"

# JUST FOR TESTING
rm -f $LF

# Do not edit below this line
# ---------------------------

#Version
VER="0.0.1"

# These are the connection variables to test if a protocol is reachable
# "0" - Can reach
# "1" - Can't reach
# Default is "1" until the check is complete
HTTPC="1"
SSHC="1"
ICMPC="1"
DNSC="1"

# Lock file
LOCK="/var/lock/graft.lock"

# JUST FOR TESTING
rm $LOCK


# This is a reusable variable for whatever is needed and shouldn't store important info
REUSE=0

clear

echo "$(date) - GRAFT Started" >> $LF
echo  -n "$(date) - Checking for lockfile at $LOCK ... " >> $LF
echo -n "Checking for lockfile at $LOCK ... "
if [ -e $LOCK ]; then
  echo -e "\e[31m[FAIL]\e[39m"
  echo "[FAIL]" >> $LF
  exit 255
else
  touch $LOCK
  echo "[OK]" >> $LF
fi

echo "$(date) - PREF = ${PREF[@]}" >> $LF
echo

function title() {

  cat << EOT
________________________________

                               
 _____ _____ _____ _____ _____ 
|   __| __  |  _  |   __|_   _|
|  |  |    -|     |   __| | |  
|_____|__|__|__|__|__|    |_|  
                             

       GRAFT: $VER
________________________________

EOT

}

function checkreq() {

  echo
  echo "Performing Requirements Checking"
  echo "--------------------------------"

  echo -n "$(date) - Checking for openssl ... " >> $LF
  echo -n "Checking for openssl .......... "
  which openssl > /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
  else
    echo -e "\e[31m[FAIL]\e[39m"
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 10
  fi

  echo -n "$(date) - Checking for hping3 ... " >> $LF
  echo -n "Checking for hping3 ........... "
  which hping3 > /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
  else
    echo -e "\e[31m[FAIL]\e[39m"
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 11
  fi  

  echo -n "$(date) - Checking for ssh ... " >> $LF
  echo -n "Checking for ssh .............. "
  which ssh > /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
  else
    echo -e "\e[31m[FAIL]\e[39m"
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 12
  fi 

  echo -n "$(date) - Checking for ptunnel-ng ... " >> $LF
  echo -n "Checking for ptunnel-ng ....... "
  which ptunnel-ng > /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
  else
    echo -e "\e[31m[FAIL]\e[39m"
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 13
  fi 

  echo -n "Stopping all \"ptunnel-ng\" instances ... "
  killall ptunnel-ng
  echo "Done"

}

function graft-http() {

  if [ "$HTTPC" != "0" ]; then
    return
  fi

  echo "$(date) - Entered HTTP Mode" >> $LF
  echo
  echo "Entering HTTP Mode"
  echo "------------------"

  # Config checking
  echo -n "$(date) - Checking ~/.ssh/config ... " >> $LF
  echo -n "Checking for proper .ssh/config for $SRV ... "

  grep "Host $SRV" $CFG > /dev/null
  if [ "$?" != "0" ]; then
    echo "[1] FAIL" >> $LF
    echo "$(date) - Exiting">> $LF
    echo -e "\e[31mNot found\e[39m"
    echo "Please add the following to your ~/.ssh/config file:"
    echo
    echo "Host $SRV"
    echo "    ProxyCommand openssl s_client -connect $SRV:$HPORT -quiet 2>/dev/null"
    echo
    echo "Exiting..."
    return 254
  else
    echo -n "[1] OK" >> $LF
    REUSE=$((REUSE+1))
  fi

  grep "ProxyCommand openssl s_client -connect $SRV:$HPORT -quiet" $CFG > /dev/null
  if [ "$?" != "0" ]; then
    echo " [2] FAIL" >> $LF
    echo "$(date) - Exiting">> $LF
    echo -e "\e[31mNot found\e[39m"
    echo "Please add the following to your ~/.ssh/config file:"
    echo
    echo "Host $SRV"
    echo "    ProxyCommand openssl s_client -connect $SRV:$HPORT -quiet 2>/dev/null"
    echo
    echo "Exiting..."
    return 253
  else
    echo " [2] OK" >> $LF
    REUSE=$((REUSE+1))
  fi

  if [ $REUSE == 2 ]; then
    echo -e "\e[32m[OK]\e[39m"
  else
    echo "\e[31m[FAIL]\e[39m"
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 250
  fi

  # Check for existing tunnel
  echo -n "$(date) - Checking for existing tunnel ... " >> $LF
  netstat -peanut 2>/dev/null | grep EST | grep $SRV > /dev/null
  if [ $? == 0 ]; then
    echo "[FAIL]" >> $LF
    echo "It appears that the SSH tunnel is already connected. Exiting..."
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 255
  fi

  echo "[OK]" >> $LF
  echo "$(date) - Starting tunnel over HTTPS - RPORT = $RPORT" >> $LF
  echo "Creating SSH reverse tunnel over HTTPS"
  ssh $USER@$SRV -R $RPORT:127.0.0.1:22 -p $SSHPORT
  RV=$?
  if [ "$RV" == "0" ]; then
    echo "$(date) - Stopped tunnel over HTTPS - RPORT = $RPORT" >> $LF
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 0
  else
    echo "$(date) - Exit from SSH: ($RV)." >> $LF
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 22
  fi

}

function graft-ssh {

  if [ "$SSHC" != "0" ]; then
    return
  fi

  echo "$(date) - Entered SSH Mode" >> $LF

  echo
  echo "Entering SSH Mode"
  echo "-----------------"

  echo "$(date) - Starting tunnel over SSH - RPORT = $RPORT" >> $LF
  echo "Creating SSH reverse tunnel over SSH"
  ssh $USER@$SRV -R $RPORT:127.0.0.1:22 -p $SSHPORT -F /dev/null
  RV=$?
  if [ "$RV" == "0" ]; then
    echo "$(date) - Stopped tunnel over SSH - RPORT = $RPORT" >> $LF
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    exit 0
  else
    echo "$(date) - Exit from SSH: ($RV)." >> $LF
    rm -f $LOCK
    echo "$(date) - Lockfile removed from $LOCK" >> $LF
    return 22
  fi

}

function graft-icmp() {

  if [ "$ICMPC" != "0" ]; then
    return
  fi

  echo "$(date) - Entered ICMP Mode" >> $LF

  echo
  echo "Entering ICMP Mode"
  echo "------------------"

  echo "$(date) - Starting tunnel over ICMP" >> $LF
  echo "Creating ICMP reverse tunnel over ICMP"

  echo -n "$(date) - Starting ptunnel-ng ... " >> $LF
  ptunnel-ng -l$RPORT -p$SRV -R$SSHPORT &
  echo "[OK]" >> $LF
  sleep 2
  ssh $USER@localhost -p$RPORT -R $LPORT:localhost:$LSSHPORT
  killall ptunnel-ng
  exit

}

function graft-dns() {

  echo "DNS"

}

function graft-main() {

  # Using hping3 to see what we can reach
  echo
  echo "Testing Connections"
  echo "-------------------"
  echo -n "HTTPS ... "
  echo -n "$(date) - Testing HTTPS access to $SRV on port $HPORT ... " >> $LF
  hping3 $SRV -S -c 1 -p $HPORT &> /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
    HTTPC="0"
  else
    echo "[FAIL]" >> $LF
    echo -e "\e[31m[FAIL]\e[39m"
    HTTPC="1"
  fi

  if [ "$HTTPC" == "0" ]; then
    # Certificate checking
    echo -n "$(date) - Checking certificate ... " >> $LF
    echo -n "Verifying $SRV HTTPS certificate ... "
    SHATMP=$(nmap $SRV -p $HPORT --script ssl-cert | grep SHA | awk '{print $2 " " $3 " " $4 " " $5 " " $6 " " $7 " " $8 " " $9 " " $10 " " $11}')

    if [ "$SHATMP" == "$SHA" ]; then
      echo "[OK]" >> $LF
      echo "$(date) - SHA    = $SHA" >> $LF
      echo "$(date) - SHATMP = $SHATMP" >> $LF
      echo -e "\e[32m[OK]\e[39m"
    else
      echo "[FAIL]" >> $LF
      echo -e "\e[31m[FAIL]\e[39m Certificate Mismatch"
      echo "$(date) - SHA    = $SHA" >> $LF
      echo "$(date) - SHATMP = $SHATMP" >> $LF
      HTTPC="1"
    fi
  fi

  echo -n "SSH ..... "
  echo -n "$(date) - Testing SSH access to $SRV on port $SSHPORT ... " >> $LF
  hping3 $SRV -S -c 1 -p $SSHPORT &> /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
    SSHC="0"
  else
    echo "[FAIL]" >> $LF
    echo -e "\e[31m[FAIL]\e[39m"
    SSHC="1"
  fi

  if [ "$SSHC" == "0" ]; then
    # Attempt to get the SSH fingerprint of the server
    echo -n "$(date) - Attempting to verify SSH fingerprint of $SRV ... " >> $LF
    echo -n "Verifying SSH fingerprint of $SRV ... "
    SIGTMP=$(ssh-keyscan -p $SSHPORT -t ecdsa $SRV 2>/dev/null | ssh-keygen -lf- | awk -F ':' '{print $2}' | awk '{print $1}')
    if [ "$SIG" != "$SIGTMP" ]; then
      echo -e "\e[31m[FAIL]\e[39m Signature Mismatch"
      echo "FAIL" >> $LF
      echo "$(date) - SIG    = $SIG" >> $LF
      echo "$(date) - SIGTMP = $SIGTMP" >> $LF
      SSHC="1"
    else
      echo -e "\e[32m[OK]\e[39m"
      echo "OK" >> $LF
      echo "$(date) - SIG    = $SIG" >> $LF
      echo "$(date) - SIGTMP = $SIGTMP" >> $LF
    fi
  fi

    echo -n "$(date) - Testing SSH access to $SRV on port $SSHPORT ... " >> $LF
  hping3 $SRV -S -c 1 -p $SSHPORT &> /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
    SSHC="0"
  else
    echo "[FAIL]" >> $LF
    echo -e "\e[31m[FAIL]\e[39m"
    SSHC="1"
  fi

  echo -n "ICMP .... "
  echo -n "$(date) - Testing ICMP access to $SRV ... " >> $LF
  ping -c 1 $SRV &> /dev/null
  if [ "$?" == "0" ]; then
    echo "[OK]" >> $LF
    echo -e "\e[32m[OK]\e[39m"
    ICMPC="0"
  else
    echo "[FAIL]" >> $LF
    echo -e "\e[31m[FAIL]\e[39m"
    ICMPC="1"
  fi

  # Follow PREF to connect
  for i in ${PREF[@]}; do
    graft-$i
  done

}


title
checkreq
graft-main

# EOF
