<div align="center">
  <h1>🧠 Synapse</h1>
  <p><b>Zero-Friction Spaced Repetition built directly into Discord & WhatsApp.</b></p>
  <p><i>A GDG Hackathon Submission</i></p>

  <br />

  <table align="center">
    <tr>
      <td align="center"><h3><a href="https://discord.com/oauth2/authorize?client_id=1518276830723969127&permissions=274877959168&scope=bot">🤖 CLICK HERE TO ADD BOT TO DISCORD (LIVE PROD)</a></h3></td>
    </tr>
    <tr>
      <td align="center"><a href="https://gdg-hackathon-6ixq.onrender.com/health">🟢 View Production Backend Status (Render)</a></td>
    </tr>
  </table>

  <br />
</div>

---

## 🛑 The Problem
The human brain forgets approximately **70% of new information within 24 hours**. 

Mathematical "Spaced Repetition" systems (like Anki) solve this problem flawlessly, but they suffer from **massive user friction**. Students have to manually format, type, and organize hundreds of flashcards. Because the friction is so high, most people abandon the habit entirely.

## 📱 How to Use It
Synapse eliminates 100% of the friction by integrating the entire learning pipeline directly into the app you already use every day: **Discord**.

1. **Zero-Friction Ingestion:** Read an interesting article on your phone? Just copy the massive wall of text and drop it directly into a Discord DM with the Synapse bot.
2. **Instant Extraction:** In seconds, Synapse replies confirming that it has used AI to automatically extract all the key facts from your text and created smart flashcards.
3. **The Daily Review:** On the exact day you are mathematically predicted to forget a fact, the bot DMs you.
4. **Interactive Buttons:** Attached to the DM are three simple buttons (`🔴 Forgot`, `🟡 Hard`, `🟢 Easy`). You tap a button right there in the chat, the math recalculates in milliseconds, and the database updates. 

You never type a flashcard. You never leave Discord. You just drop text and tap buttons.

---

## 🏗️ Technical Architecture (Under The Hood)

We specifically chose a stack that could handle immense concurrency and real-time WebSocket connections without breaking a sweat.

* **Backend / Concurrency:** `Elixir` & the Erlang VM. Using the `WebSockex` library, we maintain a persistent, non-blocking WebSocket connection directly to the Discord Gateway.
* **Database:** `Supabase (PostgreSQL)`. Managed via Elixir's `Ecto` wrapper with a direct connection pool.
* **NLP Pipeline:** `Google Gemini API`. We strictly enforce `application/json` response schemas to prevent LLM hallucinations, ensuring we only get structural flashcard data back.
* **Algorithm:** `SuperMemo-2`. The forgetting curve math is executed entirely locally on the Elixir backend, resolving button interactions in under 50ms without relying on slow external APIs.

---

## 🚀 How to Run Locally

### 1. Prerequisites
- Windows OS (or Linux/Mac with bash)
- `Elixir` (~> 1.14) and `Erlang` installed.

### 2. Environment Variables
Create a `.env` file in the root directory with the following keys:
```env
DISCORD_BOT_TOKEN="your_discord_bot_token"
DATABASE_URL="postgresql://postgres:[PASSWORD]@aws-0-region.pooler.supabase.com:5432/postgres?pool_mode=session"
GEMINI_API_KEY="your_gemini_api_key"
```
*(Note: Supabase Connection Pooler must use `?pool_mode=session` for Ecto migrations to work).*

### 3. Boot the Server
We wrote a custom PowerShell wrapper to automatically load environment variables, install package managers, run database migrations, and boot the WebSocket server.
```powershell
cd gitmind
.\run.ps1
```

---

## 🟢 WhatsApp Integration

While our live demo is running on Discord, our Elixir architecture was intentionally designed to be **frontend-agnostic**. The backend logic is already fully decoupled and supports the **WhatsApp Business Cloud API**. 

To use the WhatsApp bot instead of Discord, you simply need to provide your Meta Developer keys in the `.env` file:

```env
WHATSAPP_TOKEN="your_meta_whatsapp_token"
WHATSAPP_PHONE_NUMBER_ID="your_phone_id"
```

Once the keys are added, students can:
1. Forward massive text chains directly to the Synapse WhatsApp number.
2. Receive their daily flashcards via SMS push notifications.
3. Grade their memory directly from their lock screen using Meta's interactive webhook buttons.

Because the SuperMemo-2 algorithm and Ecto database are decoupled from the gateway, the backend dynamically handles both platforms simultaneously.
