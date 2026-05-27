---
name: cloudbase-test-site-deploy
description: Use this when deploying or updating a small Node.js/HTML test website to Tencent CloudBase for China-accessible testing. Provides a CLI-first workflow, avoids the flaky Tencent CloudBase web console, creates or reuses an HTTP access service, protects secrets, and verifies the public test URL.
metadata:
  short-description: Deploy small test sites to Tencent CloudBase
---

# CloudBase Test Site Deploy

Use this skill to publish a small Node.js/HTML prototype as a Tencent CloudBase test website.

## App Requirements

The project should have:

- `index.js` exporting `exports.main = async (event) => ...`
- static files such as `index.html`, `styles.css`, `app.js`
- optional `.env` for server-side secrets
- hidden-file protection so files such as `.env` cannot be served publicly

For web apps mounted under a service path such as `/demo`, the function should strip that prefix before routing requests.

## Fast Path

Run:

```bash
PROJECT_DIR=/path/to/project \
ENV_ID=your-cloudbase-env-id \
FUNCTION_NAME=your-function-name \
SERVICE_PATH=/demo \
SERVICE_URL=https://your-public-url/demo \
/path/to/this/skill/scripts/deploy_cloudbase_test.sh
```

If `SERVICE_URL` is omitted, the script still deploys. Verification is strongest when `SERVICE_URL` is supplied.

## Workflow

1. Use CloudBase CLI, not the web console.
2. Check syntax with Node.
3. Confirm CloudBase CLI login. If not logged in, run `tcb login` and authorize in the browser.
4. Deploy as an ordinary Event SCF, not HTTP function:
   - runtime: `Nodejs18.15` by default
   - handler inferred from `index.js` as `index.main`
5. Create HTTP access service with `tcb service create -p "$SERVICE_PATH" -f "$FUNCTION_NAME"` only if missing.
6. Verify:
   - public page returns 200
   - CSS and JS return 200 when present
   - `.env` returns 404 or 403
   - optional API smoke test succeeds

## Known CloudBase Notes

- `fn deploy --httpFn --path /` may create a URL that returns `FUNCTION_PARAM_INVALID`.
- Route commands using `WEB_SCF` may report success but still fail at the gateway.
- The most reliable path for small prototypes is:
  - ordinary Event SCF
  - `tcb service create`
- Default `*.app.tcloudbase.com` domains may show Tencent's “确实要继续吗” interstitial. Removing it requires a custom ICP-filed domain.

## Cost And Secret Safety

- Never print API keys or `.env` values.
- Keep `.env` out of Git.
- Add a test access code before sharing widely.
- Rotate any LLM provider key that appears in logs, screenshots, or chat.
