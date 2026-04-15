type JSONValue =
  | string
  | number
  | boolean
  | null
  | JSONValue[]
  | { [key: string]: JSONValue };

type RegisterPayload = {
  nodeID: string;
  publicKey: string;
  wgPublicKey?: string;
  displayName: string;
  capabilities: JSONValue;
  signature: string;
};

type DiscoverPayload = {
  requestingNodeID: string;
};

type TargetedPayload = {
  fromNodeID: string;
  toNodeID: string;
  sessionID: string;
};

type RelayPeer = {
  ws: ServerWebSocket<unknown>;
  nodeID: string;
  publicKey: string;
  wgPublicKey?: string;
  displayName: string;
  capabilities: JSONValue;
  lastSeenReferenceSeconds: number;
};

type RelayMessage = Record<string, JSONValue>;

const port = Number(Bun.env.PORT ?? "8080");
const referenceDateSeconds = Date.parse("2001-01-01T00:00:00Z") / 1000;
const peers = new Map<string, RelayPeer>();
const sockets = new WeakMap<ServerWebSocket<unknown>, string>();
const rateLimits = new Map<string, { lastDiscover: number; lastRegister: number }>();

// Metrics
const startTime = Date.now();
let messageCount = 0;
let messageCountAtLastMinute = 0;
let lastMinuteTimestamp = Date.now();
let relaySessionCount = 0;

function nowReferenceSeconds(): number {
  return Date.now() / 1000 - referenceDateSeconds;
}

function send(ws: ServerWebSocket<unknown>, message: RelayMessage) {
  ws.send(JSON.stringify(message));
}

function peerInfo(peer: RelayPeer) {
  return {
    nodeID: peer.nodeID,
    publicKey: peer.publicKey,
    wgPublicKey: peer.wgPublicKey ?? null,
    displayName: peer.displayName,
    capabilities: peer.capabilities,
    lastSeen: peer.lastSeenReferenceSeconds,
    natType: "unknown",
    endpoints: []
  };
}

function sendError(ws: ServerWebSocket<unknown>, code: string, errorMessage: string, extra?: Record<string, JSONValue>) {
  send(ws, {
    error: {
      code,
      message: errorMessage,
      ...extra
    }
  });
}

function checkRateLimit(nodeID: string, kind: "discover" | "register"): number | null {
  const now = Date.now();
  const limits = rateLimits.get(nodeID) ?? { lastDiscover: 0, lastRegister: 0 };
  const minInterval = kind === "discover" ? 10_000 : 30_000;
  const lastTime = kind === "discover" ? limits.lastDiscover : limits.lastRegister;

  if (now - lastTime < minInterval) {
    return Math.ceil((minInterval - (now - lastTime)) / 1000);
  }

  if (kind === "discover") limits.lastDiscover = now;
  else limits.lastRegister = now;
  rateLimits.set(nodeID, limits);
  return null;
}

function forwardToTarget(kind: string, payload: TargetedPayload & Record<string, JSONValue>, sender: ServerWebSocket<unknown>) {
  const target = peers.get(payload.toNodeID);
  if (!target) {
    sendError(sender, "peer_not_found", `Peer ${payload.toNodeID} is not connected`);
    return;
  }

  send(target.ws, {
    [kind]: payload
  });
}

function handleRegister(ws: ServerWebSocket<unknown>, payload: RegisterPayload) {
  if (!payload?.nodeID) {
    sendError(ws, "invalid_register", "Missing nodeID in register payload");
    return;
  }

  const retryAfter = checkRateLimit(payload.nodeID, "register");
  if (retryAfter !== null) {
    sendError(ws, "rate_limited", `Register rate limited, retry after ${retryAfter}s`, { retryAfterSeconds: retryAfter });
    return;
  }

  console.log(`[register] nodeID=${payload.nodeID.substring(0, 16)}... displayName=${payload.displayName} peers_before=${peers.size}`);
  const existing = peers.get(payload.nodeID);
  // Store the new peer BEFORE closing the old connection to prevent race conditions.
  // If we close first, the close handler could fire synchronously and remove the peer
  // before the new registration is stored.
  const peer: RelayPeer = {
    ws,
    nodeID: payload.nodeID,
    publicKey: payload.publicKey,
    wgPublicKey: payload.wgPublicKey,
    displayName: payload.displayName,
    capabilities: payload.capabilities,
    lastSeenReferenceSeconds: nowReferenceSeconds()
  };

  peers.set(payload.nodeID, peer);
  sockets.set(ws, payload.nodeID);

  // Close old connection AFTER the new peer is stored, so the close handler
  // sees peer.ws !== old_ws and skips removal.
  if (existing && existing.ws !== ws) {
    console.log(`[register] replacing existing session for ${payload.nodeID.substring(0, 16)}...`);
    existing.ws.close(1012, "Replaced by newer session");
  }

  send(ws, {
    registerAck: {
      nodeID: payload.nodeID,
      registeredAt: peer.lastSeenReferenceSeconds,
      ttlSeconds: 300
    }
  });
}

function handleDiscover(ws: ServerWebSocket<unknown>, payload: DiscoverPayload) {
  const retryAfter = checkRateLimit(payload.requestingNodeID, "discover");
  if (retryAfter !== null) {
    sendError(ws, "rate_limited", `Discover rate limited, retry after ${retryAfter}s`, { retryAfterSeconds: retryAfter });
    return;
  }

  let result = Array.from(peers.values())
    .filter((peer) => peer.nodeID !== payload.requestingNodeID);

  const filter = payload.filter as Record<string, any> | undefined;
  if (filter) {
    if (filter.modelID) {
      result = result.filter((p) => {
        const caps = p.capabilities as any;
        return Array.isArray(caps?.loadedModels) && caps.loadedModels.includes(filter.modelID);
      });
    }
    if (typeof filter.minRAMGB === "number") {
      result = result.filter((p) => {
        const hw = (p.capabilities as any)?.hardware;
        return hw && typeof hw.totalRAMGB === "number" && hw.totalRAMGB >= filter.minRAMGB;
      });
    }
    if (typeof filter.minTier === "number") {
      result = result.filter((p) => {
        const hw = (p.capabilities as any)?.hardware;
        return hw && typeof hw.tier === "number" && hw.tier <= filter.minTier;
      });
    }
  }

  const maxPeers = (typeof (filter as any)?.maxPeers === "number") ? (filter as any).maxPeers : 50;
  if (result.length > maxPeers) {
    // Fisher-Yates shuffle, then take first maxPeers
    for (let i = result.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [result[i], result[j]] = [result[j], result[i]];
    }
    result = result.slice(0, maxPeers);
  }

  send(ws, {
    discoverResponse: {
      peers: result.map(peerInfo)
    }
  });
}

function handleMessage(ws: ServerWebSocket<unknown>, rawMessage: string | Buffer) {
  messageCount++;

  let message: RelayMessage;
  try {
    message = JSON.parse(rawMessage.toString());
  } catch {
    sendError(ws, "invalid_json", "Could not decode relay message");
    return;
  }

  const entry = Object.entries(message)[0];
  if (!entry) {
    sendError(ws, "invalid_message", "Empty relay message");
    return;
  }

  const [kind, rawPayload] = entry as [string, any];

  // Support both flat JSON and Swift's auto-synthesized {"_0": {...}} wrapper format.
  const payload = rawPayload?._0 ?? rawPayload;

  console.log(`[msg] kind=${kind} from=${sockets.get(ws)?.substring(0, 16) ?? "unknown"}...`);

  switch (kind) {
    case "register":
      handleRegister(ws, payload as RegisterPayload);
      break;

    case "discover":
      handleDiscover(ws, payload as DiscoverPayload);
      break;

    case "offer":
    case "answer":
    case "iceCandidate":
    case "relayReady":
    case "relayData":
      forwardToTarget(kind, payload as TargetedPayload & Record<string, JSONValue>, ws);
      break;

    case "relayOpen":
      relaySessionCount++;
      forwardToTarget(kind, payload as TargetedPayload & Record<string, JSONValue>, ws);
      break;

    case "relayClose":
      relaySessionCount = Math.max(0, relaySessionCount - 1);
      forwardToTarget(kind, payload as TargetedPayload & Record<string, JSONValue>, ws);
      break;

    default:
      sendError(ws, "unsupported_message", `Unsupported relay message: ${kind}`);
      break;
  }
}

function handleClose(ws: ServerWebSocket<unknown>) {
  const nodeID = sockets.get(ws);
  if (!nodeID) {
    console.log(`[close] unknown websocket closed`);
    return;
  }

  console.log(`[close] nodeID=${nodeID.substring(0, 16)}... peers_before=${peers.size}`);
  sockets.delete(ws);
  const peer = peers.get(nodeID);
  if (!peer || peer.ws !== ws) {
    console.log(`[close] stale ws for ${nodeID.substring(0, 16)}... (already replaced)`);
    return;
  }

  peers.delete(nodeID);
  rateLimits.delete(nodeID);
  console.log(`[close] removed ${nodeID.substring(0, 16)}... peers_after=${peers.size}`);
}

const server = Bun.serve({
  port,
  fetch(req, server) {
    const url = new URL(req.url);
    if (url.pathname === "/health") {
      return Response.json({
        ok: true,
        peers: peers.size
      });
    }

    if (url.pathname === "/metrics") {
      const now = Date.now();
      const elapsed = (now - lastMinuteTimestamp) / 1000;
      const messagesPerMinute = elapsed > 0
        ? Math.round(((messageCount - messageCountAtLastMinute) / elapsed) * 60)
        : 0;
      messageCountAtLastMinute = messageCount;
      lastMinuteTimestamp = now;

      return Response.json({
        peers: peers.size,
        messagesPerMinute,
        relaySessionsActive: relaySessionCount,
        uptimeSeconds: Math.round((now - startTime) / 1000),
        totalMessages: messageCount
      });
    }

    if (url.pathname === "/peers") {
      const peerList = Array.from(peers.values()).map(p => ({
        nodeID: p.nodeID.substring(0, 16) + "...",
        displayName: p.displayName,
        wgPublicKey: p.wgPublicKey ? p.wgPublicKey.substring(0, 16) + "..." : null,
        lastSeen: p.lastSeenReferenceSeconds,
      }));
      return Response.json({ peers: peerList });
    }

    if (url.pathname === "/ws" && server.upgrade(req)) {
      return;
    }

    return new Response("Not found", { status: 404 });
  },
  websocket: {
    message(ws, message) {
      handleMessage(ws, message);
    },
    close(ws) {
      handleClose(ws);
    }
  }
});

console.log(`relay listening on :${server.port}`);
