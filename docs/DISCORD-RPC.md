# Discord RPC integration notes

WMDiscord uses the documented local IPC RPC transport. It does not connect to the undocumented/private Gateway.

## Current startup sequence

1. Find `discord-ipc-0` through `discord-ipc-9` beneath `XDG_RUNTIME_DIR`, `TMPDIR`, `TMP`, `TEMP`, or `/tmp`.
2. Connect using `AF_UNIX` / `SOCK_STREAM`.
3. Send opcode `HANDSHAKE` (0) with JSON `{ "v": 1, "client_id": "..." }`.
4. Wait for the `READY` event.
5. Send `AUTHENTICATE` with a saved access token, or send `AUTHORIZE` with `client_id`, `response_type: "code"`, and the `rpc`, `identify`, and `rpc.voice.read` scopes. Do not include `redirect_uri` in the native IPC AUTHORIZE frame. The `rpc.voice.read` scope is required for voice settings and voice events and is restricted to Discord-approved partners; an ordinary OAuth authorization does not automatically grant it.
6. On the authorization code response, exchange the code at Discord's OAuth2 token endpoint using libcurl, `client_id`, `client_secret`, `grant_type=authorization_code`, `code`, and the same registered `redirect_uri` supplied in `WMDISCORD_REDIRECT_URI`.
7. Store the token response locally and send `AUTHENTICATE`.
8. Query `GET_SELECTED_VOICE_CHANNEL`.
9. Subscribe to `VOICE_CHANNEL_SELECT` and `VOICE_SETTINGS_UPDATE`. For a selected channel, subscribe to voice state and speaking events with `channel_id` arguments.

## RPC requirements

Create a Discord Developer Application. Register a desktop redirect URI in OAuth2 → Redirects (for example `http://127.0.0.1/callback`) and set that exact value as `WMDISCORD_REDIRECT_URI`. The native Unix-socket IPC `AUTHORIZE` frame includes `client_id`, `response_type: "code"`, and `scopes`; it must NOT include `redirect_uri`. Discord uses the registered redirect for the code flow, and the app supplies that URI only to the later `/oauth2/token` exchange. Set `WMDISCORD_CLIENT_ID` and `WMDISCORD_CLIENT_SECRET` too. The code deliberately does not embed a client secret in the binary.

Discord's RPC documentation states that RPC access for unapproved applications is restricted to an approved tester list. Development accounts may need to be added to the app's tester list before authorization succeeds.

## Events used

| Event | Purpose | Subscribe arguments |
|---|---|---|
| `VOICE_CHANNEL_SELECT` | Detect join/leave/channel change | none |
| `VOICE_SETTINGS_UPDATE` | Read current user's mute/deafen state | none |
| `VOICE_STATE_CREATE` | Add participant | `channel_id` |
| `VOICE_STATE_UPDATE` | Update participant mute/deafen/profile state | `channel_id` |
| `VOICE_STATE_DELETE` | Remove participant | `channel_id` |
| `SPEAKING_START` | Highlight speaker | `channel_id` |
| `SPEAKING_STOP` | Remove speaking highlight | `channel_id` |
| `VOICE_CONNECTION_STATUS` | Voice connection status telemetry | none |

## Known caveats

- Actual authorization depends on the Discord app's RPC access and the user's tester/approval status.
- A `Redirect URI cannot be used in the RPC OAuth2 Authorization flow` error means `redirect_uri` was incorrectly included in the native IPC AUTHORIZE frame. Keep `response_type: "code"`, omit `redirect_uri` from that frame, register a redirect in the Developer Portal, and send the registered URI only during the authorization-code token exchange.
- `rpc.voice.read` is required for the voice roster/events. Discord currently documents this scope as available only to approved partners. If Discord refuses the scope or omits it from `AUTHENTICATE.data.scopes`, the application cannot retrieve the voice roster through this documented RPC route until Discord grants the app access.
- Diagnostic logs report handshake, close, authorization, authentication, request errors, and the selected-channel voice-state count. They never print access tokens or client secrets.
- Discord may change the RPC contract. Compare real response payloads against the official docs before changing parsing.
- The initial implementation is intentionally read-only. The RPC API also has write commands, but WMDiscord does not call them.
- Voice events are scoped to a channel ID; subscribing without it is not a correct participant/speaker subscription.

## Reference documentation

- [Discord RPC](https://discord.com/developers/docs/topics/rpc)
- [Discord OAuth2](https://discord.com/developers/docs/topics/oauth2)

The RPC reference currently documents the IPC handshake, opcode layout, authorization and authentication commands, `GET_SELECTED_VOICE_CHANNEL`, channel-specific subscriptions, participant state events, and speaking events.
