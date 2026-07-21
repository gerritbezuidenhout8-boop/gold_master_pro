# Background alerts (optional, ~$0 on free tiers)

In-app alerts already work: while GMP is open, `AlertWatcher` evaluates
the live price and pops a SnackBar on a crossing. **Background** delivery
(alert fires while the app is closed) can't run on the device — a phone
OS suspends the app — so it needs a tiny always-on service. This design
stays within free tiers.

## Architecture

```
Binance public price ─▶ Cloudflare Worker (cron, every 1 min)
                          │  reads armed rules + FCM tokens from KV/Firestore
                          │  reuses the SAME crossing rule as AlertEngine.fires
                          ▼
                        Firebase Cloud Messaging ─▶ device push
```

Two prerequisites, both needing YOUR account login (can't be automated):

1. **Rules + token must reach the server.** Today alerts live on-device.
   To evaluate them server-side, mirror each rule and the device's FCM
   token to a store the Worker can read — Cloudflare **KV** (free: 100k
   reads/day) or Firestore (if you did docs/firebase_setup.md).
2. **FCM** for the actual push (free, unlimited) — needs the Firebase
   project + `firebase_messaging` in the app to obtain a device token.

## Cloudflare Worker (free plan: 100k req/day, 3 crons, 1-min minimum)

`wrangler.toml`:

```toml
name = "gmp-alert-watcher"
main = "src/worker.js"
compatibility_date = "2026-01-01"
kv_namespaces = [{ binding = "ALERTS", id = "<your-kv-id>" }]
[triggers]
crons = ["* * * * *"]           # every minute
```

`src/worker.js` — note the crossing test is identical to
`lib/alerts/alert_engine.dart`, so behaviour matches the in-app path:

```js
export default {
  async scheduled(event, env) {
    const res = await fetch(
      'https://data-api.binance.vision/api/v3/ticker/price?symbol=PAXGUSDT');
    const price = parseFloat((await res.json()).price);

    const prev = parseFloat(await env.ALERTS.get('lastPrice')) || price;
    await env.ALERTS.put('lastPrice', String(price));

    const rules = JSON.parse(await env.ALERTS.get('rules') || '[]');
    for (const r of rules) {
      const armed = r.enabled && !r.triggeredAt;
      const fired = armed && (
        (r.kind === 'priceAbove' && prev < r.threshold && price >= r.threshold) ||
        (r.kind === 'priceBelow' && prev > r.threshold && price <= r.threshold));
      if (!fired) continue;
      r.triggeredAt = new Date().toISOString();
      await sendPush(env, r, price);
    }
    await env.ALERTS.put('rules', JSON.stringify(rules));
  },
};

async function sendPush(env, rule, price) {
  // POST to FCM HTTP v1 with an OAuth token minted from the service
  // account (store the JSON as a Worker secret). Body: notification
  // { title: 'Gold alert', body: `Gold ${rule.kind} ${rule.threshold} (now ${price})` }
  // to the stored device token.
}
```

Deploy:

```sh
npm install -g wrangler
wrangler login                 # opens the browser, your Cloudflare account
wrangler kv:namespace create ALERTS
wrangler deploy
```

## Cost guard

Free tiers only: Worker 100k req/day (1-min cron = ~1,440/day), KV 100k
reads/day, FCM unlimited. No card required for the Workers free plan.
One-minute granularity is plenty for price alerts; if you later want
tick-accuracy, move to a small always-on socket server instead.
