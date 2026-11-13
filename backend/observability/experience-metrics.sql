SET statement_timeout = '5s';
SELECT '# HELP tatuzin_experience_events_24h Client-reported events received in the last 24 hours for the pilot version.';
SELECT '# TYPE tatuzin_experience_events_24h gauge';
WITH names(name) AS (VALUES ('registration_completed'), ('product_created'), ('cash_opened'),
  ('checkout_started'), ('checkout_completed'), ('checkout_exited'), ('checkout_failed'),
  ('plans_viewed'), ('subscription_started'))
SELECT format('tatuzin_experience_events_24h{event="%s"} %s', names.name, COUNT(events.id))
FROM names LEFT JOIN "ProductJourneyEvent" events ON events.name = names.name
  AND events."receivedAt" >= NOW() - INTERVAL '24 hours'
  AND events."appVersion" = '1.0.1-pilot'
GROUP BY names.name ORDER BY names.name;

SELECT '# HELP tatuzin_experience_checkout_median_seconds_24h Median client-reported duration of all completed pilot checkouts, not only simple sales. NaN without data.';
SELECT '# TYPE tatuzin_experience_checkout_median_seconds_24h gauge';
SELECT 'tatuzin_experience_checkout_median_seconds_24h ' ||
  COALESCE((percentile_cont(0.5) WITHIN GROUP (ORDER BY "durationMs") / 1000.0)::text, 'NaN')
FROM "ProductJourneyEvent"
WHERE name = 'checkout_completed' AND "receivedAt" >= NOW() - INTERVAL '24 hours'
  AND "appVersion" = '1.0.1-pilot';
