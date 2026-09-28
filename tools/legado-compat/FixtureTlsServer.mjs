import fs from 'node:fs';
import https from 'node:https';

const port = Number(process.argv[2] || '18766');
const certificatePath = process.argv[3] || '';
const privateKeyPath = process.argv[4] || '';

if (!Number.isInteger(port) || port < 1 || port > 65535 || !certificatePath || !privateKeyPath) {
  process.stderr.write('Invalid TLS fixture arguments.\n');
  process.exit(2);
}

const server = https.createServer({
  cert: fs.readFileSync(certificatePath),
  key: fs.readFileSync(privateKeyPath)
}, (request, response) => {
  if (request.url !== '/tls-observation') {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('fixture-not-found');
    return;
  }

  const socket = request.socket;
  const cipher = socket.getCipher();
  const payload = {
    marker: 'fixture-tls-observation-v1',
    protocol: socket.getProtocol() || '',
    httpVersion: request.httpVersion,
    alpnPresent: Boolean(socket.alpnProtocol),
    cipherPresent: Boolean(cipher && cipher.name)
  };
  response.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(payload));
});

server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`LEGADO_TLS_FIXTURE_READY:${port}\n`);
});

function shutdown() {
  server.close(() => process.exit(0));
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
