const port = process.argv[2] || '61253';
const url = process.argv[3] || 'http://localhost:7357';

async function main() {
  const res = await fetch(`http://localhost:${port}/json`);
  const targets = await res.json();
  const page = targets.find(t => t.type === 'page');
  if (!page) { console.log('NO_PAGE'); process.exit(1); }
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  ws.send(JSON.stringify({ id: 1, method: 'Page.enable' }));
  ws.send(JSON.stringify({ id: 2, method: 'Page.navigate', params: { url } }));
  setTimeout(() => { console.log('NAVIGATED to ' + url); process.exit(0); }, 3000);
}
main().catch(e => { console.error(e.message); process.exit(1); });
