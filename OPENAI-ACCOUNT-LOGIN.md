# OpenAI account sign-in scope

Requested: ChatGPT account sign-in, not API-key entry.

## Current behavior

`tui/picker_actions.jac` constructs `/login` from `PROVIDER_ROUTES`.
OAuth selection always reports unavailable. `agent/auth_network.jac` has
unimplemented authorization and refresh seams. `agent/llm_transport.jac`
implements Chat Completions, not Responses.

## Implementation boundary

Use OpenAI's documented open-source Sign in with ChatGPT flow, with Jackal's
own dynamic client registration. Do not reuse Codex's client ID or credentials.

1. Persist a stable, opaque host ID. Start a loopback callback listener before
   opening the browser. Generate fresh state, nonce, and PKCE per attempt.
2. Validate callback state and issued client ID; exchange the code. Validate
   the ID-token signature using JWKS, issuer, audience, expiry, and nonce.
   Require the returned plan-usage permission before enabling inference.
3. Save credentials atomically with owner-only permissions, retaining the
   issued client ID and verified identity. Keep pending sign-ins separate
   from the active account. Refresh rotating credentials as one transaction.
4. Add a distinct account-auth provider route and Responses transport. Convert
   conversation history, function calls, and tool results; normalize streamed
   text, calls, completion, and errors for the existing agent loop.
5. Run authorization off the TUI thread. Support cancellation and timeout;
   show the authorization URL for users whose browser is on another machine.
6. Test malformed callbacks, rejected consent, invalid signatures and claims,
   missing permissions, expired/revoked tokens, refresh rotation, storage
   failures, text streaming, and multi-turn tool use. Build both native entries
   on box-7a0637; account consent is a separate user-operated live check.

## Native dependency investigation / human handoff

On box-7a0637, neojac 0.3.2 rejects `import jwt` with W1100 (module not found).
This proves no JWT module is available through that import; it does not prove
that lower-level cryptography or another native library cannot implement OIDC.
No native ID-token verification implementation has yet been established.

Owner: Jackal integration, with neojac runtime/library support if needed.
Minimal recommended next step: establish a supported native JWKS/JWT signature
verification API, or explicitly choose a reviewed crypto helper boundary.
Do not replace signature verification with base64 decoding. The repository's
AGENTS.md rule 4 requires stopping and documenting framework gaps for the human.
Implementation is not complete; no login option has been enabled.

The VM checkout also contains extensive pre-existing edits, including auth and
transport files. Preserve those edits when continuing; do not overwrite it with
the local checkout.

## Primary references

- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
