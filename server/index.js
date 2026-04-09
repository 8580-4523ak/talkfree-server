"use strict";

const fs = require("fs");
const path = require("path");

const envPath = path.join(__dirname, ".env");
require("dotenv").config({ path: envPath });

const express = require("express");
const cors = require("cors");
const twilio = require("twilio");

const {
  TWILIO_ACCOUNT_SID,
  TWILIO_AUTH_TOKEN,
  TWILIO_API_KEY_SID,
  TWILIO_API_KEY_SECRET,
  TWILIO_TWIML_APP_SID,
  TWILIO_APP_SID,
  TWILIO_CALLER_ID,
  PORT = 3000,
} = process.env;

const OUTGOING_APP_SID = String(
  TWILIO_TWIML_APP_SID || TWILIO_APP_SID || "",
).trim();

const app = express();
app.use((req, res, next) => {
  console.log("Incoming:", req.method, req.url);
  next();
});
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

app.get("/", (req, res) => {
  res.send("Server is alive");
});

app.use(express.static(path.join(__dirname, "public")));

function requireEnv(name, val) {
  if (!val || String(val).trim() === "") {
    throw new Error(`Missing env: ${name}`);
  }
}

try {
  requireEnv("TWILIO_ACCOUNT_SID", TWILIO_ACCOUNT_SID);
  requireEnv("TWILIO_AUTH_TOKEN", TWILIO_AUTH_TOKEN);
  requireEnv("TWILIO_CALLER_ID", TWILIO_CALLER_ID);
  requireEnv("TWILIO_API_KEY_SID", TWILIO_API_KEY_SID);
  requireEnv("TWILIO_API_KEY_SECRET", TWILIO_API_KEY_SECRET);
  requireEnv("TWILIO_TWIML_APP_SID or TWILIO_APP_SID", OUTGOING_APP_SID);
} catch (e) {
  console.error(e.message);
  const examplePath = path.join(__dirname, ".env.example");
  if (!fs.existsSync(envPath)) {
    console.error(`\nNo file at: ${envPath}`);
    console.error(`Copy .env.example to .env in this folder, then fill in your Twilio values.`);
  } else {
    console.error(`\nEdit ${envPath} — one or more required variables are empty.`);
  }
  if (fs.existsSync(examplePath)) {
    console.error(`Template: ${examplePath}`);
  }
  process.exit(1);
}

const twilioClient = twilio(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN);

const AccessToken = twilio.jwt.AccessToken;
const VoiceGrant = AccessToken.VoiceGrant;

app.all("/voice", (req, res) => {
  console.log("🔥 Twilio hit /voice endpoint");

  res.type("text/xml");
  res.send(`     <Response>       <Say voice="alice">Hello Akash, your TalkFree server is working!</Say>     </Response>
  `);
});

app.get("/call", async (req, res) => {
  try {
    const to = req.query.to;

    if (!to) {
      return res.send("Missing ?to= number");
    }

    await twilioClient.calls.create({
      to: String(to).trim(),
      from: process.env.TWILIO_CALLER_ID,
      url: "https://talkfree-server.onrender.com/voice",
    });

    res.send("Call triggered successfully");
  } catch (err) {
    console.error(err);
    res.send("Error: " + err.message);
  }
});

app.get("/token", (req, res) => {
  const identity = String(req.query.identity || "anonymous").slice(0, 128);
  const token = new AccessToken(
    TWILIO_ACCOUNT_SID,
    TWILIO_API_KEY_SID,
    TWILIO_API_KEY_SECRET,
    { identity },
  );
  const grant = new VoiceGrant({
    outgoingApplicationSid: OUTGOING_APP_SID,
    incomingAllow: true,
  });
  token.addGrant(grant);
  res.json({ identity, token: token.toJwt() });
});

app.post("/call", (req, res) => {
  const to = req.body.To || req.body.to;
  const vr = new twilio.twiml.VoiceResponse();
  if (!to) {
    vr.say({ voice: "alice" }, "No destination number.");
  } else {
    const dial = vr.dial({ callerId: TWILIO_CALLER_ID });
    dial.number(to);
  }
  res.type("text/xml");
  res.send(vr.toString());
});

const server = app.listen(Number(PORT), () => {
  console.log(`TalkFree voice server listening on port ${PORT}`);
});
server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(`Port ${PORT} is already in use. Change PORT in .env or stop the other process.`);
    if (String(PORT) === "3000") {
      console.error("From server folder try: npm run free-port   then   npm start");
    }
    console.error(
      "PowerShell: Get-NetTCPConnection -LocalPort " +
        PORT +
        " -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }",
    );
    process.exit(1);
  }
  throw err;
});
