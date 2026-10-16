// widget-sw.js - LE FILET DU WIDGET. Le seul service que ce fichier rend est celui que
// Chrome demande pour INSTALLER la page sur l'ecran d'accueil : un gestionnaire de fetch.
// Il ne met RIEN en cache : la machine EST le serveur, et une page servie du cache serait
// une page morte qui a l'air vivante.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => { /* le reseau seul */ });
