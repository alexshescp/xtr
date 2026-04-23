# xTR Server Side

This document describes how to install and manage the server-side components used by xTR.
The repository includes helper scripts for setting up Xray, adding clients, and changing the masking domain.

## Install server side

Run the following commands on your Linux server as root or with `sudo`:

```bash
sudo mkdir -p /root/xray-tools
cd /root/xray-tools

sudo chmod +x xray_install_server.sh xray_add_client.sh xray_change_mask_domain.sh
sudo ./xray_install_server.sh
```

The installer script sets up Xray and creates the initial configuration files.

## Custom mask domain

If you want to use a different masked domain, start the installer with environment variables:

```bash
sudo DEST_DOMAIN=www.microsoft.com SERVER_NAME=www.microsoft.com XRAY_PORT=443 ./xray_install_server.sh
```

This installs the server with the chosen disguised domain and port.

## Add clients

To add a new client configuration, run:

```bash
sudo ./xray_add_client.sh
```

To add a named client entry, use a parameter:

```bash
sudo ./xray_add_client.sh iphone-main
```

## Change the masked domain

To update the masking domain later, use:

```bash
sudo /root/xray-tools/xray_change_mask_domain.sh www.microsoft.com
```

## File locations

The server scripts and Xray configuration files are stored in these standard locations:

* `/usr/local/etc/xray/config.json`
* `/usr/local/etc/xray/server_meta.json`
* `/usr/local/etc/xray/clients/clients.json`
* `/usr/local/etc/xray/clients/*.txt`

## Notes

* The server-side scripts are intended for Linux systems.
* The app itself reads client-side YAML configs from `app/src/main/assets`.
* Keep your server credentials and private keys secure.
