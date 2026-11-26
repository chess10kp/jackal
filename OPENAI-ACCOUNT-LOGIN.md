# OpenAI account sign-in

Jackal supports ChatGPT account sign-in through OpenAI's documented open-source registration flow. It creates its own client registration and uses the Responses API with the account's granted ChatGPT plan permission.

## Use it

1. Start the TUI with `./run.sh` and enter `/login openai`, or select **Continue with ChatGPT** from `/login`.
2. Complete authorization in the browser. If the browser does not open, use the URL shown in the terminal. Sign-in expires after five minutes; `/login cancel` cancels it.
3. Use `/model` to choose an `openai/<slug>` model from your account's catalog. Display names appear beside the model commands.
4. `/login openai` also opens the saved-account picker. Choose an existing registration, add another account, or authorize the selected account again. `/login openai new` starts a new registration directly.
5. `/logout openai` removes the active session's local tokens and attempts remote revocation. A message distinguishes confirmed revocation from a local-only sign-out. The registration remains available for reauthorization.

The browser must reach Jackal's loopback callback at `127.0.0.1`. When running Jackal over SSH, forward the callback port shown in its authorization URL before completing authorization, or run the binary on the browser's machine. A callback URL must not be pasted into the chat prompt.

API-key login remains available under `openai_compat` and the other existing providers. Account tokens are never exported as API-key environment variables.

## Storage and implementation

Credentials live in `openai-accounts.json` under `JACKAL_AGENT_DIR`, or `~/.jackal` when that variable is unset. The launcher defaults `JACKAL_AGENT_DIR` to the repo's `pi/` directory. The file is written atomically with mode `0600`; newly created parent directories use `0700`. Do not share or commit this file.

A stable host UUID survives restarts. Each attempt uses fresh state, nonce and PKCE, and starts its loopback listener before opening the browser. Callback state and issued client ID are checked before token exchange. ID tokens undergo native OpenSSL RS256 verification plus issuer, audience, validity, nonce and subject checks. ChatGPT plan permission is required separately.

Registrations are keyed by issued client ID and verified subject, so identical emails do not merge accounts. A pending attempt leaves the active account unchanged until validation succeeds. Refreshes hold a cross-process file lock while exchanging and atomically replacing the rotating token pair. A transport retains its selected account for the whole turn, even if the user selects another account.

The account route uses `https://api.openai.com/v1/models` and `/responses`, with `store: false` and streaming enabled. Conversation history includes prior function calls and their outputs. Buffered function calls reach the agent only after an explicit successful terminal event; truncated or failed streams remain errors even after partial text.

Source modules are `app/agent/openai_accounts.jac`, `openai_login.jac`, `openai_identity.jac`, and `openai_responses.jac`, with bodies in their `impl/` annexes. UI integration uses the existing login picker and frame tick. The project requires neojac 0.5.3's architecture wiring and implementation-annex format.

## Verification

Development and native builds run on `jackal-extra-1`, in `/data/workspace/jackal-openai`, isolated from the other VM session. Automated tests cover signed-token rejection, callback HTTP handling, account isolation and private storage, refresh-record rotation, missing plan permission, Responses history conversion, and unsuccessful terminal streams. A PTY test covers the account picker and cancellation.

Real account consent, a live refresh grant, remote revocation and subscription-backed inference require a user-operated account check; automated fixtures do not establish that live authorization succeeded. Test results and binary paths are recorded in the delivery message.

## Protocol references

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Profiles and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
