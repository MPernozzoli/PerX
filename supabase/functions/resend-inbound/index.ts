import { createClient } from "@supabase/supabase-js";
import { Webhook } from "svix";

type ResendAddress = string | { email?: string; name?: string };

type ResendEmailData = {
  id?: string;
  email_id?: string;
  message_id?: string;
  from?: ResendAddress;
  to?: ResendAddress[] | ResendAddress;
  cc?: ResendAddress[] | ResendAddress;
  subject?: string;
  text?: string;
  html?: string;
  created_at?: string;
  received_at?: string;
  attachments?: unknown[];
};

type ResendWebhookEvent = {
  id?: string;
  type?: string;
  created_at?: string;
  data?: ResendEmailData;
};

const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

const normalizeAddress = (address: ResendAddress | undefined): string => {
  if (!address) return "";
  if (typeof address === "string") return address.trim().toLowerCase();
  return (address.email ?? "").trim().toLowerCase();
};

const normalizeAddressList = (addresses: ResendAddress[] | ResendAddress | undefined): string[] => {
  if (!addresses) return [];
  const list = Array.isArray(addresses) ? addresses : [addresses];
  return list.map(normalizeAddress).filter(Boolean);
};

const domainsFromRecipients = (recipients: string[]): string[] => {
  const domains = new Set<string>();
  for (const recipient of recipients) {
    const domain = recipient.split("@").at(1)?.toLowerCase();
    if (domain) domains.add(domain);
  }
  return Array.from(domains);
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET");

  if (!supabaseUrl || !serviceRoleKey || !webhookSecret) {
    return json({ error: "missing_function_secrets" }, 500);
  }

  const rawPayload = await req.text();
  let event: ResendWebhookEvent;

  try {
    const webhook = new Webhook(webhookSecret);
    event = webhook.verify(rawPayload, {
      "svix-id": req.headers.get("svix-id") ?? "",
      "svix-timestamp": req.headers.get("svix-timestamp") ?? "",
      "svix-signature": req.headers.get("svix-signature") ?? "",
    }) as ResendWebhookEvent;
  } catch {
    return json({ error: "invalid_signature" }, 400);
  }

  if (event.type !== "email.received") {
    return json({ status: "ignored", type: event.type ?? null });
  }

  const data = event.data ?? {};
  const toAddresses = normalizeAddressList(data.to);
  const ccAddresses = normalizeAddressList(data.cc);
  const recipientDomains = domainsFromRecipients([...toAddresses, ...ccAddresses]);

  if (recipientDomains.length === 0) {
    return json({ status: "ignored", reason: "missing_recipient_domain" }, 202);
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: domains, error: domainError } = await supabase
    .from("tenant_email_domains")
    .select("id, tenant_id, domain")
    .eq("provider", "resend")
    .eq("inbound_enabled", "true")
    .in("domain", recipientDomains)
    .limit(1);

  if (domainError) {
    return json({ error: "domain_lookup_failed", detail: domainError.message }, 500);
  }

  const matchedDomain = domains?.[0];
  if (!matchedDomain) {
    return json({ status: "ignored", reason: "unknown_recipient_domain", domains: recipientDomains }, 202);
  }

  const providerEventId = event.id ?? crypto.randomUUID();
  const receivedAt = data.received_at ?? data.created_at ?? event.created_at ?? new Date().toISOString();
  const inboundEventId = crypto.randomUUID();

  const inboundRecord = {
    id: inboundEventId,
    tenant_id: matchedDomain.tenant_id,
    domain_id: matchedDomain.id,
    provider: "resend",
    provider_event_id: providerEventId,
    provider_email_id: data.email_id ?? data.id ?? null,
    message_id: data.message_id ?? null,
    from_address: normalizeAddress(data.from),
    to_addresses: toAddresses,
    cc_addresses: ccAddresses,
    subject: data.subject ?? null,
    body_text: data.text ?? null,
    body_html: data.html ?? null,
    received_at: receivedAt,
    status: "queued",
    raw_payload: event,
    attachments_json: data.attachments ?? null,
  };

  const { data: insertedEvent, error: insertError } = await supabase
    .from("inbound_email_events")
    .insert(inboundRecord)
    .select("id, tenant_id")
    .single();

  if (insertError) {
    if (insertError.code === "23505") {
      return json({ status: "duplicate", provider_event_id: providerEventId });
    }
    return json({ error: "event_insert_failed", detail: insertError.message }, 500);
  }

  const { error: jobError } = await supabase.from("email_processing_jobs").insert({
    id: crypto.randomUUID(),
    tenant_id: insertedEvent.tenant_id,
    inbound_event_id: insertedEvent.id,
    status: "pending",
    priority: 10,
    input_json: inboundRecord,
  });

  if (jobError) {
    return json({ error: "job_insert_failed", detail: jobError.message }, 500);
  }

  return json({ status: "queued", inbound_event_id: insertedEvent.id });
});
