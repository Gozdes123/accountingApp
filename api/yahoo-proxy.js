// Vercel Serverless Function to proxy Yahoo Finance API and bypass CORS
export default async function handler(req, res) {
  // CORS Headers for API accessibility
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

  // Handle OPTIONS request for CORS preflight
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  const { symbol, symbols } = req.query;

  // ── Batch mode: ?symbols=AAPL,2330.TW,BTC-USD ───────────────────
  if (symbols) {
    const symList = symbols.split(',').map(s => s.trim()).filter(Boolean);
    if (symList.length === 0) {
      res.status(400).json({ error: 'symbols parameter is empty' });
      return;
    }

    try {
      const yhUrl = `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${encodeURIComponent(symList.join(','))}&fields=regularMarketPrice,currency,shortName`;
      const response = await fetch(yhUrl, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
          'Accept-Language': 'zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
          'Referer': 'https://finance.yahoo.com/',
          'Origin': 'https://finance.yahoo.com'
        }
      });

      if (!response.ok) {
        res.status(response.status).json({ error: `Failed to fetch from Yahoo Finance: ${response.statusText}` });
        return;
      }

      const data = await response.json();
      // Return a map: { symbol -> regularMarketPrice }
      const result = {};
      const quotes = data?.quoteResponse?.result ?? [];
      for (const q of quotes) {
        if (q.symbol && q.regularMarketPrice != null) {
          result[q.symbol] = q.regularMarketPrice;
        }
      }
      res.status(200).json({ prices: result });
      return;
    } catch (error) {
      res.status(500).json({ error: error.message });
      return;
    }
  }

  // ── Single mode: ?symbol=AAPL (backward compatible) ─────────────
  if (!symbol) {
    res.status(400).json({ error: 'symbol or symbols parameter is required' });
    return;
  }

  try {
    const yhUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?interval=1d&range=1d`;
    const response = await fetch(yhUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'zh-TW,zh;q=0.9,en-US;q=0.8,en;q=0.7',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Referer': 'https://finance.yahoo.com/',
        'Origin': 'https://finance.yahoo.com'
      }
    });

    if (!response.ok) {
      res.status(response.status).json({ error: `Failed to fetch from Yahoo Finance: ${response.statusText}` });
      return;
    }

    const data = await response.json();
    res.status(200).json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}
