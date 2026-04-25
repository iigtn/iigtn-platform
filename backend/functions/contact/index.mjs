// ============================================================================
// Contact Form Lambda Handler
// ----------------------------------------------------------------------------
// POST /api/contact
//
// 入力 (JSON body):
//   { name: string, email: string, message: string }
//
// 動作:
//   1. 入力バリデーション
//   2. DynamoDB にレコード保存 (PK: UUID v4)
//   3. SES でメール送信（環境変数が揃っている場合のみ。sandbox 失敗時は warn ログ）
//   4. JSON レスポンスを返す
//
// ランタイム: Node.js 20.x (AWS SDK v3 がランタイムに同梱されている前提で
// 外部依存なし)
// ============================================================================
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { SESv2Client, SendEmailCommand } from "@aws-sdk/client-sesv2";
import { randomUUID } from "node:crypto";

// ── クライアント初期化 (ハンドラ外 = 同一コンテナで再利用される) ──────────
const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);
const sesClient = new SESv2Client({});

// ── 環境変数 ────────────────────────────────────────────────────────────
const TABLE_NAME = process.env.DDB_TABLE;
const SES_FROM = process.env.SES_FROM;     // 送信元 (検証済アドレス)
const SES_TO = process.env.SES_TO;         // 受信先 (sandbox では検証済必須)
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || "*";

// ── 共通レスポンスヘッダ (CORS + Security) ───────────────────────────────
const corsHeaders = {
  "Content-Type": "application/json; charset=utf-8",
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "300",
  // セキュリティ系
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

const respond = (statusCode, body) => ({
  statusCode,
  headers: corsHeaders,
  body: JSON.stringify(body),
});

// ── 入力バリデーション ─────────────────────────────────────────────────
//   email: ざっくり regex (RFC 完全準拠は不要、ある程度形になっていれば OK)
//   length: name 1-100, email 5-254, message 10-5000
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function validate(payload) {
  const errors = [];
  if (!payload || typeof payload !== "object") {
    errors.push("Body must be a JSON object");
    return errors;
  }
  const { name, email, message } = payload;

  if (typeof name !== "string" || name.trim().length < 1 || name.length > 100) {
    errors.push("name must be 1-100 chars");
  }
  if (typeof email !== "string" || email.length < 5 || email.length > 254 || !EMAIL_RE.test(email)) {
    errors.push("email is invalid");
  }
  if (typeof message !== "string" || message.trim().length < 10 || message.length > 5000) {
    errors.push("message must be 10-5000 chars");
  }
  return errors;
}

// ── ハンドラ ───────────────────────────────────────────────────────────
export const handler = async (event) => {
  // OPTIONS (preflight) は即返す
  if (event.requestContext?.http?.method === "OPTIONS") {
    return respond(204, "");
  }

  // POST 以外は弾く
  if (event.requestContext?.http?.method !== "POST") {
    return respond(405, { error: "Method Not Allowed" });
  }

  // ── 1. 入力パース ────────────────────────────────────────────────
  let payload;
  try {
    payload = JSON.parse(event.body ?? "{}");
  } catch {
    return respond(400, { error: "Body must be valid JSON" });
  }

  // ── 2. バリデーション ────────────────────────────────────────────
  const errors = validate(payload);
  if (errors.length > 0) {
    return respond(400, { error: "Validation failed", details: errors });
  }

  // ── 3. DDB に保存 ────────────────────────────────────────────────
  const id = randomUUID();
  const now = new Date().toISOString();
  const item = {
    id,
    name: payload.name.trim(),
    email: payload.email.trim().toLowerCase(),
    message: payload.message.trim(),
    created_at: now,
    source_ip: event.requestContext?.http?.sourceIp ?? null,
    user_agent: event.headers?.["user-agent"] ?? null,
  };

  try {
    await ddb.send(new PutCommand({ TableName: TABLE_NAME, Item: item }));
  } catch (err) {
    console.error("DDB Put failed", { id, err: err.message });
    return respond(500, { error: "Failed to persist message" });
  }

  // ── 4. SES でメール送信 (失敗しても致命的扱いはしない) ─────────────
  if (SES_FROM && SES_TO) {
    try {
      // CloudWatch Logs に PII を残さない: 本文は DDB にのみ
      const emailBody = [
        `New contact submission`,
        `ID: ${id}`,
        `Time: ${now}`,
        `Name: ${item.name}`,
        `Email: ${item.email}`,
        `Source IP: ${item.source_ip}`,
        ``,
        `Message:`,
        item.message,
      ].join("\n");

      await sesClient.send(new SendEmailCommand({
        FromEmailAddress: SES_FROM,
        Destination: { ToAddresses: [SES_TO] },
        Content: {
          Simple: {
            Subject: { Data: `[iigtn] New contact: ${item.name}`, Charset: "UTF-8" },
            Body: { Text: { Data: emailBody, Charset: "UTF-8" } },
          },
        },
      }));
    } catch (err) {
      // sandbox 制限などで送信失敗 → ログだけ残し、フロントには成功扱い
      // (DDB には保存されているのでデータは失われない)
      console.warn("SES SendEmail failed (continuing)", {
        id,
        err: err.name,
        msg: err.message,
      });
    }
  } else {
    console.log("SES env vars not set, skipping email", { id });
  }

  // ── 5. 成功レスポンス ────────────────────────────────────────────
  // ID は返さない方針（攻撃者にエンティティ存在を漏らさない）
  return respond(200, { ok: true });
};
