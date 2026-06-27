# AI Coding Rules for Accounting & Investment App

As an agentic coder working on this codebase, you must adhere to these structural constraints and design decisions to maintain compatibility and prevent regressions:

## 1. File Encoding
- **Encoding Constraint**: Ensure all source files (especially `Dashboard.vue`) are saved in **UTF-8 (without BOM)** format. 
- **Rationale**: The code contains active Unicode emojis (e.g., 🏦, 📈, ⚙️) in strings and templates. Saving with incorrect codepages (like UTF-16, ANSI, or bad BOMs) will corrupt these characters, resulting in blank labels or crash scripts in production.

## 2. ROI 折線圖 (Historical ROI Chart) Calculation rules
- **LOCF (Last Observation Carried Forward)**: When evaluating stock history across multiple tickers (e.g. US markets vs TW markets), if a date is missing prices for symbol A but has prices for B (due to market holidays), you must retrieve the last known closing price on or before that date. Skipping it will cause artificial -50% dips.
- **Pre-Purchase Exclusion**: Investments should only contribute value and cost to the overall ROI timeline from their specific `buy_date` onwards. Do not compare today's cost bases against historical price tickers before the buy date.
- **Trim Empty Space**: Slice the beginning of the chart dates array up to the first non-null index in the overall ROI dataset.

## 3. UI Styling & Theme Compatibility
- **Glassmorphism Badges**: The trend view uses high-fidelity glassmorphism-style chips with `linear-gradient` overlays and shadows. Do not change these to generic CSS classes or styles.
- **Text Visibility**: Keep inline styles theme-resilient. Avoid hardcoding text background colours to absolute white `#ffffff` or black `#000000` alongside themes `var(--color-text)`, as this causes visual "invisible text" bugs when themes toggle.
- **Label Flex Isolation**: In custom scrollable select boxes (like manage group checklist), wrap options in robust `div` elements instead of direct flex-labels. This protects the children labels from CSS parent flex compression bugs.

## 4. Group State Persistence (Safety Net)
- **Database Race Conditions**: Group additions use Supabase writes. Because page reloads might catch Supabase before the async write finishes, always query the local `localStorage` map (e.g., `localInvMap`) to merge back `custom_group` settings if Supabase returns empty strings.
- **No Form Resets**: In `selectSubtype`, do not clear `newAsset.value.custom_group`. Maintain the inherited `activeCustomGroup.value` so the asset category modal flow works properly.

## 5. Dashboard.vue (7,200+ Lines) Development Guide
- **Do NOT attempt to rewrite the entire `Dashboard.vue` file** in one output. Doing so will exceed the AI's output tokens. Use target line edits (e.g. search-and-replace tool) to replace specific blocks.
- **Ignore Unused Components**: Ignore files like `Assets.vue`, `Investments.vue`, `Transactions.vue`, `QuickAdd.vue`, `ExpenseList.vue` unless explicitly asked to refactor them. Only edit `Dashboard.vue` and `BottomNav.vue`.
- **Key State Reference**:
  - `accounts`: Array of liquid/liability accounts.
  - `investments`: Array of stock/crypto holding lots.
  - `usdTwdRate`: Currency conversion rate.
  - `activeCustomGroup`: Current filtering custom group (e.g. '台股', '美股').
- **Key Chart Computed Properties**:
  - `roiHistoryChartData`: Computes the historical ROI timeline.
  - `trendChartData`: Computes the overall Net Worth history chart.
  - `statsChartData`: Computes monthly Income vs Expenses.
- **Key Sync Functions**:
  - `fetchAllData()`: Triggers SWR flow, merges Supabase with local cache mapping (`localInvMap`).

