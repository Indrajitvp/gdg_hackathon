# GitMind - Zero-Friction Spaced Repetition 🧠

GitMind is a spaced repetition system built for a hackathon, utilizing an obscure but highly effective tech stack: **Elixir**, **Git (as a database)**, and **Telegram**.

## 1. The Core Concept (From the Basics)
Students forget 70% of what they study within a week. Existing tools like Anki solve this but fail because the setup friction is too high. 

**GitMind's Solution:**
1. **Zero Friction UI:** No app, no login. You just forward a message or send a voice note to a Telegram bot.
2. **AI Magic:** Gemini 1.5 analyzes the text/audio and slices it into bite-sized "Atomic Facts."
3. **The Obscure Database:** Instead of PostgreSQL, each fact is saved as a Markdown file and `git commit`ted to a bare Git repository. Your memory literally lives in your commit log!
4. **1-Click Review:** A daily cron job (via Supabase Edge Functions) sends you the facts you are mathematically about to forget. You click `[Forgot]`, `[Hard]`, or `[Easy]`, and Gemini recalculates the next review date.

## 2. Team Segregation & Roles
To build this fast without merge conflicts, the workload is strictly segregated between two engineers.

### 👤 Person A: The API & AI Engineer
**Focus:** Telegram Bot Integration and Gemini API.
*   **Task A1 (Telegram):** Setup the bot via BotFather. Build the Elixir webhook endpoint (`Plug`) to receive messages and voice notes.
*   **Task A2 (Gemini):** Write the HTTP client code (`Req` library) to send the user's data to Gemini. Craft Prompt 1 ("Slice this text into facts") and Prompt 2 ("Calculate the next review date based on user feedback").
*   **Task A3 (UI):** Write the code to send formatted Telegram messages with inline buttons (`[Forgot] [Hard] [Easy]`).

### 👤 Person B: The Engine Engineer
**Focus:** The Git Database engine, Concurrency, and Cron Jobs.
*   **Task B1 (Setup):** Initialize the Elixir supervision tree. Setup the local bare Git repository.
*   **Task B2 (Git DB):** Write the code that takes a Fact, formats it as Markdown with YAML frontmatter, writes it to disk, and executes the `git commit`.
*   **Task B3 (Concurrency):** Build an Elixir `GenServer` to act as a funnel. All incoming writes must go through this single process sequentially to prevent Git lock errors.
*   **Task B4 (Cron):** Write the Elixir function that scans all Markdown files for `next_review <= today`. Setup a Supabase Edge Function to trigger this daily.

## 3. The Tech Stack
*   **Backend:** Elixir (Erlang VM) for massive concurrency.
*   **Database:** Git (`libgit2` or raw `git` commands).
*   **Frontend:** Telegram Bot API.
*   **AI:** Google Gemini 1.5 Flash (for slicing and forgetting curve calculations).
*   **Hosting:** Render.com (Free tier).
*   **Cron Job:** Supabase Scheduled Edge Functions.
