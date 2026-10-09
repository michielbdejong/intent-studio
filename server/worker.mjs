// This module is bundled with the Elm application by scripts/build-worker.mjs.
export default {
  async fetch(request,env) {
    const url=new URL(request.url);
    if(url.pathname==='/api/regenerate') return handleRegenerate(request,env);
    if(url.pathname==='/api/status') return new Response(JSON.stringify({configured:Boolean(env.OPENAI_API_KEY)}),{headers:{'content-type':'application/json','cache-control':'no-store'}});
    const asset=ASSETS[url.pathname==='/'?'/index.html':url.pathname];
    if(!asset) return new Response('Not found',{status:404});
    if(!['GET','HEAD'].includes(request.method)) return new Response('Method not allowed',{status:405});
    return new Response(request.method==='HEAD'?null:asset.body,{headers:{'content-type':asset.type,'cache-control':'no-cache','x-content-type-options':'nosniff'}});
  }
};
