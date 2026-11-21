# Grader access

Graders can enter a separate access code in the app. They do not need your OpenAI key, Cloudflare account, or Xcode environment variables. The code permits chat and grammar requests to your existing Worker; provider usage still bills your OpenAI project and uses the existing shared limits.

This update needs a Worker deployment and a rebuilt app. It has not been deployed from this workspace.

## Owner: one-time setup

1. Generate a private code on your Mac:

   ```sh
   openssl rand -hex 24
   ```

   Save the output in your password manager. Do not commit it or paste it into chat. Use a new value, different from both `XIAOLIAO_CLIENT_TOKEN` and `OPENAI_API_KEY`.

2. In Terminal, change into the updated repository's `Backend` folder. Run:

   ```sh
   npx wrangler secret put XIAOLIAO_GRADING_TOKEN
   ```

   Paste the generated code when Wrangler asks for the secret value. Alternatively, add a Secret with that exact name under your existing Worker's Settings → Variables and Secrets. Keep the existing OpenAI and developer secrets.

3. Deploy the updated backend:

   ```sh
   npx wrangler deploy
   ```

   Use the existing `xiaoliao-api` Worker/account. The repository supplies the binding and configuration; do not replace it by pasting only `worker.js` into the dashboard.

4. Build the updated app in Xcode, then give the grader the code privately along with the app/repository instructions. Building from source still needs a Mac, Xcode supporting the retained iOS 26.5 target, and normal Apple signing for physical devices. The access code does not distribute or install the app.

## Grader: use the app

1. Open the rounded menu button (terracotta glyph) → gear → Conversation Settings.
2. Enable **Grading Mode / 评分模式** for English controls and errors.
3. Under **Grading access**, paste the supplied code and tap **Verify and save**. Do not enter an OpenAI key.
4. Return through the menu and start a conversation. If a conversation or grammar job previously failed, tap its existing Retry button explicitly.

The code is remembered in this device's Keychain. After saving, launching from the Home Screen works without an Xcode Run token; Debug and Release both support saved grading access. Existing service instances read the saved credential on every new chat/grammar request, so replacement/removal needs no app restart. Saving a code does not automatically retry paid requests.

**Remove code** deletes this device's saved credential. It does not revoke someone else's copy or disable the developer's Debug environment token. A saved grading credential takes priority over that developer token; rejection of a saved code never silently falls back to developer access. Removing it restores the existing Debug fallback, if configured. Release has no embedded fallback credential.

## Rotate or end access

To replace the code, generate a fresh one, repeat `npx wrangler secret put XIAOLIAO_GRADING_TOKEN`, and deploy. Send the replacement privately; graders verify and save it over the previous one. To revoke grading entirely:

```sh
npx wrangler secret delete XIAOLIAO_GRADING_TOKEN
npx wrangler deploy
```

Keep `XIAOLIAO_CLIENT_TOKEN` and `OPENAI_API_KEY` if you still want developer access. The Worker checks authentication before serving cached responses as well as new requests. Requests already authorized/in flight may finish. There is no automatic expiration or separate code per grader in this prototype; rotating/deleting the shared code affects every holder. Removing an app may leave Keychain items behind: use **Remove code** for local cleanup and revoke at the server to end access.

## Troubleshooting and limits

- **Service has not been deployed / Not found:** redeploy the current `Backend` checkout; the older Worker lacks `/v1/access/check`.
- **Grading access is not configured:** confirm `XIAOLIAO_GRADING_TOKEN` is a Secret on the correct Worker. It must be 32–256 printable non-space ASCII characters, with no surrounding whitespace, and distinct from the developer/provider secrets.
- **Invalid or revoked:** obtain the current grading code. Keep all secret values out of screenshots, logs, Git and chat.
- **Cannot verify:** check connectivity and retry. A failed replacement check or failed Keychain write preserves the previous saved credential.
- **Secure storage unavailable:** unlock the device and retry. The app fails closed when secure storage cannot be read.
- **Verification succeeds but chat/grammar fails:** verification checks only the grading credential. It makes no OpenAI call and cannot confirm provider billing/model access, the Durable Object binding, or available quotas. Existing chat/grammar errors and explicit retries still apply.
- Chat and grammar share the existing global ceiling of 10 new provider attempts/minute and 200/UTC day across developer and grading access. Grammar also retains its 4/minute and 100/day ceiling. Failed provider attempts count. Verification consumes neither provider calls nor these quotas.

The code is sent only as an HTTPS Authorization header, never in URLs, conversation payloads, history, or UserDefaults. Storage uses a non-synchronizing [WhenUnlockedThisDeviceOnly Keychain item](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly). The entry field is masked and never displays the saved value. The English Grading Mode preference is independent of authentication. This shared prototype code does not provide production accounts, per-user ownership, or individual quotas.

## Validation and remaining Mac checks

All 37 backend tests passed locally with mocked provider/storage. Five new cases cover validation without AI calls, malformed configuration, shared quota/cache behavior, credential rotation/revocation and grading-only authentication. No live deployment or paid provider request was performed here.

Seven new Swift test methods cover code validation, endpoint/error mapping, saving/replacement failures, cancellation/removal races, and credentials changing on an existing service. An isolated UI regression covers save, relaunch, remove and reject with offline validation. Unit tests inject memory storage; UI tests use a UUID-specific Keychain service and never the person's credential. These native tests have not run on Linux.

On the Mac, build the app and run `GradingAccessTests` plus the existing reply/grammar/localization tests. Verify a real code once, terminate, then launch from the Home Screen without an Xcode token and send a typed practice message. Check chat and grammar, English errors, invalid-code handling, offline replacement preserving the saved code, removal, and server revocation followed by an explicit retry. Check the settings card with the keyboard, Dynamic Type and VoiceOver on iPhone/iPad.
