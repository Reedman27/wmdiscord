# Security notes

> This is an archived experimental project. Review the implementation before use.

- WMDiscord connects only to the user's local Discord IPC socket. It does not scrape Discord account tokens, read Discord databases, or connect to the private Gateway.
- The Discord application client secret is read from `WMDISCORD_CLIENT_SECRET` in the process environment. It is not embedded in source and is never saved by WMDiscord.
- The OAuth access/refresh token response is saved to `${XDG_CONFIG_HOME:-~/.config}/wmdiscord/token.json`.
- WMDiscord creates its config directory with owner-only permissions where possible and applies mode `0600` to the token file.
- The token file is still a bearer credential. Anyone who can read it as the same user can potentially use it. Do not upload it, paste it into chat, or include it in backups shared with other people.
- HTTPS is used for OAuth exchange/refresh with libcurl peer and hostname verification enabled.
- The overlay currently only reads voice state. It does not mute, deafen, move participants, or invoke other RPC write commands.
- A distributed public desktop build must not ship a confidential application secret. A future public release needs a proper supported public-client or backend authorization design.
