```bash
curl -X POST \
  "https://<YOUR_SUPABASE_PROJECT_ID>.supabase.co/functions/v1/send-push?forceSeries=true" \
  -H "Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>" \
  -H "Content-Type: application/json"
```