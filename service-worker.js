const CACHE='jsf-mafigo-v3-20260926';
const CORE=[
  './',
  './index.html',
  './manifest.webmanifest',
  './assets/1000342094(2).png',
  './assets/jsf-mafigo-logo.png',
  './assets/jsf-banner.png',
  './assets/martha-eva-flores-ramos.jpg',
  './assets/carlos-salazar-ramos.jpg',
  './assets/martha-eva-salazar-flores.jpg',
  './assets/julio-cesar-salazar-flores.png'
];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys().then(keys=>Promise.all(
      keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))
    )).then(()=>self.clients.claim())
  );
});
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET')return;
  const u=new URL(event.request.url);
  if(u.origin!==location.origin)return;

  // HTML/navegación: siempre intentar la versión publicada primero.
  if(event.request.mode==='navigate' || u.pathname.endsWith('/index.html') || u.pathname==='/'){
    event.respondWith(
      fetch(event.request,{cache:'no-store'})
        .then(res=>{
          const copy=res.clone();
          caches.open(CACHE).then(c=>c.put('./index.html',copy)).catch(()=>{});
          return res;
        })
        .catch(()=>caches.match(event.request).then(r=>r||caches.match('./index.html')))
    );
    return;
  }

  // Activos locales: caché primero, red como respaldo.
  event.respondWith(
    caches.match(event.request).then(r=>r||fetch(event.request).then(res=>{
      const copy=res.clone();
      caches.open(CACHE).then(c=>c.put(event.request,copy)).catch(()=>{});
      return res;
    }))
  );
});
