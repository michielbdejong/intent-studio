import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {handleRegenerate} from '../server/regenerate.mjs';
const types={'.html':'text/html','.js':'application/javascript','.css':'text/css'};
createServer(async(req,res)=>{
  const url=new URL(req.url,'http://localhost:8765');
  try {
    if(url.pathname==='/api/regenerate'){
      const chunks=[];for await (const c of req)chunks.push(c);
      const headers=new Headers(req.headers);headers.set('oai-authenticated-user-id','local-preview');
      const response=await handleRegenerate(new Request(url,{method:req.method,headers,body:Buffer.concat(chunks)}),process.env);
      res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text());return;
    }
    if(url.pathname==='/api/status'){res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({configured:!!process.env.OPENAI_API_KEY}));return;}
    const file=url.pathname==='/'?'index.html':url.pathname.slice(1);
    if(!['index.html','elm.js','bridge.js','style.css'].includes(file)){res.writeHead(404);res.end();return;}
    res.writeHead(200,{'content-type':types[file.slice(file.lastIndexOf('.'))],'cache-control':'no-store'});res.end(await readFile('dist/'+file));
  }catch{res.writeHead(500);res.end('Preview error');}
}).listen(8765,'127.0.0.1',()=>console.log('Local: http://localhost:8765'));
