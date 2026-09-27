const CACHE='jsf-mafigo-v2-20260926';
const CORE=['./','./index.html','./manifest.webmanifest','./assets/1000342094(2).png','./assets/jsf-mafigo-logo.png','./assets/jsf-banner.png','./assets/martha-eva-flores-ramos.jpg','./assets/carlos-salazar-ramos.jpg','./assets/martha-eva-salazar-flores.jpg','./assets/julio-cesar-salazar-flores.png'];
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET') return;
  const u=new URL(e.request.url);
  if(u.origin===location.origin){
    e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request).then(res=>{const copy=res.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));return res}).catch(()=>caches.match('./index.html'))));
  }
});
