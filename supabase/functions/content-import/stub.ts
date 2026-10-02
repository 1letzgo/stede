// Ruhezustand zwischen Importen (Skill `new-region-app` deployt kurzzeitig index.ts mit Einmal-Token).
Deno.serve(() => new Response("gone", { status: 410 }));
